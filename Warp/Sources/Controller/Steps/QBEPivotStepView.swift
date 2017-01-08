/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
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
	
	private var sourceColumns: OrderedSet<Column>? { didSet {
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
			let job = Job(.userInitiated)
			sourceStep.exampleDataset(job, maxInputRows: 100, maxOutputRows: 100, callback: { (exDataset: Fallible<Dataset>) -> () in
				exDataset.maybe({ (ed) in ed.columns(job) { (columns: Fallible<OrderedSet<Column>>) -> () in
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
		
		allTable?.register(forDraggedTypes: [dragType])
		rowsTable?.register(forDraggedTypes: [dragType])
		columnsTable?.register(forDraggedTypes: [dragType])
		aggregatesTable?.register(forDraggedTypes: [dragType])
		
		aggregatorsMenu = NSMenu()
		for fun in Function.allFunctions {
			if fun.reducer != nil {
				let item = NSMenuItem(title: fun.localizedName, action: nil, keyEquivalent: "")
				item.representedObject = fun.rawValue
				aggregatorsMenu!.addItem(item)
			}
		}
	}
	
	internal func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
		var cols: [Any] = []
		
		(rowIndexes as NSIndexSet).enumerate({ (index, stop) -> Void in
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
				cols.append(self.step.aggregates[index])
			}
		})
		
		let data = NSKeyedArchiver.archivedData(withRootObject: cols)
		pboard.declareTypes([dragType], owner: nil)
		pboard.setData(data, forType: dragType)
		return true
	}
	
	internal func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation {
		let pboard = info.draggingPasteboard()
		if pboard.data(forType: dragType) != nil {
			// Dragging from self is disallowed
			if info.draggingSource() as? NSTableView == tableView {
				return NSDragOperation()
			}
			
			return (tableView == self.allTable!) ? NSDragOperation.delete : NSDragOperation.copy
		}
		
		return NSDragOperation()
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(QBEPivotStepView.delete(_:)) {
			if let fr = self.view.window?.firstResponder {
				return fr == rowsTable || fr == columnsTable || fr == aggregatesTable
			}
		}
		return false
	}
	
	@IBAction func delete(_ sender: NSObject) {
		// Is one of our table views selected?
		if rowsTable == self.view.window?.firstResponder {
			if let index = rowsTable?.selectedRow {
				if index >= 0 {
					self.step.rows.remove(at: index)
					rowsTable!.reloadData()
				}
			}
		}
		else if columnsTable == self.view.window?.firstResponder {
			if let index = columnsTable?.selectedRow {
				if index >= 0 {
					self.step.columns.remove(at: index)
					columnsTable!.reloadData()
				}
			}
		}
		else if aggregatesTable == self.view.window?.firstResponder {
			if let index = aggregatesTable?.selectedRow {
				if index >= 0 {
					self.step.aggregates.remove(at: index)
					aggregatesTable!.reloadData()
				}
			}
		}
		else {
			return
		}
		
		delegate?.configurableView(self, didChangeConfigurationFor: step)
	}
	
	internal func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableViewDropOperation) -> Bool {
		let pboard = info.draggingPasteboard()
		if let data = pboard.data(forType: dragType) {
			// Dragging from self is disallowed
			if info.draggingSource() as? NSTableView == tableView {
				return false
			}
			
			// Unpack data and add
			if let cols = NSKeyedUnarchiver.unarchiveObject(with: data) as? [AnyObject] {
				for col in cols {
					if let columnName = col as? String {
						let column = Column(columnName)
						if tableView == rowsTable && !self.step.rows.contains(column) {
							self.step.rows.append(column)
						}
						else if tableView == columnsTable && !self.step.columns.contains(column) {
							self.step.columns.append(column)
						}
						else if tableView == aggregatesTable {
							self.step.aggregates.append(Aggregation(map: Sibling(column), reduce: Function.Sum, targetColumn: column))
						}
						else if tableView == allTable {
							// Need to remove the dragged item from the source view
							if info.draggingSource() as? NSTableView == rowsTable {
								self.step.rows.remove(column)
							}
							else if info.draggingSource() as? NSTableView == columnsTable {
								self.step.columns.remove(column)
							}
						}
					}
					else if let aggregation = col as? Aggregation {
						if let columnExpression = aggregation.aggregator.map as? Sibling {
							let column = columnExpression.column
							if tableView == rowsTable && !self.step.rows.contains(column) {
								self.step.rows.append(column)
							}
							else if tableView == columnsTable && !self.step.columns.contains(column) {
								self.step.columns.append(column)
							}
							else if tableView == allTable {
								// TODO: remove aggregation from source table
							}
						}
					}
				}

				tableView.reloadData()
				(info.draggingSource() as? NSTableView)?.reloadData()
			}
			
			tableView.reloadData()
			delegate?.configurableView(self, didChangeConfigurationFor: step)
			return true
		}
		
		return false
	}
	
	func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
		if tableView == aggregatesTable {
			if tableColumn?.identifier == "aggregator" {
				if let menuItem = aggregatorsMenu?.item(at: (object as? Int) ?? 0) {
					if let rep = menuItem.representedObject as? Function.RawValue {
						if let fun = Function(rawValue: rep) {
							step.aggregates[row].aggregator.reduce = fun
							tableView.reloadData()
							delegate?.configurableView(self, didChangeConfigurationFor: step)
						}
					}
				}
			}
			else if tableColumn?.identifier == "targetColumn" {
				if let s = object as? String {
					step.aggregates[row].targetColumn = Column(s)
				}
			}
		}
	}
	
	func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
		if tableView == aggregatesTable {
			return true
		}
		return false
	}
	
	func tableView(_ tableView: NSTableView, dataCellFor tableColumn: NSTableColumn?, row: Int) -> NSCell? {
		if tableColumn?.identifier == "aggregator" {
			if let cell = tableColumn?.dataCell(forRow: row) as? NSPopUpButtonCell {
				cell.menu = self.aggregatorsMenu
				return cell
			}
		}
		return nil
	}
	
	internal func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		if tableColumn?.identifier == "aggregator" {
			let reducer = step.aggregates[row].aggregator.reduce 
			
			for index in 0..<aggregatorsMenu!.numberOfItems {
				if let mi = aggregatorsMenu!.item(at: index) {
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
				return step.aggregates[row].targetColumn.name
				
			default:
				return ""
		}
	}
	
	internal func numberOfRows(in tableView: NSTableView) -> Int {
		switch tableView {
			case allTable!:
				return sourceColumns?.count ?? 0
				
			case rowsTable!:
				return step.rows.count 
				
			case columnsTable!:
				return step.columns.count 
				
			case aggregatesTable!:
				return step.aggregates.count 
				
			default:
				return 0
		}
	}
}
