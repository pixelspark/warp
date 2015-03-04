import Foundation

class QBEColumnsStep: QBEStep {
	let columnNames: [QBEColumn]
	let select: Bool
	
	init(previous: QBEStep?, columnNames: [QBEColumn], select: Bool) {
		self.columnNames = columnNames
		self.select = select
		let columnNameStrings = columnNames.map({$0.name})
		super.init(previous: previous)
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("Select columns", comment: "")
		}
		
		if select {
			if columnNames.count == 0 {
				return NSLocalizedString("Select all columns", comment: "")
			}
			else if columnNames.count == 1 {
				return String(format: NSLocalizedString("Select only the column '%@'", comment: ""), columnNames.first!.name)
			}
			else {
				let cn = columnNames.map({$0.name}).implode(", ") ?? ""
				return String(format: NSLocalizedString("Select only the columns %@", comment: ""), cn)
			}
		}
		else {
			if columnNames.count == 0 {
				return NSLocalizedString("Remove all columns", comment: "")
			}
			else if columnNames.count == 1 {
				return String(format: NSLocalizedString("Remove the column '%@'", comment: ""), columnNames.first!.name)
			}
			else {
				let cn = columnNames.map({$0.name}).implode(", ") ?? ""
				return String(format: NSLocalizedString("Remove the columns %@", comment: ""), cn)
			}
		}
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
	
	override func apply(data: QBEData, job: QBEJob?, callback: (QBEData) -> ()) {
		data.columnNames({ (existingColumns) -> () in
			let columns = existingColumns.filter({column -> Bool in
				for c in self.columnNames {
					if c == column {
						return self.select
					}
				}
				return !self.select
			}) ?? []
			
			callback(data.selectColumns(columns))
		})
	}
}