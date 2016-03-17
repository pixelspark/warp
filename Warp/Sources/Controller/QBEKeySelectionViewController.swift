import Cocoa
import WarpCore

protocol QBEKeySelectionViewControllerDelegate: NSObjectProtocol {
	func keySelectionViewController(controller: QBEKeySelectionViewController, didSelectKeyColumns: Set<Column>)
}

class QBEKeySelectionViewController: NSViewController, NSTableViewDataSource {
	var columns: [Column] = []
	var keyColumns: Set<Column> = []

	weak var delegate: QBEKeySelectionViewControllerDelegate? = nil

	@IBOutlet private var tableView: NSTableView!
	@IBOutlet private var okButton: NSButton!

	override func viewWillAppear() {
		self.tableView.reloadData()
		self.updateView()
		super.viewWillAppear()
	}

	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		switch tableColumn?.identifier ?? "" {
		case "columnName":
			return self.columns[row].name

		case "include":
			return NSNumber(bool: keyColumns.contains(self.columns[row]))

		default:
			return nil
		}
	}

	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
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

	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return columns.count
	}

	private func updateView() {
		self.okButton.enabled = !self.keyColumns.isEmpty
	}

	@IBAction func confirm(sender: NSObject) {
		self.delegate?.keySelectionViewController(self, didSelectKeyColumns: self.keyColumns)
		self.dismissController(sender)
	}
}