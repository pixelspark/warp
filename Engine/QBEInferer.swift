import Foundation

/** QBEInferer is a helper class that contains an algorithm to find one or more formulas that are able to transform an
input value to a specific output value. It does so by looping over 'suggestions' (provided by QBEFunction implementations)
for the application of (usually unary) functions to the input value to obtain (or come closer to) the output value. **/
class QBEInferer {
	class func inferFunctions(fromValue: QBEExpression?, toValue: QBEValue, inout suggestions: [QBEExpression], level: Int, raster: QBERaster, row: QBERow, column: Int, maxComplexity: Int = Int.max, previousValues: [QBEValue] = []) {

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
					QBEInferer.inferFunctions(formula, toValue: toValue, suggestions: &nextLevelSuggestions, level: level-1, raster: raster, row: row, column: column, maxComplexity: complexity, previousValues: newPreviousValues)
					
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