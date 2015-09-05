import Foundation
import WarpCore

final class QBECSVStream: NSObject, QBEStream, CHCSVParserDelegate {
	let parser: CHCSVParser
	let url: NSURL

	private var _columnNames: [QBEColumn] = []
	private var finished: Bool = false
	private var templateRow: QBETuple = []
	private var row: QBETuple = []
	private var rows: [QBETuple] = []
	private var queue: dispatch_queue_t
	private var rowsRead: Int = 0
	private var totalBytes: Int = 0
	
	let hasHeaders: Bool
	let fieldSeparator: unichar
	let locale: QBELocale?

	#if DEBUG
	private var totalTime: NSTimeInterval = 0.0
	#endif
	
	init(url: NSURL, fieldSeparator: unichar, hasHeaders: Bool, locale: QBELocale?) {
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
			let columnNames = row.map({QBEColumn($0.stringValue ?? "")})
			_columnNames = []
			
			for columnName in columnNames {
				if _columnNames.contains(columnName) {
					let count = _columnNames.reduce(0, combine: { (n, item) in return n + (item == columnName ? 1 : 0) })
					_columnNames.append(QBEColumn("\(columnName.name)_\(QBEColumn.defaultColumnForIndex(count).name)"))
				}
				else {
					_columnNames.append(columnName)
				}
			}
			
			rows.removeAll(keepCapacity: true)
		}
		else {
			for i in 0..<row.count {
				_columnNames.append(QBEColumn.defaultColumnForIndex(i))
			}
		}
		
		templateRow = Array<QBEValue>(count: _columnNames.count, repeatedValue: QBEValue.InvalidValue)
	}
	
	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		callback(.Success(_columnNames))
	}
	
	func fetch(job: QBEJob, consumer: QBESink) {
		dispatch_async(queue) {
			job.time("Parse CSV", items: QBEStreamDefaultBatchSize, itemType: "row") {
				#if DEBUG
				let startTime = NSDate.timeIntervalSinceReferenceDate()
				#endif
				var fetched = 0
				while !self.finished && (fetched < QBEStreamDefaultBatchSize) {
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
			consumer(.Success(r), !self.finished)
		}
	}

	#if DEBUG
	deinit {
		if self.totalTime > 0 {
			QBELog("Read \(self.parser.totalBytesRead) in \(self.totalTime) ~= \((Double(self.parser.totalBytesRead) / 1024.0 / 1024.0)/self.totalTime) MiB/s")
		}
	}
	#endif
	
	func parser(parser: CHCSVParser, didBeginLine line: UInt) {
		row = templateRow
	}
	
	func parser(parser: CHCSVParser, didEndLine line: UInt) {
		while row.count < _columnNames.count {
			row.append(QBEValue.EmptyValue)
		}
		rows.append(row)
	}
	
	func parser(parser: CHCSVParser, didReadField field: String, atIndex index: Int) {
		let value = locale != nil ? locale!.valueForLocalString(field) : QBELocale.valueForExchangedString(field)
		if index >= row.count {
			row.append(value)
		}
		else {
			row[index] = value
		}
	}
	
	func clone() -> QBEStream {
		return QBECSVStream(url: url, fieldSeparator: fieldSeparator, hasHeaders: self.hasHeaders, locale: self.locale)
	}
}

class QBECSVWriter: NSObject, QBEFileWriter, NSStreamDelegate {
	var separatorCharacter: UInt16
	var newLineCharacter: String
	var title: String?

	class var fileTypes: Set<String> { get { return Set<String>(["csv", "tsv", "tab", "txt"]) } }

	required init(locale: QBELocale, title: String?) {
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
		aCoder.encodeString("separator", forKey: String([self.separatorCharacter]))
	}

	class func explain(locale: QBELocale) -> String {
		return NSLocalizedString("comma separated values (CSV) file", comment: "")
	}

	internal func writeData(data: QBEData, toStream: NSOutputStream, locale: QBELocale, job: QBEJob, callback: (QBEFallible<Void>) -> ()) {
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

				var cb: QBESink? = nil
				cb = { (rows: QBEFallible<Array<QBETuple>>, hasNext: Bool) -> () in
					switch rows {
					case .Success(let rs):
						// We want the next row, so fetch it while we start writing this one.
						if hasNext {
							job.async {
								stream.fetch(job, consumer: cb!)
							}
						}

						job.time("Write CSV", items: rs.count, itemType: "rows") {
							for row in rs {
								for cell in row {
									csvOut.writeField(locale.localStringFor(cell))
								}
								csvOut.finishLine()
							}
						}

						if !hasNext {
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

	func writeData(data: QBEData, toFile file: NSURL, locale: QBELocale, job: QBEJob, callback: (QBEFallible<Void>) -> ()) {
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

	required init(locale: QBELocale, title: String?) {
		let locale = QBELocale()
		locale.numberFormatter.perMillSymbol = ""
		locale.numberFormatter.decimalSeparator = "."
		locale.csvFieldSeparator = ","
		super.init(locale: locale, title: title)
	}

	override class func explain(locale: QBELocale) -> String {
		return NSLocalizedString("HTML pivot table", comment: "")
	}

	override func writeData(data: QBEData, toFile file: NSURL, locale: QBELocale, job: QBEJob, callback: (QBEFallible<Void>) -> ()) {
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
	private var cachedData: QBEFuture<QBEFallible<QBEData>>?
	
	var file: QBEFileReference? { didSet {
		if let o = oldValue, let f = file where o == f {
			return;
		}
		cachedData = nil
		isCached = false
		self.useCaching = self.cachingAllowed
	} }
	
	var fieldSeparator: unichar { didSet {
		if oldValue != fieldSeparator {
			cachedData = nil
			isCached = false
		}
	} }
	
	var interpretLanguage: QBELocale.QBELanguage? { didSet {
		if oldValue != interpretLanguage {
			cachedData = nil
			isCached = false
		}
	} }
	
	var hasHeaders: Bool { didSet {
		if oldValue != hasHeaders {
			cachedData = nil
			isCached = false
		}
	} }
	
	var useCaching: Bool { didSet {
		if oldValue != useCaching {
			cachedData?.cancel()
			cachedData = nil
			isCached = false
		}
	} }
	
	var isCached = false
	
	init(url: NSURL) {
		let defaultSeparator = QBESettings.sharedInstance.defaultFieldSeparator
		
		self.file = QBEFileReference.URL(url)
		self.fieldSeparator = defaultSeparator.utf16[defaultSeparator.utf16.startIndex]
		self.hasHeaders = true
		self.useCaching = false
		self.interpretLanguage = nil
		
		super.init(previous: nil)
		self.useCaching = self.cachingAllowed
	}
	
	required init(coder aDecoder: NSCoder) {
		let d = aDecoder.decodeObjectForKey("fileBookmark") as? NSData
		let u = aDecoder.decodeObjectForKey("fileURL") as? NSURL
		self.file = QBEFileReference.create(u, d)
		
		let separator = (aDecoder.decodeObjectForKey("fieldSeparator") as? String) ?? ";"
		self.fieldSeparator = separator.utf16[separator.utf16.startIndex]
		self.hasHeaders = aDecoder.decodeBoolForKey("hasHeaders")
		self.useCaching = aDecoder.decodeBoolForKey("useCaching")
		self.interpretLanguage = aDecoder.decodeObjectForKey("interpretLanguage") as? QBELocale.QBELanguage
		super.init(coder: aDecoder)
	}
	
	deinit {
		self.file?.url?.stopAccessingSecurityScopedResource()
	}
	
	/** Get size of the selected file to determine whether caching should be enabled by default */
	private var cachingAllowed: Bool { get {
		if let url = self.file?.url {
			do {
				let attributes = try NSFileManager.defaultManager().attributesOfItemAtPath(url.path!)
				if let size = attributes[NSFileSize] as? NSNumber {
					/* SQLite files are often a bit larger than the source CSV. If we are allowed to cache 1.5x the
					original file size, then proceed by caching the CSV in SQLite */
					return QBESettings.sharedInstance.shouldCacheFile(ofEstimatedSize: Int(size) * 3 / 2, atLocation: url)
				}
			}
			catch {
				return false
			}
		}
		return false
	} }
	
	private func sourceData() -> QBEFallible<QBEData> {
		if let url = file?.url {
			let locale: QBELocale? = (interpretLanguage != nil) ? QBELocale(language: interpretLanguage!) : nil
			let s = QBECSVStream(url: url, fieldSeparator: fieldSeparator, hasHeaders: hasHeaders, locale: locale)
			return .Success(QBEStreamData(source: s))
		}
		else {
			return .Failure(NSLocalizedString("The location of the CSV source file is invalid.", comment: ""))
		}
	}
	
	override func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		if cachedData == nil {
			switch sourceData() {
				case .Success(let data):
					if useCaching {
						self.cachedData = QBEFuture<QBEFallible<QBEData>>({ [weak self] (job, cb) -> () in
							let cached = QBESQLiteCachedData(source: data)
							cached.cacheJob.addObserver(job)
							cached.completion = {(result) -> () in
								cb(result.use {(d) -> QBEData in
									self?.isCached = true
									return d.coalesced
								})
							}
						})
					}
					else {
						self.cachedData = QBEFuture<QBEFallible<QBEData>>({ (job, cb) -> () in
							cb(.Success(data.coalesced))
						})
					}
				
				case .Failure(let error):
					callback(.Failure(error))
					return
			}
		}
		
		cachedData!.get(job, callback)
	}
	
	override func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEFallible<QBEData>) -> ()) {
		if isCached {
			self.fullData(job, callback: { (fullData) -> () in
				callback(fullData.use({$0.limit(maxInputRows)}))
			})
		}
		else {
			callback(sourceData().use{ $0.limit(maxInputRows) })
		}
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		
		let separator = String(Character(UnicodeScalar(fieldSeparator)))
		coder.encodeObject(separator, forKey: "fieldSeparator")
		coder.encodeBool(hasHeaders, forKey: "hasHeaders")
		coder.encodeBool(useCaching, forKey: "useCaching")
		coder.encodeObject(self.file?.url, forKey: "fileURL")
		coder.encodeObject(self.file?.bookmark, forKey: "fileBookmark")
		coder.encodeObject(self.interpretLanguage, forKey: "intepretLanguage")
	}

	override func sentence(locale: QBELocale) -> QBESentence {
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
	
	func updateCache(callback: (() -> ())? = nil) {
		cachedData = nil
		if useCaching && cachingAllowed {
			let job = QBEJob(.UserInitiated)
			self.fullData(job, callback: { (data) -> () in
				if let c = callback {
					c()
				}
			})
		}
	}
}