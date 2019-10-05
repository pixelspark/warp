/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import  WarpCore
import Cocoa

protocol QBEColumnMappingDelegate: NSObjectProtocol {
	func columnMappingView(_ view: QBEColumnMappingViewController, didChangeMapping: ColumnMapping)
}

class QBEColumnMappingViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	@IBOutlet private var tableView: NSTableView?
	weak var delegate: QBEColumnMappingDelegate? = nil

	var mapping: ColumnMapping = ColumnMapping() {
		didSet {
			self.destinationColumns = OrderedSet(mapping.keys)
		}
	}

	var sourceColumns: OrderedSet<Column> = [] {
		didSet {
			self.sourceColumnsMenu = NSMenu()

			let noneItem = NSMenuItem(title: NSLocalizedString("(empty)", comment: ""), action: nil, keyEquivalent: "")
			noneItem.tag = -1
			self.sourceColumnsMenu.addItem(noneItem)
			self.sourceColumnsMenu.addItem(NSMenuItem.separator())

			for index in 0..<sourceColumns.count {
				let column = sourceColumns[index]
				let item = NSMenuItem(title: column.name, action: nil, keyEquivalent: "")
				item.tag = index
				self.sourceColumnsMenu.addItem(item)
			}
		}
	}

	private var destinationColumns: OrderedSet<Column> = []
	private var sourceColumnsMenu: NSMenu = NSMenu()

	@IBAction func okay(_ sender: NSObject) {
		delegate?.columnMappingView(self, didChangeMapping: self.mapping)
		self.dismiss(sender)
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		return self.destinationColumns.count
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		switch convertFromNSUserInterfaceItemIdentifier((tableColumn?.identifier)!) {
		case "source":
			let dest = self.destinationColumns[row]
			if let src = self.mapping[dest] {
				// The '(empty)' menu item is in position 0, then a separator, then the columns (+2 is the first column's index)
				return NSNumber(value: (self.sourceColumns.firstIndex(of: src) ?? -2) + 2)
			}
			return nil

		case "icon":
			return NSImage(named: "NextIcon")


		case "destination":
			return self.destinationColumns[row].name
			
		default:
			return nil
		}
	}

	func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
		if let n = object as? NSNumber, let tc = tableColumn, convertFromNSUserInterfaceItemIdentifier(tc.identifier) == "source" {
			let dest = self.destinationColumns[row]

			if let item = self.sourceColumnsMenu.item(at: n.intValue) {
				let tag = item.tag
				if tag >= 0 && tag < self.sourceColumns.count {
					let sourceName = self.sourceColumns[tag]
					self.mapping[dest] = sourceName
				}
				else if tag == -1 {
					self.mapping[dest] = Column("")
				}
			}
		}
	}

	func tableView(_ tableView: NSTableView, dataCellFor tableColumn: NSTableColumn?, row: Int) -> NSCell? {
		if tableColumn == nil {
			return nil
		}

		if convertFromNSUserInterfaceItemIdentifier((tableColumn?.identifier)!) == "source" {
			if let cell = tableColumn?.dataCell(forRow: row) as? NSPopUpButtonCell {
				cell.menu = self.sourceColumnsMenu
				return cell
			}
		}
		return nil
	}
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromNSUserInterfaceItemIdentifier(_ input: NSUserInterfaceItemIdentifier) -> String {
	return input.rawValue
}
