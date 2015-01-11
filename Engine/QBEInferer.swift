import Foundation

class QBEInferer {
	class func inferFunctions(fromValue: QBEExpression?, toValue: QBEValue, inout suggestions: [QBEExpression], level: Int, raster: QBERaster, row: Int, column: Int, maxComplexity: Int = Int.max, previousValues: [QBEValue] = []) {

		
		let inputValue = raster[row, column]
		
		// Try out combinations of formulas and see if they fit
		for formulaType in QBEExpressions {
			let suggestedFormulas = formulaType.suggest(fromValue, toValue: toValue, raster: raster, row: row, inputValue: inputValue);
			var complexity = maxComplexity
			var exploreFurther: [QBEExpression] = []
			
			for formula in suggestedFormulas {
				if formula.complexity >= maxComplexity {
					continue
				}
				
				let result = formula.apply(raster, rowNumber: row, inputValue: inputValue)
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
					let result = formula.apply(raster, rowNumber: row, inputValue: inputValue)
					
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
						if nextLevelSuggestion.apply(raster, rowNumber: row, inputValue: inputValue) == toValue {
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