import Foundation

class QBECalculateStep: QBEStep {
	var function: QBEExpression
	var targetColumn: QBEColumn
	
	required init(coder aDecoder: NSCoder) {
		function = aDecoder.decodeObjectForKey("function") as? QBEExpression ?? QBEIdentityExpression()
		targetColumn = QBEColumn(aDecoder.decodeObjectForKey("targetColumn") as? String ?? "")
		super.init(coder: aDecoder)
	}
	
	override func explain(locale: QBELocale) -> String {
		return String(format: NSLocalizedString("Calculate column %@ as %@", comment: ""), targetColumn.name, function.explain(locale))
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(function, forKey: "function")
		coder.encodeObject(targetColumn.name, forKey: "targetColumn")
		super.encodeWithCoder(coder)
	}
	
	required init(previous: QBEStep?, targetColumn: QBEColumn, function: QBEExpression) {
		self.function = function
		self.targetColumn = targetColumn
		super.init(previous: previous)
	}
	
	override func apply(data: QBEData?, callback: (QBEData?) -> ()) {
		callback(data?.calculate([targetColumn: function]))
	}
}