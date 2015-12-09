import Foundation
import Cocoa
import WarpCore

class QBESuggestionsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	var suggestions: [QBEStep]?
	@IBOutlet var tableView: NSTableView?
	weak var delegate: QBESuggestionsViewDelegate?
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return suggestions?.count ?? 0
	}
	
	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if tableColumn?.identifier == "suggestionLabel" {
			return suggestions?[row].explain(delegate?.locale ?? Locale())
		}
		else if tableColumn?.identifier == "suggestionIcon" {
			if let suggestedStep = suggestions?[row] {
				if let icon = QBEFactory.sharedInstance.iconForStep(suggestedStep) {
					return NSImage(named: icon)
				}
			}
		}
		
		return nil
	}
	
	func tableViewSelectionDidChange(notification: NSNotification) {
		if let selectedRow = tableView?.selectedRow {
			if selectedRow >= 0 {
				if let selectedSuggestion = suggestions?[selectedRow] {
					delegate?.suggestionsView(self, didSelectAlternativeStep: selectedSuggestion)
				}
			}
			else {
				delegate?.suggestionsView(self, previewStep: nil)
			}
		}
	}
}