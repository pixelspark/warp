import Foundation
import Cocoa

typealias QBEConfigurator = (step: QBEStep?, delegate: QBESuggestionsViewDelegate) -> NSViewController?

let QBEConfigurators: Dictionary<String, QBEConfigurator> = [
	QBESQLiteSourceStep.className(): {QBESQLiteSourceConfigurator(step: $0, delegate: $1)},
	QBELimitStep.className(): {QBELimitConfigurator(step: $0, delegate: $1)},
	QBERandomStep.className(): {QBERandomConfigurator(step: $0, delegate: $1)},
	QBECalculateStep.className(): {QBECalculateConfigurator(step: $0, delegate: $1)},
	QBEPivotStep.className(): {QBEPivotConfigurator(step: $0, delegate: $1)}
]

private class QBEPivotConfigurator: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
	private let dragType = "nl.pixelspark.qbe.column"
	
	weak var delegate: QBESuggestionsViewDelegate?
	let step: QBEPivotStep?
	@IBOutlet var allTable: NSTableView?
	@IBOutlet var rowsTable: NSTableView?
	@IBOutlet var columnsTable: NSTableView?
	@IBOutlet var aggregatesTable: NSTableView?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBEPivotStep {
			self.step = s
			super.init(nibName: "QBEPivotConfigurator", bundle: nil)
		}
		else {
			super.init(nibName: "QBEPivotConfigurator", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	private override func awakeFromNib() {
		super.awakeFromNib()
		
		allTable?.registerForDraggedTypes([dragType])
		rowsTable?.registerForDraggedTypes([dragType])
		columnsTable?.registerForDraggedTypes([dragType])
		aggregatesTable?.registerForDraggedTypes([dragType])
	}
	
	private func tableView(tableView: NSTableView, writeRowsWithIndexes rowIndexes: NSIndexSet, toPasteboard pboard: NSPasteboard) -> Bool {
		var cols: [String] = []
		
		rowIndexes.enumerateIndexesUsingBlock({ (index, stop) -> Void in
			if tableView == self.allTable! {
				if let column = self.step?.previous?.exampleData?.raster().columnNames[index].name {
					cols.append(column)
				}
			}
			else if tableView == self.rowsTable! {
				if let column = self.step?.rows[index].name {
					cols.append(column)
				}
			}
			else if tableView == self.columnsTable! {
				if let column = self.step?.columns[index].name {
					cols.append(column)
				}
			}
			else if tableView == self.aggregatesTable! {
				if let column = self.step?.aggregates[index].name {
					cols.append(column)
				}
			}
		})
		
		let data = NSArchiver.archivedDataWithRootObject(cols)
		pboard.declareTypes([dragType], owner: nil)
		pboard.setData(data, forType: dragType)
		return true
	}
	
	private func tableView(tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation {
		let pboard = info.draggingPasteboard()
		if let data = pboard.dataForType(dragType) {
			// Dragging from self is disallowed
			if info.draggingSource() as? NSTableView == tableView {
				return NSDragOperation.None
			}
			
			return (tableView == self.allTable!) ? NSDragOperation.Delete : NSDragOperation.Copy
		}
		
		return NSDragOperation.None
	}
	
	private func tableView(tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableViewDropOperation) -> Bool {
		let pboard = info.draggingPasteboard()
		if let data = pboard.dataForType(dragType) {
			// Dragging from self is disallowed
			if info.draggingSource() as? NSTableView == tableView {
				return false
			}
			
			// Unpack data and add
			if let cols = NSUnarchiver.unarchiveObjectWithData(data) as? [String] {
				for col in cols {
					if tableView == rowsTable {
						if !(self.step?.rows.contains(QBEColumn(col)) ?? false) {
							self.step?.rows.append(QBEColumn(col))
						}
					}
					else if tableView == columnsTable {
						if !(self.step?.columns.contains(QBEColumn(col)) ?? false) {
							self.step?.columns.append(QBEColumn(col))
						}
					}
					else if tableView == aggregatesTable {
						if !(self.step?.aggregates.contains(QBEColumn(col)) ?? false) {
							self.step?.aggregates.append(QBEColumn(col))
						}
					}
					else if tableView == allTable {
						// Need to remove the dragged item from the source view
						if info.draggingSource() as? NSTableView == rowsTable {
							self.step?.rows.remove(QBEColumn(col))
							rowsTable?.reloadData()
						}
						else if info.draggingSource() as? NSTableView == columnsTable {
							self.step?.columns.remove(QBEColumn(col))
							columnsTable?.reloadData()
						}
						else if info.draggingSource() as? NSTableView == aggregatesTable {
							self.step?.aggregates.remove(QBEColumn(col))
							aggregatesTable?.reloadData()
						}
					}
				}
			}
			
			tableView.reloadData()
			delegate?.suggestionsView(self, previewStep: nil)
			return true
		}
		
		return false
	}
	
	private func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		switch tableView {
		case allTable!:
			return step?.previous?.exampleData?.raster().columnNames[row].name
			
		case rowsTable!:
			return step?.rows[row].name
			
		case columnsTable!:
			return step?.columns[row].name
			
		case aggregatesTable!:
			return step?.aggregates[row].name
			
		default:
			return 0
		}
	}
	
	private func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		switch tableView {
		case allTable!:
			return step?.previous?.exampleData?.raster().columnNames.count ?? 0
			
		case rowsTable!:
			return step?.rows.count ?? 0
			
		case columnsTable!:
			return step?.columns.count ?? 0
			
		case aggregatesTable!:
			return step?.aggregates.count ?? 0
			
		default:
			return 0
		}
	}
}

private class QBECalculateConfigurator: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var targetColumnNameField: NSTextField?
	@IBOutlet var formulaField: NSTextField?
	let step: QBECalculateStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBECalculateStep {
			self.step = s
			super.init(nibName: "QBECalculateConfigurator", bundle: nil)
		}
		else {
			super.init(nibName: "QBECalculateConfigurator", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	private override func viewWillAppear() {
		super.viewWillAppear()
		if let s = step {
			self.targetColumnNameField?.stringValue = s.targetColumn.name
			self.formulaField?.stringValue = "=" + s.function.toFormula(self.delegate?.locale ?? QBEDefaultLocale())
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			s.targetColumn = QBEColumn(self.targetColumnNameField?.stringValue ?? s.targetColumn.name)
			if let f = self.formulaField?.stringValue {
				if let parsed = QBEFormula(formula: f, locale: (self.delegate?.locale ?? QBEDefaultLocale()))?.root {
					s.function = parsed
				}
				else {
					// TODO parsing error
				}
			}
			delegate?.suggestionsView(self, previewStep: s)
		}
	}
}

private class QBERandomConfigurator: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var numberOfRowsField: NSTextField?
	let step: QBERandomStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBERandomStep {
			self.step = s
			super.init(nibName: "QBERandomConfigurator", bundle: nil)
		}
		else {
			super.init(nibName: "QBERandomConfigurator", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	private override func viewWillAppear() {
		super.viewWillAppear()
		if let s = step {
			numberOfRowsField?.stringValue = s.numberOfRows.toString()
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			s.numberOfRows = (numberOfRowsField?.stringValue ?? "1").toInt() ?? 1
			delegate?.suggestionsView(self, previewStep: s)
		}
	}
}

private class QBELimitConfigurator: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var numberOfRowsField: NSTextField?
	let step: QBELimitStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBELimitStep {
			self.step = s
			super.init(nibName: "QBELimitConfigurator", bundle: nil)
		}
		else {
			super.init(nibName: "QBELimitConfigurator", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	private override func viewWillAppear() {
		super.viewWillAppear()
		if let s = step {
			numberOfRowsField?.stringValue = s.numberOfRows.toString()
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			s.numberOfRows = (numberOfRowsField?.stringValue ?? "1").toInt() ?? 1
			delegate?.suggestionsView(self, previewStep: s)
		}
	}
}

private class QBESQLiteSourceConfigurator: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	let step: QBESQLiteSourceStep?
	var tableNames: [String]?
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var tableView: NSTableView?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBESQLiteSourceStep {
			self.step = s
			super.init(nibName: "QBESQLiteSourceConfigurator", bundle: nil)
		}
		else {
			super.init(nibName: "QBESQLiteSourceConfigurator", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	private override func viewWillAppear() {
		super.viewWillAppear()
		
		// Fetch table names
		if let s = step {
			tableNames = []
			if let db = s.db {
				tableNames = db.tableNames
			}
			
			tableView?.reloadData()
			// Select current table
			if tableNames != nil {
				let currentTable = s.tableName
				for i in 0..<tableNames!.count {
					if tableNames![i]==currentTable {
						tableView?.selectRowIndexes(NSIndexSet(index: i), byExtendingSelection: false)
						break
					}
				}
			}
		}
	}
	
	private func tableViewSelectionDidChange(notification: NSNotification) {
		let selection = tableView?.selectedRow ?? -1
		if tableNames != nil && selection >= 0 && selection < tableNames!.count {
			let selectedName = tableNames![selection]
			step?.tableName = selectedName
			delegate?.suggestionsView(self, previewStep: step)
		}
	}
	
	private func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return tableNames?.count ?? 0
	}
	
	private func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		return tableNames?[row] ?? ""
	}
}