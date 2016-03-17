import Foundation
import WarpCore

internal class QBEColumnsStepView: QBEConfigurableStepViewControllerFor<QBEColumnsStep>, NSTableViewDataSource, NSTableViewDelegate {
	var columns: [Column] = []
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
		let job = Job(.UserInitiated)
		if let previous = step.previous {
			previous.exampleData(job, maxInputRows: 100, maxOutputRows: 100) { (data) -> () in
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
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return columns.count
	}
	
	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if let identifier = tableColumn?.identifier where identifier == "selected" {
			let select = object?.boolValue ?? false
			let name = columns[row]
			step.columns.remove(name)
			if select {
				step.columns.append(name)
			}
		}
		self.delegate?.configurableView(self, didChangeConfigurationFor: step)
	}
	
	internal func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if let tc = tableColumn {
			if (tc.identifier ?? "") == "column" {
				return columns[row].name
			}
			else {
				return NSNumber(bool: step.columns.indexOf(columns[row]) != nil)
			}
		}
		return nil
	}
}