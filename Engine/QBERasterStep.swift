import Foundation

class QBERasterStep: QBEStep {
	var staticExampleData: QBERasterData
	var staticFullData: QBEData
	
	init(raster: QBERaster) {
		self.staticExampleData = QBERasterData(raster: raster)
		self.staticFullData = staticExampleData
		super.init(previous: nil)
	}
	
	required init(coder aDecoder: NSCoder) {
		staticExampleData = (aDecoder.decodeObjectForKey("staticExampleData") as? QBERasterData) ?? QBERasterData()
		staticFullData = (aDecoder.decodeObjectForKey("staticFullData") as? QBERasterData) ?? QBERasterData()
		super.init(coder: aDecoder)
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		return NSLocalizedString("Data table", comment: "")
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(staticExampleData, forKey: "staticData")
		super.encodeWithCoder(coder)
	}
	
	override func fullData(job: QBEJob?, callback: (QBEData) -> ()) {
		callback(staticFullData)
	}
	
	override func exampleData(job: QBEJob?, callback: (QBEData) -> ()) {
		callback(staticExampleData)
	}
}