/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
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
		if convertFromNSUserInterfaceItemIdentifier((tableColumn?.identifier)!) == "suggestionLabel" {
			return suggestions?[row].explain(delegate?.locale ?? Language())
		}
		else if convertFromNSUserInterfaceItemIdentifier((tableColumn?.identifier)!) == "suggestionIcon" {
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

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromNSUserInterfaceItemIdentifier(_ input: NSUserInterfaceItemIdentifier) -> String {
	return input.rawValue
}
