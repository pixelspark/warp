import Foundation

internal class QBERenameStepView: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	let step: QBERenameStep?
	var columnNames: [QBEColumn] = []
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var tableView: NSTableView?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBERenameStep {
			self.step = s
			super.init(nibName: "QBERenameStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBERenameStepView", bundle: nil)
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
		let job = QBEJob(.UserInitiated)
		if let s = step {
			if let previous = s.previous {
				previous.exampleData(job, maxInputRows: 100, maxOutputRows: 100) { (data) -> () in
					data.use({$0.columnNames(job) {(columns) in
						columns.use {(cns) in
							QBEAsyncMain {
								self.columnNames = cns
								self.updateView()
							}
						}
						}})
				}
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
			if let identifier = tableColumn?.identifier where identifier == "new" {
				let name = columnNames[row]
				if let newName = object as? String where !newName.isEmpty {
					s.renames[name] = QBEColumn(newName)
				}
				else {
					s.renames.removeValueForKey(name)
				}
			}
			self.delegate?.suggestionsView(self, previewStep: s)
		}
	}
	
	internal func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if let tc = tableColumn {
			if (tc.identifier ?? "") == "old" {
				return columnNames[row].name
			}
			else if (tc.identifier ?? "") == "new" {
				if let s = step {
					let oldName = columnNames[row]
					if let newName = s.renames[oldName] {
						return newName.name
					}
					return ""
				}
			}
		}
		return nil
	}
}