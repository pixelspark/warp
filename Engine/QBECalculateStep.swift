import Foundation

class QBECalculateStep: QBEStep {
	var function: QBEFunction
	var targetColumn: String
	
	required init(coder aDecoder: NSCoder) {
		function = aDecoder.decodeObjectForKey("function") as? QBEFunction ?? QBEIdentityFunction()
		targetColumn = aDecoder.decodeObjectForKey("targetColumn") as? String ?? ""
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(function, forKey: "function")
		coder.encodeObject(targetColumn, forKey: "targetColumn")
		super.encodeWithCoder(coder)
	}
	
	required init(previous: QBEStep?, explanation: String, targetColumn: String, function: QBEFunction) {
		self.function = function
		self.targetColumn = targetColumn
		super.init(previous: previous, explanation: explanation)
	}
	
	override func apply(data: QBEData?) -> QBEData? {
		return data?.calculate(targetColumn, formula: function)
	}
}