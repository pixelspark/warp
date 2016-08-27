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
	
	@IBAction func addFromPopupButton(_ sender: NSObject) {
		if let selected = self.addButton?.selectedItem {
			let columnName = selected.title
			let expression = Sibling(Column(columnName))
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
		let job = Job(.userInitiated)

		if let previous = step.previous {
			previous.exampleDataset(job, maxInputRows: 100, maxOutputRows: 100) { (data) -> () in
				data.maybe({$0.columns(job) {(columns) in
					columns.maybe { (columns) in
						asyncMain {
							self.addButton?.removeAllItems()
							self.addButton?.addItem(withTitle: NSLocalizedString("Add sorting criterion...", comment: ""))
							self.addButton?.addItems(withTitles: columns.map({return $0.name}))
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
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		return step.orders.count 
	}

	func validate(_ item: NSValidatedUserInterfaceItem) -> Bool {
		return self.validateUserInterfaceItem(item)
	}
	
	func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		if item.action == #selector(QBESortStepView.delete(_:)) {
			return (tableView?.selectedRowIndexes.count ?? 0) > 0
		}
		else if item.action == #selector(QBESortStepView.addFromPopupButton(_:)) {
			return true
		}
		return false
	}
	
	@IBAction func delete(_ sender: NSObject) {
		if let selection = tableView?.selectedRowIndexes, selection.count > 0 {
			step.orders.removeObjectsAtIndexes(selection, offset: 0)
			tableView?.reloadData()
			self.delegate?.configurableView(self, didChangeConfigurationFor: step)
		}
	}
	
	func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
		if let identifier = tableColumn?.identifier {
			let order = step.orders[row]
			
			if identifier == "formula" {
				if let formulaString = object as? String {
					if let formula = Formula(formula: formulaString, locale: self.delegate?.locale ?? Language()) {
						order.expression = formula.root
						self.delegate?.configurableView(self, didChangeConfigurationFor: step)
					}
				}
			}
			else if identifier == "ascending" {
				let oldValue = order.ascending
				order.ascending = (object as AnyObject).boolValue
				if oldValue != order.ascending {
					self.delegate?.configurableView(self, didChangeConfigurationFor: step)
				}
			}
			else if identifier == "numeric" {
				let oldValue = order.numeric
				order.numeric = (object as AnyObject).boolValue
				if oldValue != order.numeric {
					self.delegate?.configurableView(self, didChangeConfigurationFor: step)
				}
			}
		}
	}
	
	private let QBESortStepViewItemType = "nl.pixelspark.qbe.QBESortStepView.Item"
	
	func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
		let data = NSKeyedArchiver.archivedData(withRootObject: rowIndexes)
		
		pboard.declareTypes([QBESortStepViewItemType], owner: nil)
		pboard.setData(data, forType: QBESortStepViewItemType)
		return true
	}
	
	
	func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation {
		if info.draggingSource() as? NSTableView == tableView {
			if dropOperation == NSTableViewDropOperation.on {
				tableView.setDropRow(row+1, dropOperation: NSTableViewDropOperation.above)
				return NSDragOperation.move
			}
		}
		return NSDragOperation()
	}
	
	func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableViewDropOperation) -> Bool {
		let pboard = info.draggingPasteboard()
		if let data = pboard.data(forType: QBESortStepViewItemType) {
			if let rowIndexes = NSKeyedUnarchiver.unarchiveObject(with: data) as? IndexSet {
				let movedItems = step.orders.objectsAtIndexes(rowIndexes)
				movedItems.forEach { self.step.orders.remove($0) }
				step.orders.insert(contentsOf: movedItems, at: min(step.orders.count, row))
			}
		}
		tableView.reloadData()
		self.delegate?.configurableView(self, didChangeConfigurationFor: step)
		return true
	}
	
	internal func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		if let identifier = tableColumn?.identifier {
			let order = step.orders[row]
			
			if identifier == "formula" {
				if let formulaString = order.expression?.toFormula(self.delegate?.locale ?? Language(), topLevel: true) {
					return formulaString
				}
			}
			else if identifier == "ascending" {
				return NSNumber(value: order.ascending)
			}
			else if identifier == "numeric" {
				return NSNumber(value: order.numeric)
			}
		}

		return nil
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		tableView?.register(forDraggedTypes: [QBESortStepViewItemType])
	}
}
