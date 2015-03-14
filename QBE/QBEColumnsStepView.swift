import Foundation

internal class QBEColumnsStepView: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	let step: QBEColumnsStep?
	var columnNames: [QBEColumn] = []
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var tableView: NSTableView?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBEColumnsStep {
			self.step = s
			super.init(nibName: "QBEColumnsStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBEColumnsStepView", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		self.step = nil
		super.init(coder: coder)
	}
	
	internal override func viewWillAppear() {
		updateColumns()
		super.viewWillAppear()
		updateView()
	}
	
	private func updateColumns() {
		if let s = step {
			if let previous = s.previous {
				previous.exampleData(nil, callback: { (data) -> () in
					data.columnNames({(columns) in
						QBEAsyncMain {
							self.columnNames = columns
							self.updateView()
						}
					})
				})
			}
			else {
				columnNames.removeAll()
				self.updateView()
			}
		}
	}
	
	private func updateView() {
		tableView?.reloadData()
	}
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return columnNames.count
	}
	
	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if let s = step {
			if let identifier = tableColumn?.identifier where identifier == "selected" {
				let select = object?.boolValue ?? false
				let name = columnNames[row]
				s.columnNames.remove(name)
				if select {
					s.columnNames.append(name)
				}
			}
			self.delegate?.suggestionsView(self, previewStep: s)
		}
	}
	
	internal func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if let tc = tableColumn {
			if (tc.identifier ?? "") == "column" {
				return columnNames[row].name
			}
			else {
				if let s = step {
					return NSNumber(bool: find(s.columnNames, columnNames[row]) != nil)
				}
			}
		}
		return nil
	}
}