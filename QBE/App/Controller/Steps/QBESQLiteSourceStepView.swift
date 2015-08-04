import Foundation

internal class QBESQLiteSourceStepView: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	let step: QBESQLiteSourceStep?
	var tableNames: [String]?
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var tableView: NSTableView?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBESQLiteSourceStep {
			self.step = s
			super.init(nibName: "QBESQLiteSourceStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBESQLiteSourceStepView", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		self.step = nil
		super.init(coder: coder)
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		updateView()
	}
	
	private func updateView() {
		// Fetch table names
		if let s = step {
			tableNames = []
			if let db = s.db {
				db.tableNames.maybe {(tns) in tableNames = tns }
			}
			
			tableView?.reloadData()
			// Select current table
			if tableNames != nil {
				let currentTable = s.tableName
				for i in 0..<tableNames!.count {
					if tableNames![i]==currentTable {
						tableView?.selectRowIndexes(NSIndexSet(index: i), byExtendingSelection: false)
						break
					}
				}
			}
		}
	}
	
	internal func tableViewSelectionDidChange(notification: NSNotification) {
		let selection = tableView?.selectedRow ?? -1
		if tableNames != nil && selection >= 0 && selection < tableNames!.count {
			let selectedName = tableNames![selection]
			step?.tableName = selectedName
			delegate?.suggestionsView(self, previewStep: step)
		}
	}
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return tableNames?.count ?? 0
	}
	
	internal func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		return tableNames?[row] ?? ""
	}
}