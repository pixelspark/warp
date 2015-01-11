import Foundation
import Cocoa

class QBESuggestionsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	var suggestions: [QBEStep]?
	@IBOutlet var tableView: NSTableView?
	weak var delegate: QBESuggestionsViewDelegate?
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return suggestions?.count ?? 0
	}
	
	override func viewWillAppear() {
		tableView?.selectRowIndexes(NSIndexSet(index: 0), byExtendingSelection: false)
		delegate?.suggestionsView(self, previewStep: suggestions![0])
	}
	
	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		return suggestions?[row].explanation
	}
	
	func tableViewSelectionDidChange(notification: NSNotification) {
		if let selectedRow = tableView?.selectedRow {
			if selectedRow >= 0 {
				if let selectedSuggestion = suggestions?[selectedRow] {
					delegate?.suggestionsView(self, previewStep: selectedSuggestion)
				}
			}
			else {
				delegate?.suggestionsView(self, previewStep: nil)
			}
		}
	}
	
	@IBAction func cancel(sender: NSObject) {
		delegate?.suggestionsViewDidCancel(self)
		self.dismissController(sender)
	}
	
	@IBAction func chooseSuggestion(sender: NSObject) {
		if let selectedRow = tableView?.selectedRow {
			if selectedRow == -1 {
				delegate?.suggestionsViewDidCancel(self)
			}
			else {
				if let selectedSuggestion = suggestions?[selectedRow] {
					delegate?.suggestionsView(self, didSelectStep: selectedSuggestion)
				}
			}
		}
		self.dismissController(sender)
	}
}