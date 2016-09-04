/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
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

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: NSLocalizedString("For each cell, put its value in column [#], the column name in [#], and in [#] the result of [#]", comment: ""),
			QBESentenceTextToken(value: self.valueColumn.name, callback: { [weak self] (newName) -> (Bool) in
				if !newName.isEmpty {
					self?.valueColumn = Column(newName)
					return true
				}
				return false
			}),
			QBESentenceTextToken(value: self.colColumn?.name ?? "", callback: { [weak self] (newName) -> (Bool) in
				if !newName.isEmpty {
					self?.colColumn = Column(newName)
				}
				else {
					self?.colColumn = nil
				}
				return true
			}),
			QBESentenceTextToken(value: self.rowColumn?.name ?? "", callback: { [weak self] (newName) -> (Bool) in
				if !newName.isEmpty {
					self?.rowColumn = Column(newName)
				}
				else {
					self?.rowColumn = nil
				}
				return true
			}),
			QBESentenceFormulaToken(expression: self.rowIdentifier ?? Literal(Value("")), locale: locale, callback: { [weak self] (expression) -> () in
				self?.rowIdentifier = expression
			}, contextCallback: self.contextCallbackForFormulaSentence)
		)
	}
	
	required init(coder aDecoder: NSCoder) {
		if let cc = aDecoder.decodeObject(forKey: "colColumn") as? String {
			colColumn = Column(cc)
		}
		
		if let rc = aDecoder.decodeObject(forKey: "rowColumn") as? String {
			rowColumn = Column(rc)
		}
		
		valueColumn = Column((aDecoder.decodeObject(forKey: "valueColumn") as? String) ?? "")
		rowIdentifier = aDecoder.decodeObject(forKey: "rowIdentifier") as? Expression
		super.init(coder: aDecoder)
	}
	
	override func encode(with coder: NSCoder) {
		coder.encode(colColumn?.name, forKey: "colColumn")
		coder.encode(rowColumn?.name, forKey: "rowColumn")
		coder.encode(valueColumn.name, forKey: "valueColumn")
		coder.encode(rowIdentifier, forKey: "rowIdentifier")
		super.encode(with: coder)
	}
	
	override func apply(_ data: Dataset, job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		/* If a column is set to put a row identifier in, but there is no expression, fill in an expression that uses the
		value in the first column. */
		if rowIdentifier == nil && rowColumn != nil {
			data.columns(job) { (columns) -> () in
				switch columns {
					case .success(let cs):
						if let firstColumn = cs.first {
							let ri = Sibling(firstColumn)
							callback(.success(data.flatten(self.valueColumn, columnNameTo: self.colColumn, rowIdentifier: ri, to: self.rowColumn)))
						}
						else {
							callback(.failure(NSLocalizedString("The data set that is to be flattened contained no rows.", comment: "")))
						}
					
					case .failure(let error):
						callback(.failure(error))
				}
			}
		}
		else {
			callback(.success(data.flatten(valueColumn, columnNameTo: colColumn, rowIdentifier: rowIdentifier, to: rowColumn)))
		}
	}

	override func related(job: Job, callback: @escaping (Fallible<[QBERelatedStep]>) -> ()) {
		return callback(.success([]))
	}
}
