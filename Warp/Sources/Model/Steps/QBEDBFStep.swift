/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore
import WarpConduit

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

	func writeDataset(_ data: Dataset, toFile file: URL, locale: Language, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		let stream = data.stream()

		let handle = DBFCreate((file as NSURL).fileSystemRepresentation)

		if handle == nil {
			return callback(.failure("could not create DBF file"))
		}

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
			let s = DBFStream(url: url as URL)
			return .success(StreamDataset(source: s))
		}
		else {
			return .failure(NSLocalizedString("The location of the DBF source file is invalid.", comment: ""))
		}
	}

	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		callback(sourceDataset())
	}

	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
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
			QBESentenceFileToken(file: self.file, allowedFileTypes: fileTypes, callback: { [weak self] (newFile) -> () in
				self?.file = newFile
			})
		)
	}

	override func willSaveToDocument(_ atURL: URL) {
		self.file = self.file?.persist(atURL)
	}

	override func didLoadFromDocument(_ atURL: URL) {
		self.file = self.file?.resolve(atURL)
		if let b = self.file?.url?.startAccessingSecurityScopedResource(), !b {
			trace("startAccessingSecurityScopedResource failed for \(String(describing: self.file?.url))")
		}
	}
}
