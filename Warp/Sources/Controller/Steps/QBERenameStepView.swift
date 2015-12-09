import Foundation
import WarpCore

internal class QBERenameStepView: QBEStepViewControllerFor<QBERenameStep>, NSTableViewDataSource, NSTableViewDelegate {
	var columnNames: [Column] = []
	@IBOutlet var tableView: NSTableView?

	required init?(step: QBEStep, delegate: QBEStepViewDelegate) {
		super.init(step: step, delegate: delegate, nibName: "QBERenameStepView", bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("Should not be called")
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
				data.maybe({ $0.columnNames(job) {(columns) in
					columns.maybe {(cns) in
						asyncMain {
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
	
	private func updateView() {
		tableView?.reloadData()
	}
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return columnNames.count
	}
	
	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if let identifier = tableColumn?.identifier where identifier == "new" {
			let name = columnNames[row]
			if let newName = object as? String where !newName.isEmpty {
				step.renames[name] = Column(newName)
			}
			else {
				step.renames.removeValueForKey(name)
			}
		}
		self.delegate?.stepView(self, didChangeConfigurationForStep: step)
	}
	
	internal func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if let tc = tableColumn {
			if (tc.identifier ?? "") == "old" {
				return columnNames[row].name
			}
			else if (tc.identifier ?? "") == "new" {
				let oldName = columnNames[row]
				if let newName = step.renames[oldName] {
					return newName.name
				}
				return ""
			}
		}
		return nil
	}
}