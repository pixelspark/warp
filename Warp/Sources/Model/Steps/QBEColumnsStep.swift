import Foundation
import WarpCore

class QBEColumnsStep: QBEStep {
	var columns: [Column] = []
	var select: Bool = true

	required init() {
		super.init()
	}

	init(previous: QBEStep?, columns: [Column], select: Bool) {
		self.columns = columns
		self.select = select
		super.init(previous: previous)
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		let typeItem = QBESentenceOptions(options: [
			"select": (columns.count <= 1 ? "Select column".localized : "Select columns".localized),
			"remove": (columns.count <= 1 ? "Remove column".localized : "Remove columns".localized)
		], value: self.select ? "select" : "remove") { [weak self] newType in
			self?.select = (newType == "select")
		}

		let columnsItem = QBESentenceSet(value: Set(self.columns.map { $0.name }), provider: { cb in
			let job = Job(.UserInitiated)
			if let previous = self.previous {
				previous.exampleData(job, maxInputRows: 100, maxOutputRows: 100) {result in
					switch result {
					case .Success(let data):
						data.columns(job) { result in
							switch result {
							case .Success(let cns):
								cb(.Success(Set(cns.map { $0.name })))

							case .Failure(let e):
								cb(.Failure(e))
							}
						}
					case .Failure(let e):
						cb(.Failure(e))
					}
				}
			}
			else {
				cb(.Success([]))
			}
		},
		callback: { [weak self] newSet in
			self?.columns = Array(newSet.map { Column($0) })
		})

		if select {
			if columns.count <= 1 {
				return QBESentence(format: "[#] [#]", typeItem, columnsItem)
			}
			else {
				return QBESentence(format: "[#] [#]".localized, typeItem, columnsItem)
			}
		}
		else {
			if columns.isEmpty {
				return QBESentence(format: "Remove all columns".localized)
			}
			else if columns.count == 1 {
				return QBESentence(format: "[#] [#]".localized, typeItem, columnsItem)
			}
			else {
				return QBESentence(format: "[#] [#]".localized, typeItem, columnsItem)
			}
		}
	}

	required init(coder aDecoder: NSCoder) {
		select = aDecoder.decodeBoolForKey("select")
		let names = (aDecoder.decodeObjectForKey("columnNames") as? [String]) ?? []
		columns = names.map({Column($0)})
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		let columnNameStrings = columns.map({$0.name})
		coder.encodeObject(columnNameStrings, forKey: "columnNames")
		coder.encodeBool(select, forKey: "select")
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: Data, job: Job, callback: (Fallible<Data>) -> ()) {
		data.columns(job) { (existingColumnsFallible) -> () in
			switch existingColumnsFallible {
				case .Success(let existingColumns):
					let columns = existingColumns.filter({column -> Bool in
						for c in self.columns {
							if c == column {
								return self.select
							}
						}
						return !self.select
					}) ?? []
					print("selectCols \(columns)")
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
		else if let p = prior as? QBEColumnsStep where !p.select && !self.select {
			// This step removes additional columns after the previous one
			var newColumns = p.columns
			self.columns.forEach { cn in
				if !newColumns.contains(cn) {
					newColumns.append(cn)
				}
			}

			return QBEStepMerge.Advised(QBEColumnsStep(previous: previous, columns: newColumns, select: false))
		}
		else if let p = prior as? QBECalculateStep {
			let contained = columns.contains(p.targetColumn)
			if (select && !contained) || (!select && contained) {
				let newColumns = columns.filter({$0 != p.targetColumn})
				if newColumns.isEmpty {
					return QBEStepMerge.Cancels
				}
				else {
					return QBEStepMerge.Advised(QBEColumnsStep(previous: previous, columns: newColumns, select: self.select))
				}
			}
		}
		
		return QBEStepMerge.Impossible
	}
}

class QBESortColumnsStep: QBEStep {
	var sortColumns: [Column] = []
	var before: Column? // nil means: at end

	required init() {
		super.init()
	}
	
	init(previous: QBEStep?, sortColumns: [Column], before: Column?) {
		self.sortColumns = sortColumns
		self.before = before
		super.init(previous: previous)
	}
	
	private func explanation(locale: Locale) -> String {
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

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([QBESentenceText(self.explanation(locale))])
	}
	
	required init(coder aDecoder: NSCoder) {
		let names = (aDecoder.decodeObjectForKey("sortColumns") as? [String]) ?? []
		sortColumns = names.map({Column($0)})
		let beforeName = aDecoder.decodeObjectForKey("before") as? String
		if let b = beforeName {
			self.before = Column(b)
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
	
	override func apply(data: Data, job: Job, callback: (Fallible<Data>) -> ()) {
		data.columns(job) { (existingColumnsFallible) -> () in
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