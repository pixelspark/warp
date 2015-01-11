import Foundation

class QBERemoveColumnsStep: QBEStep {
	let columnsToRemove: [QBEColumn]
	
	init(previous: QBEStep?, columnsToRemove: [QBEColumn]) {
		self.columnsToRemove = columnsToRemove
		let columnNames = columnsToRemove.map({i -> String in return i.name})
		super.init(previous: previous, explanation: NSLocalizedString("Remove column(s) ", comment: "") + (columnNames.implode(", ") ?? ""))
	}
	
	required init(coder aDecoder: NSCoder) {
		let names = aDecoder.decodeObjectForKey("columnsToRemove") as? [String] ?? []
		columnsToRemove = names.map({i -> QBEColumn in QBEColumn(i)})
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		let columnNames = columnsToRemove.map({i -> String in return i.name})
		coder.encodeObject(columnNames, forKey: "columnsToRemove")
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: QBEData?) -> QBEData? {
		let columns = data?.columnNames.filter({column -> Bool in
			for c in self.columnsToRemove {
				if c == column {
					return false
				}
			}
			return true
		}) ?? []
		
		return data?.selectColumns(columns)
	}
}