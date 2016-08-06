import Foundation
import WarpCore

internal class QBEColumnsStepView: QBEConfigurableStepViewControllerFor<QBEColumnsStep>, NSTableViewDataSource, NSTableViewDelegate {
	var columns: OrderedSet<Column> = []
	@IBOutlet var tableView: NSTableView?
	
	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBEColumnsStepView", bundle: nil)
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
				data.maybe({$0.columns(job) {(columns) in
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
		if let identifier = tableColumn?.identifier, identifier == "selected" {
			let select = object?.boolValue ?? false
			let name = columns[row]
			step.columns.remove(name)
			if select {
				step.columns.append(name)
			}
		}
		self.delegate?.configurableView(self, didChangeConfigurationFor: step)
	}
	
	internal func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if let tc = tableColumn {
			if (tc.identifier ?? "") == "column" {
				return columns[row].name
			}
			else {
				return NSNumber(value: step.columns.index(of: columns[row]) != nil)
			}
		}
		return nil
	}
}
