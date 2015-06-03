import Foundation

class QBECalculateStep: QBEStep {
	var function: QBEExpression
	var targetColumn: QBEColumn
	var insertRelativeTo: QBEColumn? = nil
	var insertBefore: Bool = false
	
	required init(coder aDecoder: NSCoder) {
		function = (aDecoder.decodeObjectForKey("function") as? QBEExpression) ?? QBEIdentityExpression()
		targetColumn = QBEColumn((aDecoder.decodeObjectForKey("targetColumn") as? String) ?? "")
		
		if let after = aDecoder.decodeObjectForKey("insertAfter") as? String {
			insertRelativeTo = QBEColumn(after)
		}
		
		/* Older versions of Warp do not encode this key and assume insert after (hence the relative column is coded as 
		'insertAfter'). As decodeBoolForKey defaults to false for keys it cannot find, this is the expected behaviour. */
		self.insertBefore = aDecoder.decodeBoolForKey("insertBefore")
		
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
		coder.encodeObject(insertRelativeTo?.name, forKey: "insertAfter")
		coder.encodeBool(insertBefore, forKey: "insertBefore")
		super.encodeWithCoder(coder)
	}
	
	required init(previous: QBEStep?, targetColumn: QBEColumn, function: QBEExpression, insertRelativeTo: QBEColumn? = nil, insertBefore: Bool = false) {
		self.function = function
		self.targetColumn = targetColumn
		self.insertRelativeTo = insertRelativeTo
		self.insertBefore = insertBefore
		super.init(previous: previous)
	}
	
	override func apply(data: QBEData, job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		let result = data.calculate([targetColumn: function])
		if let relativeTo = insertRelativeTo {
			// Reorder columns in the result set so that targetColumn is inserted after insertAfter
			data.columnNames(job) { (columnNames) in
				columnNames.use { (var cns) -> () in
					cns.remove(self.targetColumn)
					if let idx = find(cns, relativeTo) {
						if self.insertBefore {
							cns.insert(self.targetColumn, atIndex: idx)
						}
						else {
							cns.insert(self.targetColumn, atIndex: idx+1)
						}
					}
					callback(QBEFallible(result.selectColumns(cns)))
				}
			}
		}
		else {
			// If the column is to be added at the beginning, shuffle columns around (the default is to add at the end
			if insertRelativeTo == nil && insertBefore {
				data.columnNames(job) { (var columnNames: QBEFallible<[QBEColumn]>) -> () in
					switch columnNames {
						case .Success(let cns):
							var columns = cns.value
							columns.remove(self.targetColumn)
							columns.insert(self.targetColumn, atIndex: 0)
							callback(QBEFallible(result.selectColumns(columns)))
						
						case .Failure(let error):
							callback(.Failure(error))
					}
				}
			}
			else {
				callback(QBEFallible(result))
			}
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
				let relativeTo = self.insertRelativeTo ?? p.insertRelativeTo
				let before = self.insertBefore ?? p.insertBefore
				return QBEStepMerge.Advised(QBECalculateStep(previous: previous, targetColumn: targetColumn, function: function, insertRelativeTo: relativeTo, insertBefore: before))
			}
		}
		
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
				QBEExpression.infer(nil, toValue: toValue, suggestions: &suggestions, level: 8, row: QBERow(inRaster[row], columnNames: inRaster.columnNames), column: column, job: job)
				// Suggest a text replace
				suggestions.append(QBEFunctionExpression(arguments: [QBEIdentityExpression(), QBELiteralExpression(fromValue), QBELiteralExpression(toValue)], type: QBEFunction.Substitute))
			}
		}
		return suggestions
	}
}