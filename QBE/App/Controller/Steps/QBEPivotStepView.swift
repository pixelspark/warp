import Foundation
import Cocoa

internal class QBEPivotStepView: NSViewController, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
	private let dragType = "nl.pixelspark.qbe.column"
	
	weak var delegate: QBESuggestionsViewDelegate?
	let step: QBEPivotStep?
	@IBOutlet var allTable: NSTableView?
	@IBOutlet var rowsTable: NSTableView?
	@IBOutlet var columnsTable: NSTableView?
	@IBOutlet var aggregatesTable: NSTableView?
	private var aggregatorsMenu: NSMenu?
	
	private var sourceColumns: [QBEColumn]? { didSet {
		allTable?.reloadData()
		rowsTable?.reloadData()
		columnsTable?.reloadData()
		aggregatesTable?.reloadData()
	} }
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBEPivotStep {
			self.step = s
			super.init(nibName: "QBEPivotStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBEPivotStepView", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		step = nil
		super.init(coder: coder)
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
	
		if let sourceStep = self.step?.previous {
			let job = QBEJob(.UserInitiated)
			sourceStep.exampleData(job, maxInputRows: 100, maxOutputRows: 100, callback: { (exData: QBEFallible<QBEData>) -> () in
				exData.use({(ed) in ed.columnNames(job) { (columns: QBEFallible<[QBEColumn]>) -> () in
					columns.use { (cs) in
						QBEAsyncMain {
							self.sourceColumns = cs
						}
					}
				}})
			})
		}
		else {
			self.sourceColumns = []
		}
	}
	
	internal override func awakeFromNib() {
		super.awakeFromNib()
		
		allTable?.registerForDraggedTypes([dragType])
		rowsTable?.registerForDraggedTypes([dragType])
		columnsTable?.registerForDraggedTypes([dragType])
		aggregatesTable?.registerForDraggedTypes([dragType])
		
		aggregatorsMenu = NSMenu()
		for fun in QBEFunction.allFunctions {
			if fun.arity == QBEArity.Any {
				let item = NSMenuItem(title: fun.explain(delegate!.locale), action: nil, keyEquivalent: "")
				item.representedObject = fun.rawValue
				aggregatorsMenu!.addItem(item)
			}
		}
	}
	
	internal func tableView(tableView: NSTableView, writeRowsWithIndexes rowIndexes: NSIndexSet, toPasteboard pboard: NSPasteboard) -> Bool {
		var cols: [String] = []
		
		rowIndexes.enumerateIndexesUsingBlock({ (index, stop) -> Void in
			if tableView == self.allTable! {
				if let column = self.sourceColumns?[index].name {
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
				if let column = self.step?.aggregates[index].map.description {
					cols.append(column)
				}
			}
		})
		
		let data = NSArchiver.archivedDataWithRootObject(cols)
		pboard.declareTypes([dragType], owner: nil)
		pboard.setData(data, forType: dragType)
		return true
	}
	
	internal func tableView(tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation {
		let pboard = info.draggingPasteboard()
		if pboard.dataForType(dragType) != nil {
			// Dragging from self is disallowed
			if info.draggingSource() as? NSTableView == tableView {
				return NSDragOperation.None
			}
			
			return (tableView == self.allTable!) ? NSDragOperation.Delete : NSDragOperation.Copy
		}
		
		return NSDragOperation.None
	}
	
	override func validateMenuItem(menuItem: NSMenuItem) -> Bool {
		if menuItem.action == Selector("delete:") {
			if let fr = self.view.window?.firstResponder {
				return fr == rowsTable || fr == columnsTable || fr == aggregatesTable
			}
		}
		return false
	}
	
	@IBAction func delete(sender: NSObject) {
		// Is one of our table views selected?
		if rowsTable == self.view.window?.firstResponder {
			if let index = rowsTable?.selectedRow {
				if index >= 0 {
					self.step?.rows.removeAtIndex(index)
					rowsTable!.reloadData()
				}
			}
		}
		else if columnsTable == self.view.window?.firstResponder {
			if let index = columnsTable?.selectedRow {
				if index >= 0 {
					self.step?.columns.removeAtIndex(index)
					columnsTable!.reloadData()
				}
			}
		}
		else if aggregatesTable == self.view.window?.firstResponder {
			if let index = aggregatesTable?.selectedRow {
				if index >= 0 {
					self.step?.aggregates.removeAtIndex(index)
					aggregatesTable!.reloadData()
				}
			}
		}
		else {
			return
		}
		
		delegate?.suggestionsView(self, previewStep: nil)
	}
	
	internal func tableView(tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableViewDropOperation) -> Bool {
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
						self.step?.aggregates.append(QBEAggregation(map: QBESiblingExpression(columnName: QBEColumn(col)), reduce: QBEFunction.Sum, targetColumnName: QBEColumn(col)))
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
							// FIXME: needs to remove a QBEAggregation object
							//self.step?.aggregates.remove(QBEColumn(col))
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
	
	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if tableView == aggregatesTable {
			if tableColumn?.identifier == "aggregator" {
				if let menuItem = aggregatorsMenu?.itemAtIndex(object?.integerValue ?? 0) {
					if let rep = menuItem.representedObject as? QBEFunction.RawValue {
						if let fun = QBEFunction(rawValue: rep) {
							step?.aggregates[row].reduce = fun
							tableView.reloadData()
							delegate?.suggestionsView(self, previewStep: nil)
						}
					}
				}
			}
			else if tableColumn?.identifier == "targetColumnName" {
				if let s = object as? String {
					step?.aggregates[row].targetColumnName = QBEColumn(s)
				}
			}
		}
	}
	
	func tableView(tableView: NSTableView, shouldEditTableColumn tableColumn: NSTableColumn?, row: Int) -> Bool {
		if tableView == aggregatesTable {
			return true
		}
		return false
	}
	
	func tableView(tableView: NSTableView, dataCellForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSCell? {
		if tableColumn?.identifier == "aggregator" {
			if let cell = tableColumn?.dataCell as? NSPopUpButtonCell {
				cell.menu = self.aggregatorsMenu
				return cell
			}
		}
		return nil
	}
	
	internal func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if tableColumn?.identifier == "aggregator" {
			let reducer = step?.aggregates[row].reduce ?? QBEFunction.Identity
			
			for index in 0..<aggregatorsMenu!.numberOfItems {
				if let mi = aggregatorsMenu!.itemAtIndex(index) {
					if (mi.representedObject as? QBEFunction.RawValue) == reducer.rawValue {
						return index
					}
				}
			}
			return nil
		}
		
		switch tableView {
			case allTable!:
				return sourceColumns?[row].name
			
			case rowsTable!:
				return step?.rows[row].name
				
			case columnsTable!:
				return step?.columns[row].name
				
			case aggregatesTable!:
				return step?.aggregates[row].targetColumnName.name
				
			default:
				return ""
		}
	}
	
	internal func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		switch tableView {
			case allTable!:
				return sourceColumns?.count ?? 0
				
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
