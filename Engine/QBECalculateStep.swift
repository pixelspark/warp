import Foundation

class QBECalculateStep: QBEStep {
	var function: QBEExpression
	var targetColumn: QBEColumn
	var insertAfter: QBEColumn? = nil
	
	required init(coder aDecoder: NSCoder) {
		function = (aDecoder.decodeObjectForKey("function") as? QBEExpression) ?? QBEIdentityExpression()
		targetColumn = QBEColumn((aDecoder.decodeObjectForKey("targetColumn") as? String) ?? "")
		
		if let after = aDecoder.decodeObjectForKey("targetColumn") as? String {
			insertAfter = QBEColumn(after)
		}
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
		coder.encodeObject(insertAfter?.name, forKey: "insertAfter")
		super.encodeWithCoder(coder)
	}
	
	required init(previous: QBEStep?, targetColumn: QBEColumn, function: QBEExpression, insertAfter: QBEColumn? = nil) {
		self.function = function
		self.targetColumn = targetColumn
		self.insertAfter = insertAfter
		super.init(previous: previous)
	}
	
	override func apply(data: QBEData, job: QBEJob?, callback: (QBEData) -> ()) {
		let result = data.calculate([targetColumn: function])
		if let after = insertAfter {
			// Reorder columns in the result set so that targetColumn is inserted after insertAfter
			data.columnNames({(var cns: [QBEColumn]) in
				cns.remove(self.targetColumn)
				if let idx = find(cns, after) {
					cns.insert(self.targetColumn, atIndex: idx+1)
				}
				callback(result.selectColumns(cns))
			})
		}
		else {
			callback(result)
		}
	}
	
	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		// FIXME: what to do with insertAfter?
		if let p = prior as? QBECalculateStep where p.targetColumn == self.targetColumn {
			var dependsOnPrevious = false
			
			// If this function is not constant, it may depend on another column
			if !function.isConstant {
				// Check whether this calculation overwrites the previous result, or depends on its outcome
				self.function.visit({(expr) in
					if let col  = expr as? QBESiblingExpression {
						if col.columnName == p.targetColumn {
							// This expression depends on the column produced by the previous one, hence it cannot overwrite it
							dependsOnPrevious = true
						}
					}
					else if let i = expr as? QBEIdentityExpression {
						dependsOnPrevious = true
					}
				})
			}
			
			if !dependsOnPrevious {
				let after = self.insertAfter ?? p.insertAfter
				return QBEStepMerge.Advised(QBECalculateStep(previous: previous, targetColumn: targetColumn, function: function, insertAfter: after))
			}
		}
		
		/* TODO: we can merge with a previous calculate step that has the same target column name if this calculation does
		not depend on the previously calculated column. */
		
		return QBEStepMerge.Impossible
	}
	
	class func suggest(change fromValue: QBEValue, toValue: QBEValue, inRaster: QBERaster, row: Int, column: Int, locale: QBELocale, job: QBEJob?) -> [QBEExpression] {
		var suggestions: [QBEExpression] = []
		if fromValue != toValue {
			let targetColumn = inRaster.columnNames[column]
			
			// Was a formula typed in?
			if let f = QBEFormula(formula: toValue.stringValue ?? "", locale: locale) {
				suggestions.append(f.root)
				return suggestions
			}
			else {
				QBEExpression.infer(nil, toValue: toValue, suggestions: &suggestions, level: 8, columns: inRaster.columnNames, row: inRaster[row], column: column, job: job)
				// Suggest a text replace
				suggestions.append(QBEFunctionExpression(arguments: [QBEIdentityExpression(), QBELiteralExpression(fromValue), QBELiteralExpression(toValue)], type: QBEFunction.Substitute))
			}
		}
		return suggestions
	}
}