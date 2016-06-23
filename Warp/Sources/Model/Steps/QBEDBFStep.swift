import Foundation
import WarpCore

final class QBEDBFStream: NSObject, WarpCore.Stream {
	let url: URL

	private var queue = DispatchQueue(label: "nl.pixelspark.Warp.QBEDBFStream", attributes: DispatchQueueAttributes.serial)
	private let handle: DBFHandle?
	private let recordCount: Int32
	private let fieldCount: Int32
	private var columns: [Column]? = nil
	private var types: [DBFFieldType]? = nil
	private var position: Int32 = 0

	init(url: URL) {
		self.url = url
		self.handle = DBFOpen((url as NSURL).fileSystemRepresentation, "rb")
		if self.handle == nil {
			self.fieldCount = 0
			self.recordCount = 0
		}
		else {
			self.recordCount = DBFGetRecordCount(self.handle)
			self.fieldCount = DBFGetFieldCount(self.handle)
		}
	}

	deinit {
		DBFClose(handle)
	}

	func columns(_ job: Job, callback: (Fallible<[Column]>) -> ()) {
		if self.columns == nil {
			let fieldCount = self.fieldCount
			var fields: [Column] = []
			var types: [DBFFieldType] = []
			for i in 0..<fieldCount {
				var fieldName =  [CChar](repeating: 0, count: 12)
				let type = DBFGetFieldInfo(handle, i, &fieldName, nil, nil)
				if let fieldNameString = String(cString: fieldName, encoding: String.Encoding.utf8) {
					fields.append(Column(fieldNameString))
					types.append(type)
				}
			}
			self.types = types
			columns = fields
		}

		callback(.success(columns!))
	}

	func fetch(_ job: Job, consumer: Sink) {
		(self.queue).async {
			self.columns(job) { (columns) -> () in
				let end = min(self.recordCount, self.position + StreamDefaultBatchSize)

				var rows: [Tuple] = []
				for recordIndex in self.position..<end {
					if DBFIsRecordDeleted(self.handle, recordIndex) == 0 {
						var row: Tuple = []
						for fieldIndex in 0..<self.fieldCount {
							if DBFIsAttributeNULL(self.handle, recordIndex, fieldIndex) != 0 {
								row.append(Value.empty)
							}
							else {
								switch self.types![Int(fieldIndex)].rawValue {
									case FTString.rawValue:
										if let s = String(cString: DBFReadStringAttribute(self.handle, recordIndex, fieldIndex), encoding: String.Encoding.utf8) {
											row.append(Value.string(s))
										}
										else {
											row.append(Value.invalid)
										}

									case FTInteger.rawValue:
										row.append(Value.int(Int(DBFReadIntegerAttribute(self.handle, recordIndex, fieldIndex))))

									case FTDouble.rawValue:
										row.append(Value.double(DBFReadDoubleAttribute(self.handle, recordIndex, fieldIndex)))

									case FTInvalid.rawValue:
										row.append(Value.invalid)

									case FTLogical.rawValue:
										// TODO: this needs to be translated to a BoolValue. However, no idea how logical values are stored in DBF..
										row.append(Value.invalid)

									default:
										row.append(Value.invalid)
								}
							}
						}

						rows.append(row)
					}
				}

				self.position = end
				job.async {
					consumer(.success(Array(rows)), (self.position < (self.recordCount-1)) ? .hasMore : .finished)
				}
			}
		}
	}

	func clone() -> WarpCore.Stream {
		return QBEDBFStream(url: self.url)
	}
}

class QBEDBFWriter: NSObject, NSCoding, QBEFileWriter {
	class func explain(_ fileExtension: String, locale: Language) -> String {
		return NSLocalizedString("dBase III", comment: "")
	}

	class var fileTypes: Set<String> { get {
		return Set<String>(["dbf"])
	} }

	required init(locale: Language, title: String?) {
	}

	func encode(with aCoder: NSCoder) {
	}

	required init?(coder aDecoder: NSCoder) {
	}

	func writeDataset(_ data: Dataset, toFile file: URL, locale: Language, job: Job, callback: (Fallible<Void>) -> ()) {
		let stream = data.stream()

		let handle = DBFCreate((file as NSURL).fileSystemRepresentation)
		var rowIndex = 0

		// Write column headers
		stream.columns(job) { (columns) -> () in
			switch columns {
			case .success(let cns):
				var fieldIndex = 0
				for col in cns {
					// make field
					if let name = col.name.cString(using: String.Encoding.utf8) {
						DBFAddField(handle, name, FTString, 255, 0)
					}
					else {
						let name = "COL\(fieldIndex)"
						DBFAddField(handle, name.cString(using: String.Encoding.utf8)!, FTString, 255, 0)
					}
					fieldIndex += 1
				}

				let dbfMutex = Mutex()

				var cb: Sink? = nil
				cb = { (rows: Fallible<Array<Tuple>>, streamStatus: StreamStatus) -> () in
					switch rows {
					case .success(let rs):
						// We want the next row, so fetch it while we start writing this one.
						if streamStatus == .hasMore {
							job.async {
								stream.fetch(job, consumer: cb!)
							}
						}

						job.time("Write DBF", items: rs.count, itemType: "rows") {
							dbfMutex.locked {
								for row in rs {
									var cellIndex = 0
									for cell in row {
										if let s = cell.stringValue?.cString(using: String.Encoding.utf8) {
											DBFWriteStringAttribute(handle, Int32(rowIndex), Int32(cellIndex), s)
										}
										else {
											DBFWriteNULLAttribute(handle, Int32(rowIndex), Int32(cellIndex))
										}
										// write field
										cellIndex += 1
									}
									rowIndex += 1
								}
							}
						}

						if streamStatus == .finished {
							dbfMutex.locked {
								DBFClose(handle)
							}
							callback(.success())
						}

					case .failure(let e):
						callback(.failure(e))
					}
				}

				stream.fetch(job, consumer: cb!)

			case .failure(let e):
				callback(.failure(e))
			}
		}
	}

	func sentence(_ locale: Language) -> QBESentence? {
		return nil
	}
}

class QBEDBFSourceStep: QBEStep {
	var file: QBEFileReference? = nil

	required init() {
		super.init()
	}

	init(url: URL) {
		self.file = QBEFileReference.absolute(url)
		super.init()
	}

	required init(coder aDecoder: NSCoder) {
		let d = aDecoder.decodeObject(forKey: "fileBookmark") as? Data
		let u = aDecoder.decodeObject(forKey: "fileURL") as? URL
		self.file = QBEFileReference.create(u, d)
		super.init(coder: aDecoder)
	}

	deinit {
		self.file?.url?.stopAccessingSecurityScopedResource()
	}

	private func sourceDataset() -> Fallible<Dataset> {
		if let url = file?.url {
			let s = QBEDBFStream(url: url as URL)
			return .success(StreamDataset(source: s))
		}
		else {
			return .failure(NSLocalizedString("The location of the DBF source file is invalid.", comment: ""))
		}
	}

	override func fullDataset(_ job: Job, callback: (Fallible<Dataset>) -> ()) {
		callback(sourceDataset())
	}

	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Dataset>) -> ()) {
		callback(sourceDataset().use({ d in return d.limit(maxInputRows) }))
	}

	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(self.file?.url, forKey: "fileURL")
		coder.encode(self.file?.bookmark, forKey: "fileBookmark")
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let fileTypes = [
			"dbf"
		]

		return QBESentence(format: NSLocalizedString("Read DBF file [#]", comment: ""),
			QBESentenceFile(file: self.file, allowedFileTypes: fileTypes, callback: { [weak self] (newFile) -> () in
				self?.file = newFile
			})
		)
	}

	override func willSaveToDocument(_ atURL: URL) {
		self.file = self.file?.persist(atURL)
	}

	override func didLoadFromDocument(_ atURL: URL) {
		self.file = self.file?.resolve(atURL)
		if let b = self.file?.url?.startAccessingSecurityScopedResource() where !b {
			trace("startAccessingSecurityScopedResource failed for \(self.file?.url)")
		}
	}
}
