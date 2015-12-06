import Foundation
import Cocoa

internal class QBEWindowController: NSWindowController {
	@IBOutlet var stopButton: NSButton!
	@IBOutlet var calculateButton: NSButton!
	@IBOutlet var zoomButton: NSSegmentedControl!

	override var document: AnyObject? {
		didSet {
			if let qbeDocumentViewController = window!.contentViewController as? QBEDocumentViewController {
				qbeDocumentViewController.document = document as? QBEDocument
			}
		}
	}
}

class QBEToolbarItem: NSToolbarItem {
	var isValid: Bool {
		if let f = NSApp.targetForAction(Selector("validateToolbarItem:")) {
			var responder: AnyObject? = f

			while responder != nil {
				if responder!.respondsToSelector(Selector("validateToolbarItem:")) && responder!.validateToolbarItem(self) {
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