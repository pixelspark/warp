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
	
	/** FIXME:
	override func viewDidAppear() {
		super.viewDidAppear()
		
		QBESettings.sharedInstance.once("welcomeTip") {
			if let items = self.view.window?.toolbar?.items {
				for item in items {
					if item.action() == Selector("addButtonClicked:") {
						if let v = item.view! {
							self.showTip(NSLocalizedString("Welcome to Warp! Click here to start and load some data.",comment: "Welcome tip"), atView: v)
						}
					}
				}
			}
		}
	}**/
}
