import Foundation

class QBECSVStream: NSObject, QBEStream, CHCSVParserDelegate {
	let parser: CHCSVParser
	let url: NSURL

	private var _columnNames: [QBEColumn] = []
	private var finished: Bool = false
	private var templateRow: QBERow = []
	private var row: QBERow = []
	private var rows: [QBERow] = []
	private var queue: dispatch_queue_t
	private var rowsRead: Int = 0
	private var totalBytes: Int = 0
	
	let hasHeaders: Bool
	let fieldSeparator: unichar
	
	init(url: NSURL, fieldSeparator: unichar, hasHeaders: Bool) {
		self.url = url
		self.hasHeaders = hasHeaders
		self.fieldSeparator = fieldSeparator
		
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
			_columnNames = row.map({QBEColumn($0.stringValue ?? "")})
			rows.removeAll(keepCapacity: true)
		}
		else {
			for i in 0..<row.count {
				_columnNames.append(QBEColumn.defaultColumnForIndex(i))
			}
		}
		
		templateRow = Array<QBEValue>(count: _columnNames.count, repeatedValue: QBEValue.InvalidValue)
	}
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		callback(_columnNames)
	}
	
	func fetch(consumer: QBESink, job: QBEJob?) {
		dispatch_async(queue) {
			QBETime("Parse CSV", QBEStreamDefaultBatchSize, "row", job) {
				var fetched = 0
				while !self.finished && (fetched < QBEStreamDefaultBatchSize) {
					self.finished = !self.parser._parseRecord()
					fetched++
				}
			
				// Calculate progress
				self.rowsRead += fetched
				let progress = Double(self.parser.totalBytesRead) / Double(self.totalBytes)
				job?.reportProgress(progress, forKey: self.hashValue);
			}
			
			let r = Slice(self.rows)
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
		if index >= row.count {
			row.append(QBEValue(field))
		}
		else {
			row[index] = QBEValue(field)
		}
	}
	
	func clone() -> QBEStream {
		return QBECSVStream(url: url, fieldSeparator: fieldSeparator, hasHeaders: self.hasHeaders)
	}
}

protocol QBEFileWriter: NSObjectProtocol {
	func writeToFile(file: NSURL, callback: () -> ())
}

class QBECSVWriter: NSObject, QBEFileWriter, NSStreamDelegate {
	let data: QBEData
	let locale: QBELocale
	
	init(data: QBEData, locale: QBELocale) {
		self.data = data
		self.locale = locale
	}
	
	func writeToFile(file: NSURL, callback: () -> ()) {
		if let stream = data.stream() {
			let separatorString = QBESettings.defaultFieldSeparator
			let separatorChar = separatorString.utf16[separatorString.utf16.startIndex]
			let outStream = NSOutputStream(toFileAtPath: file.path!, append: false)
			let csvOut = CHCSVWriter(outputStream: outStream, encoding: NSUTF8StringEncoding, delimiter: separatorChar)
			
			// Write column headers
			stream.columnNames { (columnNames) -> () in
				for col in columnNames {
					csvOut.writeField(col.name)
				}
				csvOut.finishLine()
				
				var cb: QBESink? = nil
				cb = { (rows: Slice<QBERow>, hasNext: Bool) -> () in
					// We want the next row, so fetch it while we start writing this one.
					if hasNext {
						QBEAsyncBackground {
							stream.fetch(cb!, job: nil)
						}
					}
					
					QBETime("Write CSV", rows.count, "rows") {
						for row in rows {
							for cell in row {
								csvOut.writeField(cell.explain(self.locale))
							}
							csvOut.finishLine()
						}
					}
					
					if !hasNext {
						csvOut.closeStream()
						callback()
					}
				}
				
				stream.fetch(cb!, job: nil)
			}
		}
	}
}

class QBECSVSourceStep: QBEStep {
	private var cachedData: QBEData?
	var file: QBEFileReference? { didSet { cachedData = nil; } }
	var fieldSeparator: unichar { didSet { cachedData = nil; } }
	var hasHeaders: Bool { didSet { cachedData = nil; } }
	var useCaching: Bool { didSet { cachedData = nil; } }
	
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
		let defaultSeparator = QBESettings.defaultFieldSeparator
		
		self.file = QBEFileReference.URL(url)
		self.fieldSeparator = defaultSeparator.utf16[defaultSeparator.utf16.startIndex]
		self.hasHeaders = true
		self.useCaching = false
		super.init(previous: nil)
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
	
	override func fullData(job: QBEJob?, callback: (QBEData) -> ()) {
		if cachedData == nil {
			if let url = file?.url {
				let s = QBECSVStream(url: url, fieldSeparator: fieldSeparator, hasHeaders: hasHeaders)
				cachedData = QBEStreamData(source: s)
				if useCaching {
					cachedData = QBESQLiteCachedData(source: cachedData!)
				}
				callback(cachedData!)
			}
		}
		else {
			callback(cachedData!)
		}
	}
	
	override func exampleData(job: QBEJob?, callback: (QBEData) -> ()) {
		self.fullData(job, callback: { (fullData) -> () in
			callback(fullData.limit(100))
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
		if useCaching {
			self.fullData(nil, callback: { (data) -> () in
				if let c = callback {
					c()
				}
			})
		}
	}
}