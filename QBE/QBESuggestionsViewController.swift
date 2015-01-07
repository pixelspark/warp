import Foundation
import Cocoa

protocol QBESuggestionsViewDelegate: NSObjectProtocol {
	func suggestionsView(view: QBESuggestionsViewController, didSelectStep: QBEStep)
}

class QBESuggestionsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	var suggestions: [QBEStep]?
	@IBOutlet var tableView: NSTableView?
	weak var delegate: QBESuggestionsViewDelegate!
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return suggestions?.count ?? 0
	}
	
	override func viewWillAppear() {
		tableView?.selectRowIndexes(NSIndexSet(index: 0), byExtendingSelection: false)
	}
	
	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		return suggestions?[row].explanation
	}
	
	@IBAction func chooseSuggestion(sender: NSObject) {
		if let selectedRow = tableView?.selectedRow {
			if let selectedSuggestion = suggestions?[selectedRow] {
				delegate?.suggestionsView(self, didSelectStep: selectedSuggestion)
			}
		}
		self.dismissController(sender)
	}
}