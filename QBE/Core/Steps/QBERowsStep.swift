import Foundation

class QBERowsStep: NSObject {
	class func suggest(selectRows: NSIndexSet, columns: Set<QBEColumn>, inRaster: QBERaster, fromStep: QBEStep?, select: Bool) -> [QBEStep] {
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
				if select {
					suggestions.append(QBEFilterStep(previous: fromStep, condition: fullCondition))
				}
				else {
					suggestions.append(QBEFilterStep(previous: fromStep, condition: QBEFunctionExpression(arguments: [fullCondition], type: QBEFunction.Not)))
				}
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
			if select {
				suggestions.append(QBELimitStep(previous: fromStep, numberOfRows: selectRows.count))
			}
			else {
				suggestions.append(QBEOffsetStep(previous: fromStep, numberOfRows: selectRows.count))
			}
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
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("Select rows", comment: "")
		}
		
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
	
	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		if let p = prior as? QBEFilterStep {
			// This filter step can be AND'ed with the previous
			let combinedCondition: QBEExpression
			
			if let myCondition = self.condition {
				if let otherCondition = p.condition {
					if let rootAnd = otherCondition as? QBEFunctionExpression where rootAnd.type == QBEFunction.And {
						let args: [QBEExpression] = rootAnd.arguments + [myCondition]
						combinedCondition = QBEFunctionExpression(arguments: args, type: QBEFunction.And)
					}
					else {
						var args: [QBEExpression] = [p.condition!, myCondition]
						combinedCondition = QBEFunctionExpression(arguments: args, type: QBEFunction.And)
					}
					
					return QBEStepMerge.Possible(QBEFilterStep(previous: nil, condition: combinedCondition))
				}
				else {
					return QBEStepMerge.Advised(self)
				}
			}
			else {
				return QBEStepMerge.Advised(p)
			}
		}
		
		return QBEStepMerge.Impossible
	}
	
	override func apply(data: QBEFallible<QBEData>, job: QBEJob?, callback: (QBEFallible<QBEData>) -> ()) {
		if let c = condition {
			callback(data.use({$0.filter(c)}))
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
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("First rows", comment: "")
		}
		return String(format: NSLocalizedString("Select the first %d rows", comment: ""), numberOfRows)
	}
	
	required init(coder aDecoder: NSCoder) {
		numberOfRows = Int(aDecoder.decodeIntForKey("numberOfRows"))
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeInt(Int32(numberOfRows), forKey: "numberOfRows")
	}
	
	override func apply(data: QBEFallible<QBEData>, job: QBEJob?, callback: (QBEFallible<QBEData>) -> ()) {
		callback(data.use({$0.limit(numberOfRows)}))
	}
	
	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		if let p = prior as? QBELimitStep {
			return QBEStepMerge.Advised(QBELimitStep(previous: nil, numberOfRows: min(self.numberOfRows, p.numberOfRows)))
		}
		return QBEStepMerge.Impossible
	}
}

class QBEOffsetStep: QBEStep {
	var numberOfRows: Int
	
	init(previous: QBEStep?, numberOfRows: Int) {
		self.numberOfRows = numberOfRows
		super.init(previous: previous)
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("Skip rows", comment: "")
		}
		return String(format: NSLocalizedString("Skip the first %d rows", comment: ""), numberOfRows)
	}
	
	required init(coder aDecoder: NSCoder) {
		numberOfRows = Int(aDecoder.decodeIntForKey("numberOfRows"))
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeInt(Int32(numberOfRows), forKey: "numberOfRows")
	}
	
	override func apply(data: QBEFallible<QBEData>, job: QBEJob?, callback: (QBEFallible<QBEData>) -> ()) {
		callback(data.use({$0.offset(numberOfRows)}))
	}
}

class QBERandomStep: QBELimitStep {
	override init(previous: QBEStep?, numberOfRows: Int) {
		super.init(previous: previous, numberOfRows: numberOfRows)
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("Random rows", comment: "")
		}
		return String(format: NSLocalizedString("Randomly select %d rows", comment: ""), numberOfRows)
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: QBEFallible<QBEData>, job: QBEJob?, callback: (QBEFallible<QBEData>) -> ()) {
		callback(data.use({$0.random(numberOfRows)}))
	}
}

class QBEDistinctStep: QBEStep {
	override init(previous: QBEStep?) {
		super.init(previous: previous)
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("Unique rows", comment: "")
		}
		return NSLocalizedString("Remove duplicate rows", comment: "")
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: QBEFallible<QBEData>, job: QBEJob?, callback: (QBEFallible<QBEData>) -> ()) {
		callback(data.use({$0.distinct()}))
	}
}