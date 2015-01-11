import Foundation

class QBEReplaceStep: QBEStep {
	var replaceValue: QBEValue
	var withValue: QBEValue
	var inColumn: QBEColumn
	
	init(previous: QBEStep?, explanation: String, replaceValue: QBEValue, withValue: QBEValue, inColumn: QBEColumn) {
		self.replaceValue = replaceValue
		self.withValue = withValue
		self.inColumn = inColumn
		super.init(previous: previous, explanation: explanation)
	}
	
	required init(coder aDecoder: NSCoder) {
		self.replaceValue = (aDecoder.decodeObjectForKey("replaceValue") as? QBEValueCoder ?? QBEValueCoder()).value
		self.withValue = (aDecoder.decodeObjectForKey("withValue") as? QBEValueCoder ?? QBEValueCoder()).value
		self.inColumn = QBEColumn(aDecoder.decodeObjectForKey("inColumn") as? String ?? "")
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(QBEValueCoder(replaceValue), forKey: "replaceValue")
		coder.encodeObject(QBEValueCoder(withValue), forKey: "withValue")
		coder.encodeObject(inColumn.name, forKey: "inColumn")
	}
	
	override func apply(data: QBEData?) -> QBEData? {
		return data?.replace(replaceValue, withValue: withValue, inColumn: inColumn)
	}
}