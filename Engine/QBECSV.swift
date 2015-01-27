import Foundation

internal class QBECSVStream: NSObject, QBEStream, CHCSVParserDelegate {
	let parser: CHCSVParser
	let url: NSURL

	private var _columnNames: [QBEColumn] = []
	private var finished: Bool = false
	private var row: QBERow = []
	private var rows: [QBERow] = []
	
	let hasHeaders: Bool
	let fieldSeparator: unichar
	
	init(url: NSURL, fieldSeparator: unichar, hasHeaders: Bool) {
		self.url = url
		self.hasHeaders = hasHeaders
		self.fieldSeparator = fieldSeparator
		
		parser = CHCSVParser(contentsOfDelimitedURL: url as NSURL!, delimiter: fieldSeparator)
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
				_columnNames.append(QBEColumn("\(i)"))
			}
		}
	}
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		callback(_columnNames)
	}
	
	func fetch(consumer: QBESink) {
		var fetched = 0
		while !finished && (fetched < QBEStreamDefaultBatchSize) {
			finished = !parser._parseRecord()
			fetched++
		}
		let r = rows
		rows.removeAll(keepCapacity: true)
		consumer(r, !finished)
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

class QBECSVWriter: NSObject, NSStreamDelegate {
	let data: QBEData
	let locale: QBELocale
	
	init(data: QBEData, locale: QBELocale) {
		self.data = data
		self.locale = locale
	}
	
	func writeToFile(file: NSURL) {
		if let stream = data.stream() {
			let csvOut = CHCSVWriter(forWritingToCSVFile: file.path!)
			
			// Write column headers
			stream.columnNames { (columnNames) -> () in
				for col in columnNames {
					csvOut.writeField(col.name)
				}
				csvOut.finishLine()
				
				var cb: QBESink? = nil
				cb = { (rows: [QBERow], hasNext: Bool) -> () in
					println("Stream: got \(rows.count) rows for writing")
					for row in rows {
						for cell in row {
							csvOut.writeField(cell.explain(self.locale))
						}
						csvOut.finishLine()
					}
					
					if hasNext {
						QBEAsyncBackground {
							stream.fetch(cb!)
						}
					}
					else {
						csvOut.closeStream()
					}
				}
				
				stream.fetch(cb!)
			}
		}
	}
}

class QBECSVSourceStep: QBEStep {
	private var _exampleData: QBEData?
	var url: String
	var fieldSeparator: unichar
	var hasHeaders: Bool
	
	override func fullData(callback: (QBEData?) -> ()) {
		if let url = NSURL(string: self.url) {
			let s = QBECSVStream(url: url, fieldSeparator: fieldSeparator, hasHeaders: hasHeaders)
			callback(QBEStreamData(source: s))
		}
		else {
			callback(nil)
		}
	}
	
	override func exampleData(callback: (QBEData?) -> ()) {
		self.fullData { (fullData) -> () in
			callback(fullData?.limit(100))
		}
	}
	
	init(url: NSURL) {
		self.url = url.absoluteString!
		let s = ";"
		self.fieldSeparator = s.utf16[s.utf16.startIndex]
		self.hasHeaders = true
		super.init(previous: nil)
	}
	
	required init(coder aDecoder: NSCoder) {
		self.url = aDecoder.decodeObjectForKey("url") as? String ?? ""
		let separator = aDecoder.decodeObjectForKey("fieldSeparator") as? String ?? ";"
		self.fieldSeparator = separator.utf16[separator.utf16.startIndex]
		self.hasHeaders = aDecoder.decodeBoolForKey("hasHeaders")
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(url, forKey: "url")
		
		let separator = String(fieldSeparator)
		coder.encodeObject(separator, forKey: "fieldSeparator")
		coder.encodeBool(hasHeaders, forKey: "hasHeaders")
	}
	
	override func explain(locale: QBELocale) -> String {
		return String(format: NSLocalizedString("Load CSV file from '%@' ",comment: ""), url)
	}
}