import Foundation
import WarpCore

final class QBECSVStream: NSObject, Stream, CHCSVParserDelegate {
	let parser: CHCSVParser
	let url: NSURL

	private var _columnNames: [Column] = []
	private var finished: Bool = false
	private var templateRow: [String?] = []
	private var row: [String?] = []
	private var rows: [[String?]] = []
	private var queue: dispatch_queue_t
	private var rowsRead: Int = 0
	private var totalBytes: Int = 0
	
	let hasHeaders: Bool
	let fieldSeparator: unichar
	let locale: Locale?

	#if DEBUG
	private var totalTime: NSTimeInterval = 0.0
	#endif
	
	init(url: NSURL, fieldSeparator: unichar, hasHeaders: Bool, locale: Locale?) {
		self.url = url
		self.hasHeaders = hasHeaders
		self.fieldSeparator = fieldSeparator
		self.locale = locale
		
		// Get total file size
		if let p = url.path {
			do {
				let attributes = try NSFileManager.defaultManager().attributesOfItemAtPath(p)
				totalBytes = (attributes[NSFileSize] as? NSNumber)?.integerValue ?? 0
			}
			catch {
				totalBytes = 0
			}
		}
		
		// Create a queue and initialize the parser
		queue = dispatch_queue_create("nl.pixelspark.qbe.QBECSVStreamQueue", DISPATCH_QUEUE_SERIAL)
		dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0))
		parser = CHCSVParser(contentsOfDelimitedURL: url as NSURL!, delimiter: fieldSeparator)
		parser.sanitizesFields = true
		super.init()
		
		parser.delegate = self
		parser._beginDocument()
		finished = !parser._parseRecord()
		
		if hasHeaders {
			// Load column names, avoiding duplicate names
			let columnNames = row.map({Column($0 ?? "")})
			_columnNames = []
			
			for columnName in columnNames {
				if _columnNames.contains(columnName) {
					let count = _columnNames.reduce(0, combine: { (n, item) in return n + (item == columnName ? 1 : 0) })
					_columnNames.append(Column("\(columnName.name)_\(Column.defaultColumnForIndex(count).name)"))
				}
				else {
					_columnNames.append(columnName)
				}
			}
			
			rows.removeAll(keepCapacity: true)
		}
		else {
			for i in 0..<row.count {
				_columnNames.append(Column.defaultColumnForIndex(i))
			}
		}
		
		templateRow = Array<String?>(count: _columnNames.count, repeatedValue: nil)
	}
	
	func columnNames(job: Job, callback: (Fallible<[Column]>) -> ()) {
		callback(.Success(_columnNames))
	}
	
	func fetch(job: Job, consumer: Sink) {
		dispatch_sync(queue) {
			job.time("Parse CSV", items: StreamDefaultBatchSize, itemType: "row") {
				#if DEBUG
				let startTime = NSDate.timeIntervalSinceReferenceDate()
				#endif
				var fetched = 0
				while !self.finished && (fetched < StreamDefaultBatchSize) && !job.cancelled {
					self.finished = !self.parser._parseRecord()
					fetched++
				}
			
				// Calculate progress
				self.rowsRead += fetched
				let progress = Double(self.parser.totalBytesRead) / Double(self.totalBytes)
				job.reportProgress(progress, forKey: self.hashValue);
				#if DEBUG
				self.totalTime += (NSDate.timeIntervalSinceReferenceDate() - startTime)
				#endif
			}
			
			let r = Array(self.rows)
			self.rows.removeAll(keepCapacity: true)

			job.async {
				/* Convert the read string values to Values. Do this asynchronously because Locale.valueForLocalString 
				may take a lot of time, and we really want the CSV parser to continue meanwhile */
				let v = r.map {(row: [String?]) -> [Value] in
					return row.map { (field: String?) -> Value in
						if let value = field {
							return self.locale != nil ? self.locale!.valueForLocalString(value) : Locale.valueForExchangedString(value)
						}
						return Value.EmptyValue
					}
				}

				consumer(.Success(v), self.finished ? .Finished : .HasMore)
			}
		}
	}

	#if DEBUG
	deinit {
		if self.totalTime > 0 {
			trace("Read \(self.parser.totalBytesRead) in \(self.totalTime) ~= \((Double(self.parser.totalBytesRead) / 1024.0 / 1024.0)/self.totalTime) MiB/s")
		}
	}
	#endif
	
	func parser(parser: CHCSVParser, didBeginLine line: UInt) {
		row = templateRow
	}
	
	func parser(parser: CHCSVParser, didEndLine line: UInt) {
		while row.count < _columnNames.count {
			row.append(nil)
		}
		rows.append(row)
	}
	
	func parser(parser: CHCSVParser, didReadField field: String, atIndex index: Int) {
		if index >= row.count {
			row.append(field)
		}
		else {
			row[index] = field
		}
	}
	
	func clone() -> Stream {
		return QBECSVStream(url: url, fieldSeparator: fieldSeparator, hasHeaders: self.hasHeaders, locale: self.locale)
	}
}

class QBECSVWriter: NSObject, QBEFileWriter, NSStreamDelegate {
	var separatorCharacter: UInt16
	var newLineCharacter: String
	var title: String?

	class var fileTypes: Set<String> { get { return Set<String>(["csv", "tsv", "tab", "txt"]) } }

	required init(locale: Locale, title: String?) {
		self.newLineCharacter = locale.csvLineSeparator
		self.separatorCharacter = locale.csvFieldSeparator.utf16[locale.csvFieldSeparator.utf16.startIndex]
		self.title = title
	}

	required init?(coder aDecoder: NSCoder) {
		self.newLineCharacter = aDecoder.decodeStringForKey("newLine") ?? "\r\n"
		let separatorString = aDecoder.decodeStringForKey("separator") ?? ","
		separatorCharacter = separatorString.utf16[separatorString.utf16.startIndex]
		self.title = aDecoder.decodeStringForKey("title")
	}

	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeString(self.newLineCharacter, forKey: "newLine")
		aCoder.encodeString(String(Character(UnicodeScalar(separatorCharacter))), forKey: "separator")
	}

	func sentence(locale: Locale) -> QBESentence? {
		return QBESentence(format: NSLocalizedString("fields separated by [#]", comment: ""),
			QBESentenceList(value: String(Character(UnicodeScalar(separatorCharacter))), provider: { (pc) -> () in
				pc(.Success(locale.commonFieldSeparators))
			},
			callback: { (newValue) -> () in
				self.separatorCharacter = newValue.utf16[newValue.utf16.startIndex]
			})
		)
	}

	class func explain(fileExtension: String, locale: Locale) -> String {
		switch fileExtension {
			case "csv", "txt":
				return NSLocalizedString("Comma separated values", comment: "")

			case "tsv", "tab":
				return NSLocalizedString("Tab separated values", comment: "")

			default:
				return NSLocalizedString("Comma separated values", comment: "")
		}
	}

	internal func writeData(data: Data, toStream: NSOutputStream, locale: Locale, job: Job, callback: (Fallible<Void>) -> ()) {
		let stream = data.stream()
		let csvOut = CHCSVWriter(outputStream: toStream, encoding: NSUTF8StringEncoding, delimiter: separatorCharacter)
		csvOut.newlineCharacter = self.newLineCharacter

		// Write column headers
		stream.columnNames(job) { (columnNames) -> () in
			switch columnNames {
			case .Success(let cns):
				for col in cns {
					csvOut.writeField(col.name)
				}
				csvOut.finishLine()

				let csvOutMutex = Mutex()

				var cb: Sink? = nil
				cb = { (rows: Fallible<Array<Tuple>>, streamStatus: StreamStatus) -> () in
					switch rows {
					case .Success(let rs):
						// We want the next row, so fetch it while we start writing this one.
						if streamStatus == .HasMore {
							job.async {
								stream.fetch(job, consumer: cb!)
							}
						}

						job.time("Write CSV", items: rs.count, itemType: "rows") {
							csvOutMutex.locked {
								for row in rs {
									for cell in row {
										csvOut.writeField(locale.localStringFor(cell))
									}
									csvOut.finishLine()
								}
							}
						}

						if streamStatus == .Finished {
							callback(.Success())
						}

					case .Failure(let e):
						callback(.Failure(e))
					}
				}

				stream.fetch(job, consumer: cb!)

			case .Failure(let e):
				callback(.Failure(e))
			}
		}
	}

	func writeData(data: Data, toFile file: NSURL, locale: Locale, job: Job, callback: (Fallible<Void>) -> ()) {
		if let outStream = NSOutputStream(toFileAtPath: file.path!, append: false) {
			outStream.open()
			self.writeData(data, toStream: outStream, locale: locale, job: job, callback: { (result) in
				outStream.close()
				callback(result)
			})
		}
		else {
			callback(.Failure("Could not create output stream"))
		}
	}
}

class QBEHTMLWriter: QBECSVWriter {
	override class var fileTypes: Set<String> { get { return Set<String>(["html", "htm"]) } }

	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}

	required init(locale: Locale, title: String?) {
		let locale = Locale()
		locale.numberFormatter.perMillSymbol = ""
		locale.numberFormatter.decimalSeparator = "."
		locale.csvFieldSeparator = ","
		super.init(locale: locale, title: title)
	}

	override class func explain(fileExtension: String, locale: Locale) -> String {
		return NSLocalizedString("Interactive pivot table", comment: "")
	}

	override func writeData(data: Data, toFile file: NSURL, locale: Locale, job: Job, callback: (Fallible<Void>) -> ()) {
		if let outStream = NSOutputStream(toFileAtPath: file.path!, append: false) {
			// Get pivot template from resources
			if let path = NSBundle.mainBundle().pathForResource("pivot", ofType: "html") {
				outStream.open()
				do {
					let template = try NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding).stringByReplacingOccurrencesOfString("$$$TITLE$$$", withString: title ?? "")
					let parts = template.componentsSeparatedByString("$$$CSV$$$")
					let header = parts[0]
					let footer = parts[1]

					if let headerData = header.dataUsingEncoding(NSUTF8StringEncoding) {
						outStream.write(UnsafePointer<UInt8>(headerData.bytes), maxLength: headerData.length)
						super.writeData(data, toStream: outStream, locale: locale, job: job, callback: { (result) -> () in
							switch result {
							case .Success:
								if let footerData = footer.dataUsingEncoding(NSUTF8StringEncoding) {
									outStream.write(UnsafePointer<UInt8>(footerData.bytes), maxLength: footerData.length)
									outStream.close()
									callback(.Success())
									return
								}
								else {
									callback(.Failure("Could not convert footer to UTF-8 data"))
								}

							case .Failure(let e):
								outStream.close()
								callback(.Failure(e))
							}
						})
					}
					else {
						outStream.close()
						callback(.Failure("Could not convert header to UTF-8 data"))
					}
				}
				catch let e as NSError {
					outStream.close()
					callback(.Failure(e.localizedDescription))
				}
			}
			else {
				callback(.Failure("Could not find template"))
			}
		}
		else {
			callback(.Failure("Could not create output stream"))
		}
	}
}

class QBECSVSourceStep: QBEStep {
	var file: QBEFileReference? = nil
	var fieldSeparator: unichar
	var interpretLanguage: Locale.LanguageIdentifier? = nil
	var hasHeaders: Bool = true

	required init() {
		let defaultSeparator = QBESettings.sharedInstance.defaultFieldSeparator
		self.fieldSeparator = defaultSeparator.utf16[defaultSeparator.utf16.startIndex]
		super.init()
	}
	
	init(url: NSURL) {
		let defaultSeparator = QBESettings.sharedInstance.defaultFieldSeparator
		self.file = QBEFileReference.URL(url)
		self.fieldSeparator = defaultSeparator.utf16[defaultSeparator.utf16.startIndex]
		self.hasHeaders = true
		self.interpretLanguage = nil
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		let d = aDecoder.decodeObjectForKey("fileBookmark") as? NSData
		let u = aDecoder.decodeObjectForKey("fileURL") as? NSURL
		self.file = QBEFileReference.create(u, d)
		
		let separator = (aDecoder.decodeObjectForKey("fieldSeparator") as? String) ?? ";"
		self.fieldSeparator = separator.utf16[separator.utf16.startIndex]
		self.hasHeaders = aDecoder.decodeBoolForKey("hasHeaders")
		self.interpretLanguage = aDecoder.decodeObjectForKey("interpretLanguage") as? Locale.LanguageIdentifier
		super.init(coder: aDecoder)
	}
	
	deinit {
		self.file?.url?.stopAccessingSecurityScopedResource()
	}
	
	private func sourceData() -> Fallible<Data> {
		if let url = file?.url {
			let locale: Locale? = (interpretLanguage != nil) ? Locale(language: interpretLanguage!) : nil
			let s = QBECSVStream(url: url, fieldSeparator: fieldSeparator, hasHeaders: hasHeaders, locale: locale)
			return .Success(StreamData(source: s))
		}
		else {
			return .Failure(NSLocalizedString("The location of the CSV source file is invalid.", comment: ""))
		}
	}
	
	override func fullData(job: Job, callback: (Fallible<Data>) -> ()) {
		callback(sourceData())
	}
	
	override func exampleData(job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Data>) -> ()) {
		callback(sourceData().use{ $0.limit(maxInputRows) })
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		
		let separator = String(Character(UnicodeScalar(fieldSeparator)))
		coder.encodeObject(separator, forKey: "fieldSeparator")
		coder.encodeBool(hasHeaders, forKey: "hasHeaders")
		coder.encodeObject(self.file?.url, forKey: "fileURL")
		coder.encodeObject(self.file?.bookmark, forKey: "fileBookmark")
		coder.encodeObject(self.interpretLanguage, forKey: "intepretLanguage")
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		let fileTypes = [
			"public.comma-separated-values-text",
			"public.delimited-values-text",
			"public.tab-separated-values-text",
			"public.text",
			"public.plain-text"
		]

		return QBESentence(format: NSLocalizedString("Read CSV file [#]", comment: ""),
			QBESentenceFile(file: self.file, allowedFileTypes: fileTypes, callback: { [weak self] (newFile) -> () in
				self?.file = newFile
			})
		)
	}
	
	override func willSaveToDocument(atURL: NSURL) {
		self.file = self.file?.bookmark(atURL)
	}
	
	override func didLoadFromDocument(atURL: NSURL) {
		self.file = self.file?.resolve(atURL)
		self.file?.url?.startAccessingSecurityScopedResource()
	}
}