import Cocoa
import WarpCore

class QBEKeySelectionViewController: NSViewController, NSTableViewDataSource {
	typealias Callback = (Set<Column>) -> ()

	var columns: OrderedSet<Column> = []
	var keyColumns: Set<Column> = []
	var callback: Callback?

	@IBOutlet private var tableView: NSTableView!
	@IBOutlet private var okButton: NSButton!

	override func viewWillAppear() {
		self.tableView.reloadData()
		self.updateView()
		super.viewWillAppear()
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		switch tableColumn?.identifier ?? "" {
		case "columnName":
			return self.columns[row].name

		case "include":
			return NSNumber(value: keyColumns.contains(self.columns[row]))

		default:
			return nil
		}
	}

	func tableView(_ tableView: NSTableView, setObjectValue object: AnyObject?, for tableColumn: NSTableColumn?, row: Int) {
		if tableColumn?.identifier == "include" {
			let col = self.columns[row]
			if object?.boolValue ?? false {
				self.keyColumns.insert(col)
			}
			else {
				self.keyColumns.remove(col)
			}
		}
		self.updateView()
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		return columns.count
	}

	private func updateView() {
		self.okButton.isEnabled = !self.keyColumns.isEmpty
	}

	@IBAction func confirm(_ sender: NSObject) {
		self.callback?(self.keyColumns)
		self.dismiss(sender)
	}
}
