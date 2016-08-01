import Cocoa
import WarpCore

protocol QBEListEditorDelegate: NSObjectProtocol {
	func listEditor(_ editor: QBEListEditorViewController, didChangeSelection: [String])
}

/** Provides an editor view for a list of strings. */
class QBEListEditorViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
	private static let dragType = "nl.pixelspark.Warp.QBEListEditorRow"
	@IBOutlet private var tableView: NSTableView!
	@IBOutlet private var addField: NSTextField!
	@IBOutlet private var addButton: NSButton!
	@IBOutlet private var removeButton: NSButton!

	var selection: [String] = [] { didSet {
		assertMainThread()
		self.update()
	} }
	weak var delegate: QBEListEditorDelegate? = nil

	override func viewWillAppear() {
		tableView.register(forDraggedTypes: [self.dynamicType.dragType])
		self.update()
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		return self.selection.count
	}

	private func update() {
		self.tableView?.reloadData()
	}

	@IBAction func addValue(_ sender: NSObject) {
		if let s = self.addField?.stringValue, !s.isEmpty, !Set(self.selection).contains(s) {
			self.selection.append(s)
		}
		self.update()
		self.delegate?.listEditor(self, didChangeSelection: selection)
		self.view.window?.makeFirstResponder(self.addField)
	}

	@IBAction func removeSelectedValue(_ sender: NSObject) {
		self.selection.removeObjectsAtIndexes(self.tableView.selectedRowIndexes, offset: 0)
		self.update()
		self.delegate?.listEditor(self, didChangeSelection: selection)
	}

	func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
		let item = NSPasteboardItem()
		item.setString(String(row), forType: self.dynamicType.dragType)
		return item
	}

	func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation {
		if dropOperation == .above {
			return .move
		}
		return []
	}

	func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableViewDropOperation) -> Bool {
		var oldIndexes = [Int]()
		info.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) {
			if let str = ($0.0.item as! NSPasteboardItem).string(forType: self.dynamicType.dragType), let index = Int(str) {
				oldIndexes.append(index)
			}
		}

		var droppingItems: [String] = []
		var dropRow = row

		for oldIndex in oldIndexes {
			droppingItems.append(self.selection[oldIndex])
		}

		for oldIndex in oldIndexes.sorted(by: { $0 > $1 }) {
			if oldIndex < dropRow {
				dropRow = dropRow - 1
			}
			self.selection.remove(at: oldIndex)
		}

		self.selection.insert(contentsOf: droppingItems, at: dropRow)
		self.delegate?.listEditor(self, didChangeSelection: selection)
		self.update()
		return true
	}

	func tableView(_ tableView: NSTableView, setObjectValue object: AnyObject?, for tableColumn: NSTableColumn?, row: Int) {
		switch tableColumn?.identifier ?? "" {
		case "value":
			self.selection[row] = (object as? String) ?? ""
			self.delegate?.listEditor(self, didChangeSelection: selection)

		default:
			break
		}
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		switch tableColumn?.identifier ?? "" {
		case "value":
			return selection[row]

		default: return nil
		}
	}

}
