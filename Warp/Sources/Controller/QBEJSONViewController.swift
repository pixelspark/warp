import Cocoa
import WarpCore

protocol QBEJSONViewControlllerDelegate: NSObjectProtocol {
	/** Indicates that a value was selected for extraction to a column. The provided expression uses Identity() to refer
	to the source JSON object. */
	func jsonViewController(_ vc: QBEJSONViewController, requestExtraction of: Expression, to column: Column)
}

@objc class QBEJSONViewController: NSViewController, NSOutlineViewDelegate, NSOutlineViewDataSource {
	weak var delegate: QBEJSONViewControlllerDelegate? = nil

	@IBOutlet var outlineView: NSOutlineView!
	@IBOutlet var extractButton: NSButton!
	@IBOutlet var extractColumnNameField: NSTextField!

	private var tree: QBEJSONItem? = nil

	var data: NSObject? {
		didSet {
			if let v = data {
				self.tree = QBEJSONItem(key: "", value: v, parent: nil)
			}
			else {
				self.tree = nil
			}
		}
	}

	@IBAction func extract(_ sender: NSObject) {
		let selectedRow = self.outlineView.selectedRow
		if selectedRow != -1 { // No selection. NSNotFound apparently was too simple...
			if let item = self.outlineView.item(atRow: selectedRow) as? QBEJSONItem {
				let extractor = item.expressionForExtraction(from: Identity())
				let toColumn: Column
				if self.extractColumnNameField.stringValue.isEmpty {
					toColumn = Column(item.key as String)
				}
				else {
					toColumn = Column(self.extractColumnNameField.stringValue)
				}

				self.delegate?.jsonViewController(self, requestExtraction: extractor, to: toColumn)
			}
		}
	}

	private func updateView() {
		let hasSelection = self.outlineView.selectedRow != NSNotFound
		self.extractButton.isEnabled = hasSelection

		let selectedRow = self.outlineView.selectedRow
		if selectedRow != -1 { // No selection. NSNotFound apparently was too simple...
			if let item = self.outlineView.item(atRow: selectedRow) as? QBEJSONItem {
				self.extractColumnNameField.placeholderString = item.key as String
			}
		}
	}

	override func viewWillAppear() {
		self.outlineView?.reloadData()
		self.updateView()
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		self.updateView()
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		let item = (item as? QBEJSONItem) ?? self.tree!
		return item.value is [Any] || item.value is [String: Any]
	}

	/* The value returned by this delegate method is not retained by the outline view. So this means we cannot generate
	anything in here, and can only return objects that are kept alive in the class. */
	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		let item: QBEJSONItem = (item as? QBEJSONItem) ?? self.tree!

		let key: NSString
		let child: NSObject
		if let item = item.value as? NSArray {
			key = "\(index)" as NSString
			child = item.object(at: index) as! NSObject
		}
		else if let item = item.value as? NSDictionary {
			key = item.allKeys[index] as! NSString
			child = item.object(forKey: key) as! NSObject
		}
		else {
			fatalError("invalid object")
		}

		return child
	}

	/* Anything returned from this delegate method needs to be NSObject-subclass */
	@objc func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
		let item: QBEJSONItem = (item as? QBEJSONItem) ?? self.tree!

		if tableColumn?.identifier == "key" {
			return item.key
		}
		else if tableColumn?.identifier == "keyPath" {
			return item.keyPath
		}
		else {
			if let a = item.value as? NSArray {
				return String(format: "[%d items]", a.count)
			}
			else if let a = item.value as? NSDictionary {
				return String(format: "[%d items]", a.count)
			}
			return item.value
		}
	}

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		let item = (item as? QBEJSONItem) ?? self.tree!

		if let list = item.value as? [Any] {
			return list.count
		}
		else if let list = item.value as? [String: Any] {
			return list.count
		}
		return 0
	}
}

@objc private class QBEJSONItem: NSObject {
	var key: NSString
	var value: NSObject
	weak var parent: QBEJSONItem?

	init(key: String, value: NSObject, parent: QBEJSONItem?) {
		self.key = key as NSString
		self.parent = parent

		if let a = value as? NSArray {
			// need to make this an array of json items
			let v = NSMutableArray()
			self.value = v
			super.init()
			for (index, item) in a.enumerated() {
				v.add(QBEJSONItem(key: "\(index)", value: item as! NSObject, parent: self))
			}

		}
		else if let d = value as? NSDictionary {
			let v = NSMutableDictionary()
			self.value = v
			super.init()
			for (key, ov) in d {
				v.setValue(QBEJSONItem(key: key as! String, value: ov as! NSObject, parent: self), forKey: key as! String)
			}
		}
		else {
			self.value = value
			super.init()
		}
	}

	var keyPath: String {
		if let p = parent {
			let parentPath = p.keyPath
			if parentPath.isEmpty {
				return self.key as String
			}
			else {
				return "\(parentPath).\(self.key)"
			}
		}
		return self.key as String
	}

	func expressionForExtraction(from: Expression) -> Expression {
		let input: Expression
		if let p = parent {
			input = p.expressionForExtraction(from: from)
		}
		else {
			input = from
		}

		let keyString = self.key as String
		if !keyString.isEmpty {
			if value is NSArray, let idx = Value.string(keyString).intValue {
				return Call(arguments: [input, Literal(.int(idx))], type: .nth)
			}
			else {
				return Call(arguments: [input, Literal(.string(keyString))], type: .valueForKey)
			}
		}
		return input
	}
}
