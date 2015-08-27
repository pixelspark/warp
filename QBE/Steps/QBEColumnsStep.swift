import Foundation
import WarpCore

class QBEColumnsStep: QBEStep {
	var columnNames: [QBEColumn]
	let select: Bool
	
	init(previous: QBEStep?, columnNames: [QBEColumn], select: Bool) {
		self.columnNames = columnNames
		self.select = select
		super.init(previous: previous)
	}
	
	private func explanation(locale: QBELocale) -> String {
		if select {
			if columnNames.count == 0 {
				return NSLocalizedString("Select all columns", comment: "")
			}
			else if columnNames.count == 1 {
				return String(format: NSLocalizedString("Select only the column '%@'", comment: ""), columnNames.first!.name)
			}
			else if columnNames.count < 5 {
				let cn = columnNames.map({$0.name}).joinWithSeparator(", ")
				return String(format: NSLocalizedString("Select only the columns %@", comment: ""), cn)
			}
			else {
				return String(format: NSLocalizedString("Select %lu columns", comment: ""), columnNames.count)
			}
		}
		else {
			if columnNames.count == 0 {
				return NSLocalizedString("Remove all columns", comment: "")
			}
			else if columnNames.count == 1 {
				return String(format: NSLocalizedString("Remove the column '%@'", comment: ""), columnNames.first!.name)
			}
			else if columnNames.count < 5 {
				let cn = columnNames.map({$0.name}).joinWithSeparator(", ") ?? ""
				return String(format: NSLocalizedString("Remove the columns %@", comment: ""), cn)
			}
			else {
				return String(format: NSLocalizedString("Remove %lu columns", comment: ""), columnNames.count)
			}
		}
	}

	override func sentence(locale: QBELocale) -> QBESentence {
		return QBESentence([QBESentenceText(self.explanation(locale))])
	}

	required init(coder aDecoder: NSCoder) {
		select = aDecoder.decodeBoolForKey("select")
		let names = (aDecoder.decodeObjectForKey("columnNames") as? [String]) ?? []
		columnNames = names.map({QBEColumn($0)})
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		let columnNameStrings = columnNames.map({$0.name})
		coder.encodeObject(columnNameStrings, forKey: "columnNames")
		coder.encodeBool(select, forKey: "select")
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: QBEData, job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		data.columnNames(job) { (existingColumnsFallible) -> () in
			switch existingColumnsFallible {
				case .Success(let existingColumns):
					let columns = existingColumns.filter({column -> Bool in
						for c in self.columnNames {
							if c == column {
								return self.select
							}
						}
						return !self.select
					}) ?? []
					
					callback(.Success(data.selectColumns(columns)))
				
				case .Failure(let error):
					callback(.Failure(error))
			}
		}
	}
	
	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		if let p = prior as? QBEColumnsStep where p.select && self.select {
			// This step can ony be a further subset of the columns selected by the prior
			return QBEStepMerge.Advised(self)
		}
		else if let p = prior as? QBECalculateStep {
			let contained = columnNames.contains(p.targetColumn)
			if (select && !contained) || (!select && contained) {
				let newColumns = columnNames.filter({$0 != p.targetColumn})
				if newColumns.count == 0 {
					return QBEStepMerge.Cancels
				}
				else {
					return QBEStepMerge.Advised(QBEColumnsStep(previous: previous, columnNames: newColumns, select: self.select))
				}
			}
		}
		
		return QBEStepMerge.Impossible
	}
}

class QBESortColumnsStep: QBEStep {
	var sortColumns: [QBEColumn]
	var before: QBEColumn? // nil means: at end
	
	init(previous: QBEStep?, sortColumns: [QBEColumn], before: QBEColumn?) {
		self.sortColumns = sortColumns
		self.before = before
		super.init(previous: previous)
	}
	
	private func explanation(locale: QBELocale) -> String {
		let destination = before != nil ? String(format: NSLocalizedString("before %@", comment: ""), before!.name) : NSLocalizedString("at the end", comment: "")
		
		if sortColumns.count > 5 {
			return String(format: NSLocalizedString("Place %d columns %@", comment: ""), sortColumns.count, destination)
		}
		else if sortColumns.count == 1 {
			return String(format: NSLocalizedString("Place column %@ %@", comment: ""), sortColumns[0].name, destination)
		}
		else {
			let names = sortColumns.map({it in return it.name}).joinWithSeparator(", ")
			return String(format: NSLocalizedString("Place columns %@ %@", comment: ""), names, destination)
		}
	}

	override func sentence(locale: QBELocale) -> QBESentence {
		return QBESentence([QBESentenceText(self.explanation(locale))])
	}
	
	required init(coder aDecoder: NSCoder) {
		let names = (aDecoder.decodeObjectForKey("sortColumns") as? [String]) ?? []
		sortColumns = names.map({QBEColumn($0)})
		let beforeName = aDecoder.decodeObjectForKey("before") as? String
		if let b = beforeName {
			self.before = QBEColumn(b)
		}
		else {
			self.before = nil
		}
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		let columnNameStrings = sortColumns.map({$0.name})
		coder.encodeObject(columnNameStrings, forKey: "sortColumns")
		coder.encodeObject(before?.name ?? nil, forKey: "before")
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: QBEData, job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		data.columnNames(job) { (existingColumnsFallible) -> () in
			switch existingColumnsFallible {
				case .Success(let existingColumns):
					let columnSet = Set(existingColumns)
					var newColumns = existingColumns
					var sortColumns = self.sortColumns
					
					/* Remove the dragged columns from their existing location. If they do not exist, remove them from the
					set of dragged columns. */
					for dragged in self.sortColumns {
						if columnSet.contains(dragged) {
							newColumns.remove(dragged)
						}
						else {
							// Dragging a column that doesn't exist! Ignore
							sortColumns.remove(dragged)
						}
					}
					
					// If we have an insertion point for the set of reordered columns, insert them there
					if let before = self.before, let newIndex = newColumns.indexOf(before) {
						newColumns.insertContentsOf(self.sortColumns, at: newIndex)
					}
					else {
						// Just append at the end. Happens when self.before is nil or the column indicated in self.before doesn't exist
						sortColumns.forEach { newColumns.append($0) }
					}
					
					// The re-ordering operation may never drop or add columns (even if specified columns do not exist)
					assert(newColumns.count == existingColumns.count, "Re-ordering operation resulted in loss of columns")
					callback(.Success(data.selectColumns(newColumns)))
				
				case .Failure(let error):
					callback(.Failure(error))
			}
		}
	}
}