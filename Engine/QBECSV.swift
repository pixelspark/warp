import Foundation

class QBERasterCSVReader: NSObject, CHCSVParserDelegate {
    var raster = QBERaster()
    var row : [QBEValue] = []
	let limit: Int?
	var limitAchieved = false
	
	init(limit: Int? = nil) {
		self.limit = limit
	}
	
    func parser(parser: CHCSVParser, didBeginLine line: UInt) {
		if (limit? != nil) && limit! < (Int(line)-2) {
			parser.cancelParsing()
			limitAchieved = true
		}
        row = []
    }
    
    func parser(parser: CHCSVParser, didEndLine line: UInt) {
        raster.raster.append(row)
        row = []
    }
    
    func parser(parser: CHCSVParser, didReadField field: String, atIndex index: Int) {
        row.append(QBEValue(field))
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
		// FIXME: Very naive implementation...
		var csv = ""
		
		data.stream({ (rows: [[QBEValue]]) -> () in
			for row in rows {
				csv += self.locale.csvRow(row)
			}
		})
		
		var error: NSError?
		csv.writeToURL(file, atomically: true, encoding: NSUTF8StringEncoding, error: &error)
		println("Write csv: \(error)")
	}
}

class QBECSVSourceStep: QBERasterStep {
	var url: String
	
	init(url: NSURL) {
		self.url = url.absoluteString ?? ""
		super.init()
		super.explanation = NSAttributedString(string: NSLocalizedString("Load CSV file from",comment: "") + " " + (url.absoluteString ?? ""))
		read(url)
	}
	
	class private func readCSV(atURL url: NSURL, limit: Int?) -> QBERaster {
		let inStream = NSInputStream(URL: url)
		let parser = CHCSVParser(contentsOfCSVURL: url)
		let reader = QBERasterCSVReader(limit: limit)
		parser.delegate = reader
		parser.parse()
		return reader.raster
	}
	
	private func read(url: NSURL) {
		let r = QBECSVSourceStep.readCSV(atURL: url, limit: 100)
		super.staticExampleData = QBERasterData(raster: r)

		let s = QBECSVSourceStep.readCSV(atURL: url, limit: nil)
		super.staticFullData = QBERasterData(raster: s)
	}
	
	required init(coder aDecoder: NSCoder) {
		self.url = aDecoder.decodeObjectForKey("url") as? String ?? ""
		super.init(coder: aDecoder)
		if let url = NSURL(string: self.url) {
			read(url)
		}
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(url, forKey: "url")
	}
}