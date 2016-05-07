import Cocoa
import WarpCore

protocol QBESetEditorDelegate: NSObjectProtocol {
	func setEditor(editor: QBESetEditorViewController, didChangeSelection: Set<String>)
}

class QBESetEditorViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
	@IBOutlet private var tableView: NSTableView!
	@IBOutlet private var searchField: NSSearchField!

	var possibleValues: [String] = [] { didSet { self.updateFilter() } }
	private var filteredValues: [String] = []
	var selection: Set<String> = []
	weak var delegate: QBESetEditorDelegate? = nil

	override func viewWillAppear() {
		self.tableView?.reloadData()
	}

	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return filteredValues.count
	}

	@IBAction func selectAllVisibleItems(sender: NSObject) {
		self.selection.unionInPlace(self.filteredValues)
		self.delegate?.setEditor(self, didChangeSelection: selection)
		self.tableView.reloadData()
	}

	@IBAction func deselectAllVisibleItems(sender: NSObject) {
		self.selection.subtractInPlace(self.filteredValues)
		self.delegate?.setEditor(self, didChangeSelection: selection)
		self.tableView.reloadData()
	}

	@IBAction func searchFieldChanged(sender: NSObject) {
		self.updateFilter()
		self.tableView.reloadData()
	}

	private func updateFilter() {
		if let query = self.searchField?.stringValue where !query.isEmpty {
			self.filteredValues = self.possibleValues.filter { v in
				return Comparison(first: Literal(Value(query)), second: Literal(Value(v)), type: .MatchesRegex).apply(Row(), foreign: nil, inputValue: nil) == Value(true)
			}
		}
		else {
			self.filteredValues = self.possibleValues
		}
	}

	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		switch tableColumn?.identifier ?? "" {
		case "selected":
			let select = object?.boolValue ?? false
			if select {
				selection.insert(filteredValues[row])
			}
			else {
				selection.remove(filteredValues[row])
			}
			self.delegate?.setEditor(self, didChangeSelection: selection)

		default:
			break
		}
	}

	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		switch tableColumn?.identifier ?? "" {
			case "selected":
				return NSNumber(bool: selection.contains(filteredValues[row]))

			case "value":
				return filteredValues[row]

			default: return nil
		}
	}
}