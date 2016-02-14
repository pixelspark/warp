import Foundation
import WarpCore

internal class QBESortStepView: QBEConfigurableStepViewControllerFor<QBESortStep>, NSTableViewDataSource, NSTableViewDelegate {
	@IBOutlet var tableView: NSTableView?
	@IBOutlet var addButton: NSPopUpButton?

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBESortStepView", bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("Should not be called")
	}
	
	@IBAction func addFromPopupButton(sender: NSObject) {
		if let selected = self.addButton?.selectedItem {
			let columnName = selected.title
			let expression = Sibling(columnName: Column(columnName))
			step.orders.append(Order(expression: expression, ascending: true, numeric: true))
			self.addButton?.stringValue = ""
			self.delegate?.configurableView(self, didChangeConfigurationFor: step)
			updateView()
		}
	}
	
	internal override func viewWillAppear() {
		updateColumns()
		super.viewWillAppear()
		updateView()
	}
	
	private func updateColumns() {
		let job = Job(.UserInitiated)

		if let previous = step.previous {
			previous.exampleData(job, maxInputRows: 100, maxOutputRows: 100) { (data) -> () in
				data.maybe({$0.columnNames(job) {(columns) in
					columns.maybe { (columnNames) in
						asyncMain {
							self.addButton?.removeAllItems()
							self.addButton?.addItemWithTitle(NSLocalizedString("Add sorting criterion...", comment: ""))
							self.addButton?.addItemsWithTitles(columnNames.map({return $0.name}))
							self.updateView()
						}
					}
				}})
			}
		}
		else {
			self.addButton?.removeAllItems()
			self.updateView()
		}
	}
	
	private func updateView() {
		tableView?.reloadData()
	}
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return step.orders.count ?? 0
	}
	
	func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
		if item.action() == Selector("delete:") {
			return tableView?.selectedRowIndexes.count > 0
		}
		else if item.action() == Selector("addFromPopupButton:") {
			return true
		}
		return false
	}
	
	@IBAction func delete(sender: NSObject) {
		if let selection = tableView?.selectedRowIndexes where selection.count > 0 {
			step.orders.removeObjectsAtIndexes(selection, offset: 0)
			tableView?.reloadData()
			self.delegate?.configurableView(self, didChangeConfigurationFor: step)
		}
	}
	
	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if let identifier = tableColumn?.identifier {
			let order = step.orders[row]
			
			if identifier == "formula" {
				if let formulaString = object as? String {
					if let formula = Formula(formula: formulaString, locale: self.delegate?.locale ?? Locale()) {
						order.expression = formula.root
						self.delegate?.configurableView(self, didChangeConfigurationFor: step)
					}
				}
			}
			else if identifier == "ascending" {
				let oldValue = order.ascending
				order.ascending = object?.boolValue ?? oldValue
				if oldValue != order.ascending {
					self.delegate?.configurableView(self, didChangeConfigurationFor: step)
				}
			}
			else if identifier == "numeric" {
				let oldValue = order.numeric
				order.numeric = object?.boolValue ?? oldValue
				if oldValue != order.numeric {
					self.delegate?.configurableView(self, didChangeConfigurationFor: step)
				}
			}
		}
	}
	
	private let QBESortStepViewItemType = "nl.pixelspark.qbe.QBESortStepView.Item"
	
	func tableView(tableView: NSTableView, writeRowsWithIndexes rowIndexes: NSIndexSet, toPasteboard pboard: NSPasteboard) -> Bool {
		let data = NSKeyedArchiver.archivedDataWithRootObject(rowIndexes)
		
		pboard.declareTypes([QBESortStepViewItemType], owner: nil)
		pboard.setData(data, forType: QBESortStepViewItemType)
		return true
	}
	
	
	func tableView(tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation {
		if info.draggingSource() as? NSTableView == tableView {
			if dropOperation == NSTableViewDropOperation.On {
				tableView.setDropRow(row+1, dropOperation: NSTableViewDropOperation.Above)
				return NSDragOperation.Move
			}
		}
		return NSDragOperation.None
	}
	
	func tableView(tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableViewDropOperation) -> Bool {
		let pboard = info.draggingPasteboard()
		if let data = pboard.dataForType(QBESortStepViewItemType) {
			if let rowIndexes = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? NSIndexSet {
				let movedItems = step.orders.objectsAtIndexes(rowIndexes)
				movedItems.forEach { self.step.orders.remove($0) }
				step.orders.insertContentsOf(movedItems, at: min(step.orders.count, row))
			}
		}
		tableView.reloadData()
		self.delegate?.configurableView(self, didChangeConfigurationFor: step)
		return true
	}
	
	internal func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if let identifier = tableColumn?.identifier {
			let order = step.orders[row]
			
			if identifier == "formula" {
				if let formulaString = order.expression?.toFormula(self.delegate?.locale ?? Locale(), topLevel: true) {
					return formulaString
				}
			}
			else if identifier == "ascending" {
				return NSNumber(bool: order.ascending)
			}
			else if identifier == "numeric" {
				return NSNumber(bool: order.numeric)
			}
		}

		return nil
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		tableView?.registerForDraggedTypes([QBESortStepViewItemType])
	}
}