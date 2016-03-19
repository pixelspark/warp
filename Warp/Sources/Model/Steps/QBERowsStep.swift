import Foundation
import WarpCore

class QBERowsStep: NSObject {
	class func suggest(selectRows: NSIndexSet, columns: Set<Column>, inRaster: Raster, fromStep: QBEStep?, select: Bool) -> [QBEStep] {
		var suggestions: [QBEStep] = []
		
		// Check to see if the selected rows have similar values for the relevant columns
		var sameValues = Dictionary<Column, Value>()
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
				
				if sameColumns.isEmpty {
					break
				}
			}
		}
		
		// Build an expression to select rows by similar value
		if sameValues.count > 0 {
			var conditions: [Expression] = []
			
			for (column, value) in sameValues {
				conditions.append(Comparison(first: Literal(value), second: Sibling(column), type: Binary.Equal))
			}
			
			if let fullCondition = conditions.count > 1 ? Call(arguments: conditions, type: Function.And) : conditions.first {
				if select {
					suggestions.append(QBEFilterStep(previous: fromStep, condition: fullCondition))
				}
				else {
					suggestions.append(QBEFilterStep(previous: fromStep, condition: Call(arguments: [fullCondition], type: Function.Not)))
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
	var condition: Expression

	required init() {
		condition = Literal(Value.BoolValue(true))
		super.init()
	}
	
	init(previous: QBEStep?, condition: Expression) {
		self.condition = condition
		super.init(previous: previous)
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
			QBESentenceText(NSLocalizedString("Select rows where", comment: "")),
			QBESentenceFormula(expression: condition, locale: locale, callback: {[weak self] (expr) in
				self?.condition = expr
			})
		])
	}
	
	required init(coder aDecoder: NSCoder) {
		condition = (aDecoder.decodeObjectForKey("condition") as? Expression) ?? Literal(Value.BoolValue(true))
		super.init(coder: aDecoder)
	}

	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(condition, forKey: "condition")
	}
	
	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		if let p = prior as? QBEFilterStep {
			// This filter step can be AND'ed with the previous
			let combinedCondition: Expression

			if let rootAnd = p.condition as? Call where rootAnd.type == Function.And {
				let args: [Expression] = rootAnd.arguments + [self.condition]
				combinedCondition = Call(arguments: args, type: Function.And)
			}
			else {
				let args: [Expression] = [p.condition, self.condition]
				combinedCondition = Call(arguments: args, type: Function.And)
			}
			
			return QBEStepMerge.Possible(QBEFilterStep(previous: nil, condition: combinedCondition))
		}
		
		return QBEStepMerge.Impossible
	}
	
	override func apply(data: Data, job: Job?, callback: (Fallible<Data>) -> ()) {
		callback(.Success(data.filter(condition)))
	}
}

class QBELimitStep: QBEStep {
	var numberOfRows: Int
	
	init(previous: QBEStep?, numberOfRows: Int) {
		self.numberOfRows = numberOfRows
		super.init(previous: previous)
	}

	required init() {
		self.numberOfRows = 1
		super.init()
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: NSLocalizedString(self.numberOfRows > 1 ? "Select the first [#] rows" : "Select row [#]", comment: ""),
			QBESentenceTextInput(value: locale.localStringFor(Value(self.numberOfRows)), callback: { (newValue) -> (Bool) in
				if let x = locale.valueForLocalString(newValue).intValue {
					self.numberOfRows = x
					return true
				}
				return false
			})
		)
	}
	
	required init(coder aDecoder: NSCoder) {
		numberOfRows = Int(aDecoder.decodeIntForKey("numberOfRows"))
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeInt(Int32(numberOfRows), forKey: "numberOfRows")
	}
	
	override func apply(data: Data, job: Job?, callback: (Fallible<Data>) -> ()) {
		callback(.Success(data.limit(numberOfRows)))
	}
	
	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		if let p = prior as? QBELimitStep where !(p is QBERandomStep) {
			return QBEStepMerge.Advised(QBELimitStep(previous: nil, numberOfRows: min(self.numberOfRows, p.numberOfRows)))
		}
		return QBEStepMerge.Impossible
	}
}

class QBEOffsetStep: QBEStep {
	var numberOfRows: Int = 1

	required init() {
		super.init()
	}
	
	init(previous: QBEStep?, numberOfRows: Int) {
		self.numberOfRows = numberOfRows
		super.init(previous: previous)
	}
	
	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: NSLocalizedString( numberOfRows > 1 ? "Skip the first [#] rows" : "Skip row [#]", comment: ""),
			QBESentenceTextInput(value: locale.localStringFor(Value(self.numberOfRows)), callback: { (newValue) -> (Bool) in
				if let x = locale.valueForLocalString(newValue).intValue {
					self.numberOfRows = x
					return true
				}
				return false
			})
		)
	}
	
	required init(coder aDecoder: NSCoder) {
		numberOfRows = Int(aDecoder.decodeIntForKey("numberOfRows"))
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeInt(Int32(numberOfRows), forKey: "numberOfRows")
	}
	
	override func apply(data: Data, job: Job?, callback: (Fallible<Data>) -> ()) {
		callback(.Success(data.offset(numberOfRows)))
	}
}

class QBERandomStep: QBELimitStep {
	override init(previous: QBEStep?, numberOfRows: Int) {
		super.init(previous: previous, numberOfRows: numberOfRows)
	}

	required init() {
		super.init()
	}
	
	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
			QBESentenceText(NSLocalizedString("Randomly select", comment: "")),
			QBESentenceTextInput(value: locale.localStringFor(Value(self.numberOfRows)), callback: { (newValue) -> (Bool) in
				if let x = locale.valueForLocalString(newValue).intValue {
					self.numberOfRows = x
					return true
				}
				return false
			}),
			QBESentenceText(NSLocalizedString(self.numberOfRows > 1 ? "rows" : "row", comment: ""))
			])
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}

	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: Data, job: Job?, callback: (Fallible<Data>) -> ()) {
		callback(.Success(data.random(numberOfRows)))
	}

	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		return QBEStepMerge.Impossible
	}
}

class QBEDistinctStep: QBEStep {
	required init() {
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
			QBESentenceText(NSLocalizedString("Remove duplicate rows", comment: ""))
		])
	}
	
	override func apply(data: Data, job: Job?, callback: (Fallible<Data>) -> ()) {
		callback(.Success(data.distinct()))
	}
}