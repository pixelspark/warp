import Foundation
import Cocoa
import WarpCore

protocol QBESuggestionsViewDelegate: NSObjectProtocol {
	func suggestionsView(_ view: NSViewController, didSelectStep: QBEStep)
	func suggestionsView(_ view: NSViewController, didSelectAlternativeStep: QBEStep)
	func suggestionsView(_ view: NSViewController, previewStep: QBEStep?)
	var currentStep: QBEStep? { get }
	var locale: Language { get }
	var undo: UndoManager? { get }
}

class QBESuggestionsListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	var suggestions: [QBEStep]?
	@IBOutlet var tableView: NSTableView?
	weak var delegate: QBESuggestionsViewDelegate?
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		return suggestions?.count ?? 0
	}
	
	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		if tableColumn?.identifier == "suggestionLabel" {
			return suggestions?[row].explain(delegate?.locale ?? Language())
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
	
	func tableViewSelectionDidChange(_ notification: Notification) {
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
