import Foundation

private class QBECSVStream: NSObject, QBEStream, CHCSVParserDelegate {
	let parser: CHCSVParser
	let url: NSURL

	private var _columnNames: [QBEColumn] = []
	private var finished: Bool = false
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
	}
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		callback(_columnNames)
	}
	
	func fetch(consumer: QBESink, job: QBEJob?) {
		dispatch_async(queue) {
			QBETime("Parse CSV", QBEStreamDefaultBatchSize, "row") {
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
			
			let r = self.rows
			self.rows.removeAll(keepCapacity: true)
			consumer(Slice(r), !self.finished)
		}
	}
	
	func parser(parser: CHCSVParser, didBeginLine line: UInt) {
		row.removeAll(keepCapacity: true)
	}
	
	func parser(parser: CHCSVParser, didEndLine line: UInt) {
		rows.append(row)
	}
	
	func parser(parser: CHCSVParser, didReadField field: String, atIndex index: Int) {
		row.append(QBEValue(field))
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
			let csvOut = CHCSVWriter(forWritingToCSVFile: file.path!)
			
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
	private var _exampleData: QBEData?
	var url: String
	var fieldSeparator: unichar
	var hasHeaders: Bool
	
	override func fullData(callback: (QBEData) -> (), job: QBEJob?) {
		if let url = NSURL(string: self.url) {
			let s = QBECSVStream(url: url, fieldSeparator: fieldSeparator, hasHeaders: hasHeaders)
			callback(QBEStreamData(source: s))
		}
	}
	
	override func exampleData(callback: (QBEData) -> (), job: QBEJob?) {
		self.fullData({ (fullData) -> () in
			callback(fullData.limit(100))
		}, job: job)
	}
	
	init(url: NSURL) {
		let defaultSeparator = NSUserDefaults.standardUserDefaults().stringForKey("defaultSeparator") ?? ";"
		
		self.url = url.absoluteString!
		self.fieldSeparator = defaultSeparator.utf16[defaultSeparator.utf16.startIndex]
		self.hasHeaders = true
		super.init(previous: nil)
	}
	
	required init(coder aDecoder: NSCoder) {
		self.url = (aDecoder.decodeObjectForKey("url") as? String) ?? ""
		let separator = (aDecoder.decodeObjectForKey("fieldSeparator") as? String) ?? ";"
		self.fieldSeparator = separator.utf16[separator.utf16.startIndex]
		self.hasHeaders = aDecoder.decodeBoolForKey("hasHeaders")
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(url, forKey: "url")
		
		let separator = String(Character(UnicodeScalar(fieldSeparator)))
		coder.encodeObject(separator, forKey: "fieldSeparator")
		coder.encodeBool(hasHeaders, forKey: "hasHeaders")
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("Load CSV", comment: "")
		}
		return String(format: NSLocalizedString("Load CSV file from '%@' ",comment: ""), url)
	}
}