import Foundation
import WarpCore

internal class QBERenameStepView: QBEConfigurableStepViewControllerFor<QBERenameStep>, NSTableViewDataSource, NSTableViewDelegate {
	var columns: OrderedSet<Column> = []
	@IBOutlet var tableView: NSTableView?

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBERenameStepView", bundle: nil)
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
		let job = Job(.userInitiated)
		if let previous = step.previous {
			previous.exampleDataset(job, maxInputRows: 100, maxOutputRows: 100) { (data) -> () in
				data.maybe({ $0.columns(job) {(columns) in
					columns.maybe {(cns) in
						asyncMain {
							self.columns = cns
							self.updateView()
						}
					}
					}})
			}
		}
		else {
			columns.removeAll()
			self.updateView()
		}
	}
	
	private func updateView() {
		tableView?.reloadData()
	}
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		return columns.count
	}
	
	func tableView(_ tableView: NSTableView, setObjectValue object: AnyObject?, for tableColumn: NSTableColumn?, row: Int) {
		if let identifier = tableColumn?.identifier, identifier == "new" {
			let name = columns[row]
			if let newName = object as? String, !newName.isEmpty {
				step.renames[name] = Column(newName)
			}
			else {
				step.renames.removeValue(forKey: name)
			}
		}
		self.delegate?.configurableView(self, didChangeConfigurationFor: step)
	}
	
	internal func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if let tc = tableColumn {
			if (tc.identifier ?? "") == "old" {
				return columns[row].name
			}
			else if (tc.identifier ?? "") == "new" {
				let oldName = columns[row]
				if let newName = step.renames[oldName] {
					return newName.name
				}
				return ""
			}
		}
		return nil
	}
}
