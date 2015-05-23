import Foundation
import Cocoa

internal class QBEWindowController: NSWindowController {
	override var document: AnyObject? {
		didSet {
			if let qbeDocumentViewController = window!.contentViewController as? QBEDocumentViewController {
				qbeDocumentViewController.document = document as? QBEDocument
			}
		}
	}
}
