import Foundation

class QBECalculateStep: QBEStep {
	var function: QBEExpression
	var targetColumn: QBEColumn
	
	required init(coder aDecoder: NSCoder) {
		function = (aDecoder.decodeObjectForKey("function") as? QBEExpression) ?? QBEIdentityExpression()
		targetColumn = QBEColumn((aDecoder.decodeObjectForKey("targetColumn") as? String) ?? "")
		super.init(coder: aDecoder)
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("Calculate column", comment: "Short name for calculate step")
		}
		else {
			return String(format: NSLocalizedString("Calculate column %@ as %@", comment: ""), targetColumn.name, function.explain(locale))
		}
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
	
	override func apply(data: QBEData, job: QBEJob?, callback: (QBEData) -> ()) {
		callback(data.calculate([targetColumn: function]))
	}
	
	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		if let p = prior as? QBECalculateStep {
			if p.targetColumn == self.targetColumn && p.function.isConstant && p.function.apply([], columns: [], inputValue: nil) == QBEValue.EmptyValue {
				return QBEStepMerge.Advised(self)
			}
		}
		
		/* TODO: we can merge with a previous calculate step that has the same target column name if this calculation does
		not depend on the previously calculated column. */
		
		return QBEStepMerge.Impossible
	}
	
	class func suggest(change fromValue: QBEValue, toValue: QBEValue, inRaster: QBERaster, row: Int, column: Int, locale: QBELocale) -> [QBEExpression] {
		var suggestions: [QBEExpression] = []
		if fromValue != toValue {
			let targetColumn = inRaster.columnNames[column]
			
			// Was a formula typed in?
			if let f = QBEFormula(formula: toValue.stringValue ?? "", locale: locale) {
				suggestions.append(f.root)
				return suggestions
			}
			else {
				QBEExpression.infer(nil, toValue: toValue, suggestions: &suggestions, level: 6, columns: inRaster.columnNames, row: inRaster[row], column: column)
				// Suggest a text replace
				suggestions.append(QBEFunctionExpression(arguments: [QBEIdentityExpression(), QBELiteralExpression(fromValue), QBELiteralExpression(toValue)], type: QBEFunction.Substitute))
			}
		}
		return suggestions
	}
}