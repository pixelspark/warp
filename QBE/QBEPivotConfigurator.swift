import Foundation
import Cocoa

internal class QBEPivotConfigurator: NSViewController, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
	private let dragType = "nl.pixelspark.qbe.column"
	
	weak var delegate: QBESuggestionsViewDelegate?
	let step: QBEPivotStep?
	@IBOutlet var allTable: NSTableView?
	@IBOutlet var rowsTable: NSTableView?
	@IBOutlet var columnsTable: NSTableView?
	@IBOutlet var aggregatesTable: NSTableView?
	private var aggregatorsMenu: NSMenu?
	
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
		if let data = pboard.dataForType(dragType) {
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
	
	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
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
				return step?.previous?.exampleData?.raster().columnNames[row].name
				
			case rowsTable!:
				return step?.rows[row].name
				
			case columnsTable!:
				return step?.columns[row].name
				
			case aggregatesTable!:
				return step?.aggregates[row].map.explain(delegate!.locale)
				
			default:
				return ""
		}
	}
	
	internal func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		switch tableView {
			case allTable!:
				return step?.previous?.exampleData?.columnNames.count ?? 0
				
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
