import Foundation
import  WarpCore

protocol QBEColumnMappingDelegate: NSObjectProtocol {
	func columnMappingView(_ view: QBEColumnMappingViewController, didChangeMapping: ColumnMapping)
}

class QBEColumnMappingViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	@IBOutlet private var tableView: NSTableView?
	weak var delegate: QBEColumnMappingDelegate? = nil

	var mapping: ColumnMapping = ColumnMapping() {
		didSet {
			self.destinationColumns = Array(mapping.keys)
		}
	}

	var sourceColumns: [Column] = [] {
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

	private var destinationColumns: [Column] = []
	private var sourceColumnsMenu: NSMenu = NSMenu()

	@IBAction func okay(_ sender: NSObject) {
		delegate?.columnMappingView(self, didChangeMapping: self.mapping)
		self.dismiss(sender)
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		return self.destinationColumns.count
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		switch tableColumn?.identifier ?? "" {
		case "source":
			let dest = self.destinationColumns[row]
			if let src = self.mapping[dest] {
				// The '(empty)' menu item is in position 0, then a separator, then the columns (+2 is the first column's index)
				return NSNumber(value: (self.sourceColumns.index(of: src) ?? -2) + 2)
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

	func tableView(_ tableView: NSTableView, setObjectValue object: AnyObject?, for tableColumn: NSTableColumn?, row: Int) {
		if let n = object as? NSNumber, let tc = tableColumn, tc.identifier == "source" {
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
		if tableColumn?.identifier == "source" {
			if let cell = tableColumn?.dataCell as? NSPopUpButtonCell {
				cell.menu = self.sourceColumnsMenu
				return cell
			}
		}
		return nil
	}
}
