import Foundation

class QBEInferer {
	class func inferFunctions(fromValue: QBEValue?, toValue: QBEValue, inout suggestions: [QBEFunction], level: Int, raster: QBERaster, row: Int, column: Int, maxComplexity: Int = Int.max) {
		if fromValue == toValue {
			return
		}
		
		// Try out combinations of formulas and see if they fit
		for formulaType in QBEFunctions {
			let suggestedFormulas = formulaType.suggest(fromValue, toValue: toValue, raster: raster, row: row);
			var complexity = maxComplexity
			var exploreFurther: [QBEFunction] = []
			
			for formula in suggestedFormulas {
				if formula.complexity >= maxComplexity {
					continue
				}
				
				let result = formula.apply(raster, rowNumber: row, inputValue: fromValue)
				//println("\(level) Try formula \(formula) input=\(fromValue) expected=\(toValue) out=\(result)")
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
					let result = formula.apply(raster, rowNumber: row, inputValue: fromValue)
					var nextLevelSuggestions: [QBEFunction] = []
					QBEInferer.inferFunctions(result, toValue: toValue, suggestions: &nextLevelSuggestions, level: level-1, raster: raster, row: row, column: column, maxComplexity: complexity)
					
					for nextLevelSuggestion in nextLevelSuggestions {
						let cf = QBECompoundFunction(first: formula, second: nextLevelSuggestion)
						if cf.apply(raster, rowNumber: row, inputValue: fromValue) == toValue {
							if cf.complexity < complexity {
								suggestions.append(cf)
								complexity = cf.complexity
							}
						}
					}
				}
			}
		}
	}
}