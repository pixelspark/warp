import Foundation
import Cocoa

internal class QBEWindowController: NSWindowController {
	override var document: AnyObject? {
		didSet {
			if let qbeDocumentViewController = window!.contentViewController as? QBEDocumentViewController {
				qbeDocumentViewController.document = document as? QBEDocument
				self.update()
			}
		}
	}

	internal func update() {
		let saved: Bool
		if let doc = self.document as? QBEDocument {
			saved = doc.savedAtLeastOnce || doc.fileURL != nil
		}
		else {
			saved = false
		}
		self.window?.titleVisibility =  saved ? .Visible : .Hidden
	}

	override func windowDidLoad() {
		self.update()
	}
}

class QBEToolbarItem: NSToolbarItem {
	var isValid: Bool {
		if let f = NSApp.targetForAction(#selector(NSObject.validateToolbarItem(_:))) {
			var responder: AnyObject? = f

			while responder != nil {
				if responder!.respondsToSelector(#selector(NSObject.validateToolbarItem(_:))) && responder!.validateToolbarItem(self) {
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
		self.enabled = isValid
		if let b = self.view as? NSButton {
			if !self.enabled {
				b.state = NSOffState
			}
		}
	}
}