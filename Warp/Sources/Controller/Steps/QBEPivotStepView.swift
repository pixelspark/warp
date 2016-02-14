import Foundation
import Cocoa
import WarpCore

internal class QBEPivotStepView: QBEConfigurableStepViewControllerFor<QBEPivotStep>, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
	private let dragType = "nl.pixelspark.qbe.column"

	@IBOutlet var allTable: NSTableView?
	@IBOutlet var rowsTable: NSTableView?
	@IBOutlet var columnsTable: NSTableView?
	@IBOutlet var aggregatesTable: NSTableView?
	private var aggregatorsMenu: NSMenu?
	
	private var sourceColumns: [Column]? { didSet {
		allTable?.reloadData()
		rowsTable?.reloadData()
		columnsTable?.reloadData()
		aggregatesTable?.reloadData()
	} }

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBEPivotStepView", bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("Should not be called")
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
	
		if let sourceStep = self.step.previous {
			let job = Job(.UserInitiated)
			sourceStep.exampleData(job, maxInputRows: 100, maxOutputRows: 100, callback: { (exData: Fallible<Data>) -> () in
				exData.maybe({ (ed) in ed.columnNames(job) { (columns: Fallible<[Column]>) -> () in
					columns.maybe { (cs) in
						asyncMain {
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

		let locale = delegate?.locale ?? Locale()
		
		aggregatorsMenu = NSMenu()
		for fun in Function.allFunctions {
			if fun.reducer != nil {
				let item = NSMenuItem(title: fun.explain(locale), action: nil, keyEquivalent: "")
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
				cols.append(self.step.rows[index].name)
			}
			else if tableView == self.columnsTable! {
				cols.append(self.step.columns[index].name)
			}
			else if tableView == self.aggregatesTable! {
				cols.append(self.step.aggregates[index].map.description)
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
					self.step.rows.removeAtIndex(index)
					rowsTable!.reloadData()
				}
			}
		}
		else if columnsTable == self.view.window?.firstResponder {
			if let index = columnsTable?.selectedRow {
				if index >= 0 {
					self.step.columns.removeAtIndex(index)
					columnsTable!.reloadData()
				}
			}
		}
		else if aggregatesTable == self.view.window?.firstResponder {
			if let index = aggregatesTable?.selectedRow {
				if index >= 0 {
					self.step.aggregates.removeAtIndex(index)
					aggregatesTable!.reloadData()
				}
			}
		}
		else {
			return
		}
		
		delegate?.configurableView(self, didChangeConfigurationFor: step)
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
						if !(self.step.rows.contains(Column(col)) ?? false) {
							self.step.rows.append(Column(col))
						}
					}
					else if tableView == columnsTable {
						if !(self.step.columns.contains(Column(col)) ?? false) {
							self.step.columns.append(Column(col))
						}
					}
					else if tableView == aggregatesTable {
						self.step.aggregates.append(Aggregation(map: Sibling(columnName: Column(col)), reduce: Function.Sum, targetColumnName: Column(col)))
					}
					else if tableView == allTable {
						// Need to remove the dragged item from the source view
						if info.draggingSource() as? NSTableView == rowsTable {
							self.step.rows.remove(Column(col))
							rowsTable?.reloadData()
						}
						else if info.draggingSource() as? NSTableView == columnsTable {
							self.step.columns.remove(Column(col))
							columnsTable?.reloadData()
						}
						else if info.draggingSource() as? NSTableView == aggregatesTable {
							// FIXME: needs to remove a Aggregation object
							//self.step.aggregates.remove(Column(col))
							aggregatesTable?.reloadData()
						}
					}
				}
			}
			
			tableView.reloadData()
			delegate?.configurableView(self, didChangeConfigurationFor: step)
			return true
		}
		
		return false
	}
	
	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if tableView == aggregatesTable {
			if tableColumn?.identifier == "aggregator" {
				if let menuItem = aggregatorsMenu?.itemAtIndex(object?.integerValue ?? 0) {
					if let rep = menuItem.representedObject as? Function.RawValue {
						if let fun = Function(rawValue: rep) {
							step.aggregates[row].reduce = fun
							tableView.reloadData()
							delegate?.configurableView(self, didChangeConfigurationFor: step)
						}
					}
				}
			}
			else if tableColumn?.identifier == "targetColumnName" {
				if let s = object as? String {
					step.aggregates[row].targetColumnName = Column(s)
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
			let reducer = step.aggregates[row].reduce ?? Function.Identity
			
			for index in 0..<aggregatorsMenu!.numberOfItems {
				if let mi = aggregatorsMenu!.itemAtIndex(index) {
					if (mi.representedObject as? Function.RawValue) == reducer.rawValue {
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
				return step.rows[row].name
				
			case columnsTable!:
				return step.columns[row].name
				
			case aggregatesTable!:
				return step.aggregates[row].targetColumnName.name
				
			default:
				return ""
		}
	}
	
	internal func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		switch tableView {
			case allTable!:
				return sourceColumns?.count ?? 0
				
			case rowsTable!:
				return step.rows.count ?? 0
				
			case columnsTable!:
				return step.columns.count ?? 0
				
			case aggregatesTable!:
				return step.aggregates.count ?? 0
				
			default:
				return 0
		}
	}
}
