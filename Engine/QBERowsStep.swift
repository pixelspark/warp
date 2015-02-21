import Foundation

class QBERowsStep: NSObject {
	class func suggest(selectRows: NSIndexSet, columns: Set<QBEColumn>, inRaster: QBERaster, fromStep: QBEStep?) -> [QBEStep] {
		var suggestions: [QBEStep] = []
		
		// Check to see if the selected rows have similar values for the relevant columns
		var sameValues = Dictionary<QBEColumn, QBEValue>()
		var sameColumns = columns
		
		for index in 0..<inRaster.rowCount {
			if selectRows.containsIndex(index) {
				for column in sameColumns {
					if let ci = inRaster.indexOfColumnWithName(column) {
						let value = inRaster[index][ci]
						if let previous = sameValues[column] {
							if previous != value {
								sameColumns.remove(column)
								sameValues.removeValueForKey(column)
							}
						}
						else {
							sameValues[column] = value
						}
					}
				}
				
				if sameColumns.count == 0 {
					break
				}
			}
		}
		
		// Build an expression to select rows by similar value
		if sameValues.count > 0 {
			var conditions: [QBEExpression] = []
			
			for (column, value) in sameValues {
				conditions.append(QBEBinaryExpression(first: QBELiteralExpression(value), second: QBESiblingExpression(columnName: column), type: QBEBinary.Equal))
			}
			
			if let fullCondition = conditions.count > 1 ? QBEFunctionExpression(arguments: conditions, type: QBEFunction.And) : conditions.first {
				println("WHERE \(fullCondition.toFormula(QBEDefaultLocale()))")
				suggestions.append(QBEFilterStep(previous: fromStep, condition: fullCondition))
			}
		}
		
		// Is the selection contiguous from the top? Then suggest a limit selection
		var contiguousTop = true
		for index in 0..<selectRows.count {
			if !selectRows.containsIndex(index) {
				contiguousTop = false
				break
			}
		}
		if contiguousTop {
			suggestions.append(QBELimitStep(previous: fromStep, numberOfRows: selectRows.count))
		}
		
		// Suggest a random selection
		suggestions.append(QBERandomStep(previous: fromStep, numberOfRows: selectRows.count))
		
		return suggestions
	}
}

class QBEFilterStep: QBEStep {
	var condition: QBEExpression?
	
	init(previous: QBEStep?, condition: QBEExpression) {
		self.condition = condition
		super.init(previous: previous)
	}
	
	override func explain(locale: QBELocale) -> String {
		return String(format: NSLocalizedString("Select rows where %@", comment: ""), (condition?.explain(locale)) ?? "")
	}
	
	required init(coder aDecoder: NSCoder) {
		condition = (aDecoder.decodeObjectForKey("condition") as? QBEExpression)
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(condition, forKey: "condition")
	}
	
	override func apply(data: QBEData?, callback: (QBEData?) -> ()) {
		if let c = condition {
			callback(data?.filter(c))
		}
		else {
			callback(data)
		}
	}
}

class QBELimitStep: QBEStep {
	var numberOfRows: Int
	
	init(previous: QBEStep?, numberOfRows: Int) {
		self.numberOfRows = numberOfRows
		super.init(previous: previous)
	}
	
	override func explain(locale: QBELocale) -> String {
		return String(format: NSLocalizedString("Select the top %d rows", comment: ""), numberOfRows)
	}
	
	required init(coder aDecoder: NSCoder) {
		numberOfRows = Int(aDecoder.decodeIntForKey("numberOfRows"))
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeInt(Int32(numberOfRows), forKey: "numberOfRows")
	}
	
	override func apply(data: QBEData?, callback: (QBEData?) -> ()) {
		callback(data?.limit(numberOfRows))
	}
}

class QBERandomStep: QBELimitStep {
	override init(previous: QBEStep?, numberOfRows: Int) {
		super.init(previous: previous, numberOfRows: numberOfRows)
	}
	
	override func explain(locale: QBELocale) -> String {
		return String(format: NSLocalizedString("Randomly select %d rows", comment: ""), numberOfRows)
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: QBEData?, callback: (QBEData?) -> ()) {
		callback(data?.random(numberOfRows))
	}
}

class QBEDistinctStep: QBEStep {
	override init(previous: QBEStep?) {
		super.init(previous: previous)
	}
	
	override func explain(locale: QBELocale) -> String {
		return NSLocalizedString("Remove duplicate rows", comment: "")
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: QBEData?, callback: (QBEData?) -> ()) {
		callback(data?.distinct())
	}
}