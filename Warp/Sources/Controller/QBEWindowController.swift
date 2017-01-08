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

internal class QBEWindowController: NSWindowController, QBEDocumentViewControllerDelegate, QBESearchableDelegate {
	private var searchable: QBESearchable? = nil
	@IBOutlet var searchField: NSSearchField! = nil

	override var document: AnyObject? {
		didSet {
			if let qbeDocumentViewController = window!.contentViewController as? QBEDocumentViewController {
				qbeDocumentViewController.document = document as? QBEDocument
				self.update()
			}
		}
	}

	func searchableDidChange(_ searchable: QBESearchable) {
		self.update()
	}

	func documentView(_ view: QBEDocumentViewController, didSelectSearchable searchable: QBESearchable?) {
		self.searchable = searchable
		searchable?.searchDelegate = self
		self.update()
	}

	internal func update() {
		let saved: Bool
		if let doc = self.document as? QBEDocument {
			saved = doc.savedAtLeastOnce || doc.fileURL != nil
		}
		else {
			saved = false
		}
		self.window?.titleVisibility =  saved ? .visible : .hidden
		self.searchField?.isEnabled = self.searchable?.supportsSearch ?? false
		self.searchField?.stringValue = self.searchable?.searchQuery ?? ""
		self.searchField?.nextResponder = self.searchable?.responder
	}

	override func windowDidLoad() {
		if let qbeDocumentViewController = window!.contentViewController as? QBEDocumentViewController {
			qbeDocumentViewController.delegate = self
		}
		self.update()
	}

	@IBAction func fullTextSearch(_ sender: NSSearchField) {
		self.searchable?.searchQuery = sender.stringValue
	}
}

class QBEToolbarItem: NSToolbarItem {
	var isValid: Bool {
		if let f = NSApp.target(forAction: #selector(NSObject.validateToolbarItem(_:))) as? NSResponder {
			var responder: NSResponder? = f

			while responder != nil {
				if responder!.responds(to: #selector(NSObject.validateToolbarItem(_:))) && responder!.validateToolbarItem(self) {
					return true
				}
				else {
					responder = responder?.nextResponder
				}
			}
			return false
		}
		else {
			return false
		}
	}

	override func validate() {
		self.isEnabled = isValid
		if let b = self.view as? NSButton {
			if !self.isEnabled {
				b.state = NSOffState
			}
		}
	}
}
