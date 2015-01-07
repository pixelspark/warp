import Foundation

class QBERasterStep: QBEStep {
	private var staticExampleData: QBERasterData?
	private var staticFullData: QBEData?
	
	init(raster: QBERaster, explanation: String) {
		super.init(previous: nil, explanation: explanation)
		self.staticExampleData = QBERasterData()
		self.staticExampleData?.setRaster(raster)
		self.staticFullData = staticExampleData
	}
	
	required init(coder aDecoder: NSCoder) {
		staticExampleData = aDecoder.decodeObjectForKey("staticData") as? QBERasterData
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(staticExampleData, forKey: "staticData")
		super.encodeWithCoder(coder)
	}
	
	override var fullData: QBEData? { get { return staticFullData }}
	
	override var exampleData: QBEData? { get { return staticExampleData }}
}

class QBECSVSourceStep: QBERasterStep {
	var url: String
	
	init(url: NSURL) {
		self.url = url.absoluteString ?? ""
		let explanation = NSLocalizedString("Load CSV file from",comment: "") + " " + (url.absoluteString ?? "")
		super.init(raster: QBECSVSourceStep.readCSV(atURL: url), explanation: explanation)
	}
	
	class private func readCSV(atURL url: NSURL) -> QBERaster {
		let inStream = NSInputStream(URL: url)
		let parser = CHCSVParser(contentsOfCSVURL: url)
		let reader = QBERasterCSVReader()
		parser.delegate = reader
		parser.parse()
		return reader.raster
	}
	
	required init(coder aDecoder: NSCoder) {
		self.url = aDecoder.decodeObjectForKey("url") as? String ?? ""
		super.init(coder: aDecoder)
		if let url = NSURL(string: self.url) {
			super.staticExampleData = QBERasterData(raster: QBECSVSourceStep.readCSV(atURL: url))
			super.staticFullData = super.staticExampleData
		}
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(url, forKey: "url")
	}
}