import Foundation
import WarpCore

/** A mutable data proxy that prevents edits to the data set that assume a certain order or position of rows. */
class QBEMutableDatasetWithRowsShuffled: MutableProxyDataset {
	override func canPerformMutation(_ mutation: DatasetMutation) -> Bool {
		switch mutation {
		case .remove(rows: _), .edit(row: _, column: _, old: _, new: _):
			return false
		default:
			return true
		}
	}
}

class QBERowsStep: NSObject {
	class func suggest(_ selectRows: IndexSet, columns: Set<Column>, inRaster: Raster, fromStep: QBEStep?, select: Bool) -> [QBEStep] {
		var suggestions: [QBEStep] = []
		
		// Check to see if the selected rows have similar values for the relevant columns
		var sameValues = Dictionary<Column, Value>()
		var sameColumns = columns
		
		for index in 0..<inRaster.rowCount {
			if selectRows.contains(index) {
				for column in sameColumns {
					if let ci = inRaster.indexOfColumnWithName(column) {
						let value = inRaster[index][ci]
						if let previous = sameValues[column] {
							if previous != value {
								sameColumns.remove(column)
								sameValues.removeValue(forKey: column)
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
			if !selectRows.contains(index) {
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
		condition = Literal(Value.bool(true))
		super.init()
	}
	
	init(previous: QBEStep?, condition: Expression) {
		self.condition = condition
		super.init(previous: previous)
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
			QBESentenceText(NSLocalizedString("Select rows where", comment: "")),
			QBESentenceFormula(expression: condition, locale: locale, callback: {[weak self] (expr) in
				self?.condition = expr
			})
		])
	}
	
	required init(coder aDecoder: NSCoder) {
		condition = (aDecoder.decodeObject(forKey: "condition") as? Expression) ?? Literal(Value.bool(true))
		super.init(coder: aDecoder)
	}

	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(condition, forKey: "condition")
	}
	
	override func mergeWith(_ prior: QBEStep) -> QBEStepMerge {
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
			
			return QBEStepMerge.possible(QBEFilterStep(previous: nil, condition: combinedCondition))
		}
		
		return QBEStepMerge.impossible
	}
	
	override func apply(_ data: Dataset, job: Job?, callback: (Fallible<Dataset>) -> ()) {
		callback(.success(data.filter(condition)))
	}

	override var mutableDataset: MutableDataset? {
		if let md = self.previous?.mutableDataset {
			return QBEMutableDatasetWithRowsShuffled(original: md)
		}
		return nil
	}
}

class QBEFilterSetStep: QBEStep {
	var filterSet: [Column: FilterSet] = [:]

	required init() {
		filterSet = [:]
		super.init()
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let c = filterSet.count
		if c == 1 {
			let firstColumn = filterSet.keys.first!.name
			return QBESentence(format: String(format: "Select rows using a filter on column %@".localized, firstColumn))
		}
		else if c > 1 {
			let firstColumns = Array(filterSet.keys.sorted { $0.name < $1.name }.prefix(4)).map { return $0.name }.joined(separator: ", ")
			if c > 4 {
				return QBESentence(format: String(format: "Select rows using filters on columns %@ and %d more".localized, firstColumns, c - 4))
			}
			else {
				return QBESentence(format: String(format: "Select rows using filters on columns %@".localized, firstColumns))
			}
		}
		else {
			return QBESentence(format: "Select rows using a filter".localized)
		}
	}

	required init(coder aDecoder: NSCoder) {
		if let d = aDecoder.decodeObject(forKey: "filters") as? NSDictionary {
			for k in d.keyEnumerator() {
				if let filter = d.object(forKey: k) as? FilterSet, let key = k as? String {
					self.filterSet[Column(key)] = filter
				}
			}
		}
		super.init(coder: aDecoder)
	}

	override func encode(with coder: NSCoder) {
		super.encode(with: coder)

		let d = NSMutableDictionary()
		for (k, v) in self.filterSet {
			d.setObject(v, forKey: k.name)
		}
		coder.encode(d, forKey: "filters")
	}

	override func mergeWith(_ prior: QBEStep) -> QBEStepMerge {
		// Editing filter steps is handled separately by the editor
		return QBEStepMerge.impossible
	}

	override func apply(_ data: Dataset, job: Job, callback: (Fallible<Dataset>) -> ()) {
		if !self.filterSet.isEmpty {
			// Filter the data according to the specification
			data.columns(job, callback: { fallibleColumns in
				switch fallibleColumns {
				case .success(let columns):
					var filteredDataset = data
					for column in columns {
						if let columnFilter = self.filterSet[column] {
							let filterExpression = columnFilter.expression.expressionReplacingIdentityReferencesWith(Sibling(column))
							filteredDataset = filteredDataset.filter(filterExpression)
						}
					}
					return callback(.success(filteredDataset))

				case .failure(let e):
					return callback(.failure(e))
				}
			})
		}
		else {
			// Nothing to filter
			return callback(.success(data))
		}
	}

	override var mutableDataset: MutableDataset? {
		if let md = self.previous?.mutableDataset {
			return QBEMutableDatasetWithRowsShuffled(original: md)
		}
		return nil
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

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
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
		numberOfRows = Int(aDecoder.decodeInteger(forKey: "numberOfRows"))
		super.init(coder: aDecoder)
	}
	
	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(numberOfRows, forKey: "numberOfRows")
	}
	
	override func apply(_ data: Dataset, job: Job?, callback: (Fallible<Dataset>) -> ()) {
		callback(.success(data.limit(numberOfRows)))
	}
	
	override func mergeWith(_ prior: QBEStep) -> QBEStepMerge {
		if let p = prior as? QBELimitStep where !(p is QBERandomStep) {
			return QBEStepMerge.advised(QBELimitStep(previous: nil, numberOfRows: min(self.numberOfRows, p.numberOfRows)))
		}
		return QBEStepMerge.impossible
	}

	override var mutableDataset: MutableDataset? {
		if let md = self.previous?.mutableDataset {
			return QBEMutableDatasetWithRowsShuffled(original: md)
		}
		return nil
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
	
	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
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
		numberOfRows = Int(aDecoder.decodeInteger(forKey: "numberOfRows"))
		super.init(coder: aDecoder)
	}
	
	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(numberOfRows, forKey: "numberOfRows")
	}
	
	override func apply(_ data: Dataset, job: Job?, callback: (Fallible<Dataset>) -> ()) {
		callback(.success(data.offset(numberOfRows)))
	}

	override var mutableDataset: MutableDataset? {
		if let md = self.previous?.mutableDataset {
			return QBEMutableDatasetWithRowsShuffled(original: md)
		}
		return nil
	}
}

class QBERandomStep: QBELimitStep {
	override init(previous: QBEStep?, numberOfRows: Int) {
		super.init(previous: previous, numberOfRows: numberOfRows)
	}

	required init() {
		super.init()
	}
	
	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
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

	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
	}
	
	override func apply(_ data: Dataset, job: Job?, callback: (Fallible<Dataset>) -> ()) {
		callback(.success(data.random(numberOfRows)))
	}

	override func mergeWith(_ prior: QBEStep) -> QBEStepMerge {
		return QBEStepMerge.impossible
	}

	override var mutableDataset: MutableDataset? {
		if let md = self.previous?.mutableDataset {
			return QBEMutableDatasetWithRowsShuffled(original: md)
		}
		return nil
	}
}

class QBEDistinctStep: QBEStep {
	required init() {
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
			QBESentenceText(NSLocalizedString("Remove duplicate rows", comment: ""))
		])
	}
	
	override func apply(_ data: Dataset, job: Job?, callback: (Fallible<Dataset>) -> ()) {
		callback(.success(data.distinct()))
	}
}
