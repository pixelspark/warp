import Foundation

class QBEReplaceStep: QBEStep {
	var replaceValue: QBEValue
	var withValue: QBEValue
	var inColumn: String
	
	init(previous: QBEStep?, explanation: String, replaceValue: QBEValue, withValue: QBEValue, inColumn: String) {
		self.replaceValue = replaceValue
		self.withValue = withValue
		self.inColumn = inColumn
		super.init(previous: previous, explanation: explanation)
	}
	
	required init(coder aDecoder: NSCoder) {
		self.replaceValue = aDecoder.decodeObjectForKey("replaceValue") as? QBEValue ?? QBEValue()
		self.withValue = aDecoder.decodeObjectForKey("withValue") as? QBEValue ?? QBEValue()
		self.inColumn = aDecoder.decodeObjectForKey("inColumn") as? String ?? ""
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(replaceValue, forKey: "replaceValue")
		coder.encodeObject(withValue, forKey: "withValue")
		coder.encodeObject(inColumn, forKey: "inColumn")
	}
	
	override func apply(data: QBEData?) -> QBEData? {
		return data?.replace(replaceValue, withValue: withValue, inColumn: inColumn)
	}
}