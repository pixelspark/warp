import Foundation

class QBECSVStream: NSObject, QBEStream, CHCSVParserDelegate {
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
	let locale: QBELocale
	
	init(url: NSURL, fieldSeparator: unichar, hasHeaders: Bool, locale: QBELocale) {
		self.url = url
		self.hasHeaders = hasHeaders
		self.fieldSeparator = fieldSeparator
		self.locale = locale
		
		// Get total file size
		if let p = url.path {
			var error: NSError?
			if let attributes = NSFileManager.defaultManager().attributesOfItemAtPath(p, error: &error) {
				totalBytes = (attributes[NSFileSize] as? NSNumber)?.integerValue ?? 0
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
	
	func columnNames(job: QBEJob, callback: ([QBEColumn]) -> ()) {
		callback(_columnNames)
	}
	
	func fetch(job: QBEJob, consumer: QBESink) {
		dispatch_async(queue) {
			job.time("Parse CSV", items: QBEStreamDefaultBatchSize, itemType: "row") {
				var fetched = 0
				while !self.finished && (fetched < QBEStreamDefaultBatchSize) {
					self.finished = !self.parser._parseRecord()
					fetched++
				}
			
				// Calculate progress
				self.rowsRead += fetched
				let progress = Double(self.parser.totalBytesRead) / Double(self.totalBytes)
				job.reportProgress(progress, forKey: self.hashValue);
			}
			
			let r = ArraySlice(self.rows)
			self.rows.removeAll(keepCapacity: true)
			consumer(r, !self.finished)
		}
	}
	
	func parser(parser: CHCSVParser, didBeginLine line: UInt) {
		row = templateRow
	}
	
	func parser(parser: CHCSVParser, didEndLine line: UInt) {
		rows.append(row)
	}
	
	func parser(parser: CHCSVParser, didReadField field: String, atIndex index: Int) {
		let value = locale.valueForLocalString(field)
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

class QBECSVWriter: QBEFileWriter, NSStreamDelegate {
	var separatorCharacter: UInt16
	var newLineCharacter: String?

	required init(locale: QBELocale, title: String? = nil) {
		self.newLineCharacter = "\r\n"
		let separator = QBESettings.sharedInstance.defaultFieldSeparator
		self.separatorCharacter = separator.utf16[separator.utf16.startIndex]
		super.init(locale: locale, title: title)
	}
	
	func writeHeader(toStream: NSOutputStream) {
		// Not used
	}
	
	func writeFooter(toStream: NSOutputStream) {
		// Not used
	}
	
	override func writeData(data: QBEData, toFile file: NSURL, job: QBEJob, callback: () -> ()) {
		let stream = data.stream()

		if let outStream = NSOutputStream(toFileAtPath: file.path!, append: false) {
			let csvOut = CHCSVWriter(outputStream: outStream, encoding: NSUTF8StringEncoding, delimiter: separatorCharacter)
			writeHeader(outStream)
			
			// If a custom new line character is set, use that instead of the default
			if let nl = newLineCharacter {
				csvOut.newlineCharacter = nl
			}
			
			// Write column headers
			stream.columnNames(job) { (columnNames) -> () in
				for col in columnNames {
					csvOut.writeField(col.name)
				}
				csvOut.finishLine()
				
				var cb: QBESink? = nil
				cb = { (rows: ArraySlice<QBETuple>, hasNext: Bool) -> () in
					// We want the next row, so fetch it while we start writing this one.
					if hasNext {
						job.async {
							stream.fetch(job, consumer: cb!)
						}
					}
					
					job.time("Write CSV", items: rows.count, itemType: "rows") {
						for row in rows {
							for cell in row {
								csvOut.writeField(self.locale.localStringFor(cell))
							}
							csvOut.finishLine()
						}
					}
					
					if !hasNext {
						self.writeFooter(outStream)
						csvOut.closeStream()
						callback()
					}
				}
				
				stream.fetch(job, consumer: cb!)
			}
		}
	}
}

class QBEHTMLWriter: QBECSVWriter {
	let header: String
	let footer: String
	
	required init(locale: QBELocale, title: String? = nil) {
		// Get pivot template from resources
		if let path = NSBundle.mainBundle().pathForResource("pivot", ofType: "html") {
			var error: NSError? = nil
			if let template = NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding, error: &error) {
				let template = template.stringByReplacingOccurrencesOfString("$$$TITLE$$$", withString: title ?? "")
				let parts = template.componentsSeparatedByString("$$$CSV$$$")
				header = parts[0]
				footer = parts[1]
				let separatorString = ","
				let separatorCharacter = separatorString.utf16[separatorString.utf16.startIndex]
				
				let locale = QBELocale()
				locale.numberFormatter.perMillSymbol = ""
				locale.numberFormatter.decimalSeparator = "."
				super.init(locale: locale, title: title)
				return
			}
		}
		header = ""
		footer = ""
		super.init(locale: locale, title: title)
	}
	
	override func writeHeader(toStream: NSOutputStream) {
		if let data = header.dataUsingEncoding(NSUTF8StringEncoding) {
			toStream.write(UnsafePointer<UInt8>(data.bytes), maxLength: data.length)
		}
	}
	
	override func writeFooter(toStream: NSOutputStream) {
		if let data = footer.dataUsingEncoding(NSUTF8StringEncoding) {
			toStream.write(UnsafePointer<UInt8>(data.bytes), maxLength: data.length)
		}
	}
}

class QBECSVSourceStep: QBEStep {
	private var cachedData: QBEData?
	
	var file: QBEFileReference? { didSet {
		if let o = oldValue, let f = file where o == f {
			return;
		}
		cachedData = nil;
		self.useCaching = self.cachingAllowed
	} }
	
	var fieldSeparator: unichar { didSet {
		if oldValue != fieldSeparator {
			cachedData = nil;
		}
	} }
	
	var hasHeaders: Bool { didSet {
		if oldValue != hasHeaders {
			cachedData = nil;
		}
	} }
	
	var useCaching: Bool { didSet {
		if oldValue != useCaching {
			if let d = cachedData as? QBESQLiteCachedData {
				d.cacheJob.cancel()
			}
			cachedData = nil;
		}
	} }
	
	var isCached: Bool { get {
		if useCaching {
			if let d = cachedData as? QBESQLiteCachedData {
				return d.isCached
			}
		}
		return false
	} }
	
	var cacheJob: QBEJob? { get {
		if useCaching, let d = cachedData as? QBESQLiteCachedData {
			return d.cacheJob
		}
		return nil
	} }
	
	init(url: NSURL) {
		let defaultSeparator = QBESettings.sharedInstance.defaultFieldSeparator
		
		self.file = QBEFileReference.URL(url)
		self.fieldSeparator = defaultSeparator.utf16[defaultSeparator.utf16.startIndex]
		self.hasHeaders = true
		self.useCaching = false
		
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
		super.init(coder: aDecoder)
	}
	
	deinit {
		self.file?.url?.stopAccessingSecurityScopedResource()
	}
	
	/** Get size of the selected file to determine whether caching should be enabled by default **/
	private var cachingAllowed: Bool { get {
		var error: NSError?
		if let url = self.file?.url {
			if let attributes = NSFileManager.defaultManager().attributesOfItemAtPath(url.path!, error: &error) {
				if let size = attributes[NSFileSize] as? NSNumber {
					/* SQLite files are often a bit larger than the source CSV. If we are allowed to cache 1.5x the
					original file size, then proceed by caching the CSV in SQLite */
					return QBESettings.sharedInstance.shouldCacheFile(ofEstimatedSize: Int(size) * 3 / 2, atLocation: url)
				}
			}
		}
		return false
	} }
	
	override func fullData(job: QBEJob?, callback: (QBEData) -> ()) {
		if cachedData == nil {
			if let url = file?.url {
				let locale = QBEAppDelegate.sharedInstance.locale
				let s = QBECSVStream(url: url, fieldSeparator: fieldSeparator, hasHeaders: hasHeaders, locale: locale)
				cachedData = QBEStreamData(source: s)
				if useCaching {
					cachedData = QBESQLiteCachedData(source: cachedData!, locale: locale)
				}
				cachedData = QBECoalescedData(cachedData!)
				callback(cachedData!)
			}
		}
		else {
			callback(cachedData!)
		}
	}
	
	override func exampleData(job: QBEJob?, maxInputRows: Int, maxOutputRows: Int, callback: (QBEData) -> ()) {
		self.fullData(job, callback: { (fullData) -> () in
			callback(fullData.limit(maxInputRows))
		})
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		
		let separator = String(Character(UnicodeScalar(fieldSeparator)))
		coder.encodeObject(separator, forKey: "fieldSeparator")
		coder.encodeBool(hasHeaders, forKey: "hasHeaders")
		coder.encodeBool(useCaching, forKey: "useCaching")
		coder.encodeObject(self.file?.url, forKey: "fileURL")
		coder.encodeObject(self.file?.bookmark, forKey: "fileBookmark")
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("Load CSV", comment: "")
		}
		
		if let f = file {
			switch f {
				case .URL(let u):
					return String(format: NSLocalizedString("Load CSV file '%@'",comment: ""), u.lastPathComponent ?? "")
				
				default:
					break
			}
		}
		return NSLocalizedString("Load CSV", comment: "")
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
			self.fullData(nil, callback: { (data) -> () in
				if let c = callback {
					c()
				}
			})
		}
	}
}