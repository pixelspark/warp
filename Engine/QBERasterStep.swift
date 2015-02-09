import Foundation

class QBERasterStep: QBEStep {
	var staticExampleData: QBERasterData?
	var staticFullData: QBEData?
	
	init(raster: QBERaster) {
		super.init(previous: nil)
		self.staticExampleData = QBERasterData(raster: raster)
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
	
	override func fullData(callback: (QBEData?) -> ()) {
		callback(staticFullData)
	}
	
	override func exampleData(callback: (QBEData?) -> ()) {
		callback(staticExampleData)
	}
}