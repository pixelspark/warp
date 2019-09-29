/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
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
		if self.keyColumns.isEmpty {
			if let locale = QBEAppDelegate.sharedInstance.locale, let likely = locale.likelyPrimaryKey(columns: columns) {
				self.keyColumns = Set<Column>([likely])
			}
		}

		self.tableView.reloadData()
		self.updateView()
		super.viewWillAppear()
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		switch tableColumn?.identifier.rawValue ?? "" {
		case "columnName":
			return self.columns[row].name

		case "include":
			return NSNumber(value: keyColumns.contains(self.columns[row]))

		default:
			return nil
		}
	}

	func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
		if convertFromNSUserInterfaceItemIdentifier((tableColumn?.identifier)!) == "include" {
			let col = self.columns[row]
			if (object as? Bool) ?? false {
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

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromNSUserInterfaceItemIdentifier(_ input: NSUserInterfaceItemIdentifier) -> String {
	return input.rawValue
}
