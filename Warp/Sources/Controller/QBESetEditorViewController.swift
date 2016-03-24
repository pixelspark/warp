import Cocoa

protocol QBESetEditorDelegate: NSObjectProtocol {
	func setEditor(editor: QBESetEditorViewController, didChangeSelection: Set<String>)
}

class QBESetEditorViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
	@IBOutlet private var tableView: NSTableView!

	var possibleValues: [String] = []
	var selection: Set<String> = []
	weak var delegate: QBESetEditorDelegate? = nil

	override func viewWillAppear() {
		self.tableView?.reloadData()
	}

	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return possibleValues.count
	}

	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		switch tableColumn?.identifier ?? "" {
		case "selected":
			let select = object?.boolValue ?? false
			if select {
				print("add=\(possibleValues[row]) \(row)")
				selection.insert(possibleValues[row])
			}
			else {
				print("del=\(possibleValues[row]) \(row)")
				selection.remove(possibleValues[row])
			}
			print("selection=\(selection)")
			self.delegate?.setEditor(self, didChangeSelection: selection)

		default:
			break
		}
	}

	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		switch tableColumn?.identifier ?? "" {
			case "selected":
				return NSNumber(bool: selection.contains(possibleValues[row]))

			case "value":
				return possibleValues[row]

			default: return nil
		}
	}
}