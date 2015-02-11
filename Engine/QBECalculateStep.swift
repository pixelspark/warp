import Foundation

class QBECalculateStep: QBEStep {
	var function: QBEExpression
	var targetColumn: QBEColumn
	
	required init(coder aDecoder: NSCoder) {
		function = (aDecoder.decodeObjectForKey("function") as? QBEExpression) ?? QBEIdentityExpression()
		targetColumn = QBEColumn((aDecoder.decodeObjectForKey("targetColumn") as? String) ?? "")
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
				inferCalculation(nil, toValue: toValue, suggestions: &suggestions, level: 4, raster: inRaster, row: inRaster[row], column: column)
				// Suggest a text replace
				suggestions.append(QBEFunctionExpression(arguments: [QBEIdentityExpression(), QBELiteralExpression(fromValue), QBELiteralExpression(toValue)], type: QBEFunction.Substitute))
			}
		}
		return suggestions
	}
	
	/** The inferCalculation function implements an algorithm to find one or more formulas that are able to transform an
	input value to a specific output value. It does so by looping over 'suggestions' (provided by QBEFunction
	implementations) for the application of (usually unary) functions to the input value to obtain (or come closer to) the
	output value. **/
	private class final func inferCalculation(fromValue: QBEExpression?, toValue: QBEValue, inout suggestions: [QBEExpression], level: Int, raster: QBERaster, row: QBERow, column: Int, maxComplexity: Int = Int.max, previousValues: [QBEValue] = []) {
		
		let columns = raster.columnNames
		let inputValue = row[column]
		
		// Try out combinations of formulas and see if they fit
		for formulaType in QBEExpressions {
			let suggestedFormulas = formulaType.suggest(fromValue, toValue: toValue, row: row, columns: columns, inputValue: inputValue);
			var complexity = maxComplexity
			var exploreFurther: [QBEExpression] = []
			
			for formula in suggestedFormulas {
				if formula.complexity >= maxComplexity {
					continue
				}
				
				let result = formula.apply(row, columns: columns, inputValue: inputValue)
				if result == toValue {
					suggestions.append(formula)
					
					if formula.complexity < maxComplexity {
						complexity = formula.complexity
					}
				}
				else {
					if level > 0 {
						exploreFurther.append(formula)
					}
				}
			}
			
			if suggestions.count == 0 {
				// Let's see if we can find something else
				for formula in exploreFurther {
					let result = formula.apply(row, columns: columns, inputValue: inputValue)
					
					// Have we already seen this result? Then ignore
					var found = false
					for previous in previousValues {
						if previous == result {
							found = true
							break
						}
					}
					
					if found {
						continue
					}
					
					var nextLevelSuggestions: [QBEExpression] = []
					var newPreviousValues = previousValues
					newPreviousValues.append(result)
					inferCalculation(formula, toValue: toValue, suggestions: &nextLevelSuggestions, level: level-1, raster: raster, row: row, column: column, maxComplexity: complexity, previousValues: newPreviousValues)
					
					for nextLevelSuggestion in nextLevelSuggestions {
						if nextLevelSuggestion.apply(row, columns:raster.columnNames, inputValue: inputValue) == toValue {
							if nextLevelSuggestion.complexity <= complexity {
								suggestions.append(nextLevelSuggestion)
								complexity = nextLevelSuggestion.complexity
							}
						}
					}
				}
			}
		}
	}
}