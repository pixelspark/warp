import Foundation

internal class QBESortStepView: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	let step: QBESortStep?
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var tableView: NSTableView?
	@IBOutlet var addButton: NSPopUpButton?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBESortStep {
			self.step = s
			super.init(nibName: "QBESortStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBESortStepView", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		self.step = nil
		super.init(coder: coder)
	}
	
	@IBAction func addFromPopupButton(sender: NSObject) {
		if let selected = self.addButton?.selectedItem, let s = step {
			let columnName = selected.title
			let expression = QBESiblingExpression(columnName: QBEColumn(columnName))
			s.orders.append(QBEOrder(expression: expression, ascending: true, numeric: true))
			self.addButton?.stringValue = ""
			self.delegate?.suggestionsView(self, previewStep: s)
			updateView()
		}
	}
	
	internal override func viewWillAppear() {
		updateColumns()
		super.viewWillAppear()
		updateView()
	}
	
	private func updateColumns() {
		let job = QBEJob(.UserInitiated)
		
		if let s = step {
			if let previous = s.previous {
				previous.exampleData(job, maxInputRows: 100, maxOutputRows: 100) { (data) -> () in
					data.use({$0.columnNames(job) {(columns) in
						columns.use { (columnNames) in
							QBEAsyncMain {
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
	}
	
	private func updateView() {
		tableView?.reloadData()
	}
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return step?.orders.count ?? 0
	}
	
	func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
		if item.action() == Selector("delete:") {
			return tableView?.selectedRowIndexes.count > 0
		}
		else if item.action() == Selector("addFromPopupButton:") {
			return step != nil
		}
		return false
	}
	
	@IBAction func delete(sender: NSObject) {
		if let selection = tableView?.selectedRowIndexes, let s = step where selection.count > 0 {
			s.orders.removeObjectsAtIndexes(selection, offset: 0)
			tableView?.reloadData()
			self.delegate?.suggestionsView(self, previewStep: s)
		}
	}
	
	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if let identifier = tableColumn?.identifier {
			if let s = step {
				let order = s.orders[row]
				
				if identifier == "formula" {
					if let formulaString = object as? String {
						if let formula = QBEFormula(formula: formulaString, locale: self.delegate?.locale ?? QBELocale()) {
							order.expression = formula.root
							self.delegate?.suggestionsView(self, previewStep: s)
						}
					}
				}
				else if identifier == "ascending" {
					let oldValue = order.ascending
					order.ascending = object?.boolValue ?? oldValue
					if oldValue != order.ascending {
						self.delegate?.suggestionsView(self, previewStep: s)
					}
				}
				else if identifier == "numeric" {
					let oldValue = order.numeric
					order.numeric = object?.boolValue ?? oldValue
					if oldValue != order.numeric {
						self.delegate?.suggestionsView(self, previewStep: s)
					}
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
				if let s = step {
					let movedItems = s.orders.objectsAtIndexes(rowIndexes)
					movedItems.each({s.orders.remove($0)})
					s.orders.splice(movedItems, atIndex: min(s.orders.count, row))
				}
			}
		}
		tableView.reloadData()
		self.delegate?.suggestionsView(self, previewStep: step)
		return true
	}
	
	internal func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if let identifier = tableColumn?.identifier {
			if let s = step {
				let order = s.orders[row]
				
				if identifier == "formula" {
					if let formulaString = order.expression?.toFormula(self.delegate?.locale ?? QBELocale(), topLevel: true) {
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
		}

		return nil
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		tableView?.registerForDraggedTypes([QBESortStepViewItemType])
	}
}