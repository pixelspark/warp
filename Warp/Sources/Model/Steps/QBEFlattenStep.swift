import Foundation
import WarpCore

class QBEFlattenStep: QBEStep {
	var colColumn: Column? = nil
	var rowColumn: Column? = nil
	var valueColumn: Column
	var rowIdentifier: Expression? = nil

	required init() {
		valueColumn = Column(NSLocalizedString("Value", comment: ""))
		super.init()
	}
	
	override init(previous: QBEStep?) {
		self.colColumn = Column(NSLocalizedString("Column", comment: ""))
		self.rowColumn = Column(NSLocalizedString("Row", comment: ""))
		self.valueColumn = Column(NSLocalizedString("Value", comment: ""))
		super.init(previous: previous)
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: NSLocalizedString("For each cell, put its value in column [#], the column name in [#], and in [#] the result of [#]", comment: ""),
			QBESentenceTextInput(value: self.valueColumn.name, callback: { [weak self] (newName) -> (Bool) in
				if !newName.isEmpty {
					self?.valueColumn = Column(newName)
					return true
				}
				return false
			}),
			QBESentenceTextInput(value: self.colColumn?.name ?? "", callback: { [weak self] (newName) -> (Bool) in
				if !newName.isEmpty {
					self?.colColumn = Column(newName)
				}
				else {
					self?.colColumn = nil
				}
				return true
			}),
			QBESentenceTextInput(value: self.rowColumn?.name ?? "", callback: { [weak self] (newName) -> (Bool) in
				if !newName.isEmpty {
					self?.rowColumn = Column(newName)
				}
				else {
					self?.rowColumn = nil
				}
				return true
			}),
			QBESentenceFormula(expression: self.rowIdentifier ?? Literal(Value("")), locale: locale, callback: { [weak self] (expression) -> () in
				self?.rowIdentifier = expression
			})
		)
	}
	
	required init(coder aDecoder: NSCoder) {
		if let cc = aDecoder.decodeObjectForKey("colColumn") as? String {
			colColumn = Column(cc)
		}
		
		if let rc = aDecoder.decodeObjectForKey("rowColumn") as? String {
			rowColumn = Column(rc)
		}
		
		valueColumn = Column((aDecoder.decodeObjectForKey("valueColumn") as? String) ?? "")
		rowIdentifier = aDecoder.decodeObjectForKey("rowIdentifier") as? Expression
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(colColumn?.name, forKey: "colColumn")
		coder.encodeObject(rowColumn?.name, forKey: "rowColumn")
		coder.encodeObject(valueColumn.name, forKey: "valueColumn")
		coder.encodeObject(rowIdentifier, forKey: "rowIdentifier")
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: Data, job: Job, callback: (Fallible<Data>) -> ()) {
		/* If a column is set to put a row identifier in, but there is no expression, fill in an expression that uses the
		value in the first column. */
		if rowIdentifier == nil && rowColumn != nil {
			data.columns(job) { (columns) -> () in
				switch columns {
					case .Success(let cs):
						if let firstColumn = cs.first {
							let ri = Sibling(firstColumn)
							callback(.Success(data.flatten(self.valueColumn, columnNameTo: self.colColumn, rowIdentifier: ri, to: self.rowColumn)))
						}
						else {
							callback(.Failure(NSLocalizedString("The data set that is to be flattened contained no rows.", comment: "")))
						}
					
					case .Failure(let error):
						callback(.Failure(error))
				}
			}
		}
		else {
			callback(.Success(data.flatten(valueColumn, columnNameTo: colColumn, rowIdentifier: rowIdentifier, to: rowColumn)))
		}
	}
}