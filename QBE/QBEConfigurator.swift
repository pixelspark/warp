import Foundation
import Cocoa

typealias QBEConfigurator = (step: QBEStep?, delegate: QBESuggestionsViewDelegate) -> NSViewController?

let QBEConfigurators: Dictionary<String, QBEConfigurator> = [
	QBESQLiteSourceStep.className(): {QBESQLiteSourceConfigurator(step: $0, delegate: $1)}
]

private class QBESQLiteSourceConfigurator: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	let step: QBESQLiteSourceStep?
	var tableNames: [String]?
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var tableView: NSTableView?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBESQLiteSourceStep {
			self.step = s
			super.init(nibName: "QBESQLiteSourceConfigurator", bundle: nil)
		}
		else {
			super.init(nibName: "QBESQLiteSourceConfigurator", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	private override func viewWillAppear() {
		super.viewWillAppear()
		
		// Fetch table names
		if let s = step {
			tableNames = []
			if let db = s.db {
				tableNames = db.tableNames
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
	
	private func tableViewSelectionDidChange(notification: NSNotification) {
		let selection = tableView?.selectedRow ?? -1
		if tableNames != nil && selection >= 0 && selection < tableNames!.count {
			let selectedName = tableNames![selection]
			step?.tableName = selectedName
			delegate?.suggestionsView(self, previewStep: step)
		}
	}
	
	private func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return tableNames?.count ?? 0
	}
	
	private func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		return tableNames?[row] ?? ""
	}
	
	@IBAction func finish(sender: NSObject) {
		self.delegate?.suggestionsViewDidCancel(self)
	}
}