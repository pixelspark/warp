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

class QBECSVSourceStep: QBERasterStep {
	var url: String
	
	init(url: NSURL) {
		self.url = url.absoluteString ?? ""
		super.init()
		super.explanation = NSAttributedString(string: NSLocalizedString("Load CSV file from",comment: "") + " " + (url.absoluteString ?? ""))
		read(url)
	}
	
	class private func readCSV(atURL url: NSURL, limit: Int?) -> (QBERaster, Bool) {
		let inStream = NSInputStream(URL: url)
		let parser = CHCSVParser(contentsOfCSVURL: url)
		let reader = QBERasterCSVReader(limit: limit)
		parser.delegate = reader
		parser.parse()
		return (reader.raster, reader.limitAchieved)
	}
	
	private func read(url: NSURL) {
		let (r, limitAchieved) = QBECSVSourceStep.readCSV(atURL: url, limit: 100)
		super.staticExampleData = QBERasterData(raster: r)
		if limitAchieved {
			super.staticFullData = QBERasterData(raster: QBECSVSourceStep.readCSV(atURL: url, limit: nil).0)
		}
		else {
			super.staticFullData = super.staticExampleData
		}
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