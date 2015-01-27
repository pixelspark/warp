import Foundation
import Cocoa

internal class QBEWindowController: NSWindowController {
	@IBOutlet var progressIndicator: NSProgressIndicator?
	
	private var taskCount: Int = 0 {
		didSet {
			if taskCount > 0 {
				self.progressIndicator?.startAnimation(nil)
			}
			else {
				self.progressIndicator?.stopAnimation(nil)
			}
		}
	}
	
	override var document: AnyObject? {
		didSet {
			let qbeDocumentViewController = window!.contentViewController as QBEViewController
			qbeDocumentViewController.document = document as? QBEDocument
			qbeDocumentViewController.windowController = self
		}
	}
	
	func startTask(name: String) {
		QBEAsyncMain {
			self.taskCount = self.taskCount + 1
		}
	}
	
	func stopTask() {
		self.taskCount = self.taskCount - 1
	}
	
	@IBAction func shareDocument(sender: NSObject) {
		/*if let listDocument = document as? ListDocument {
		let listContents = ListFormatting.stringFromListItems(listDocument.list.items)
		
		let sharingServicePicker = NSSharingServicePicker(items: [listContents])
		
		let preferredEdge =  NSRectEdge(CGRectEdge.MinYEdge.rawValue)
		sharingServicePicker.showRelativeToRect(NSZeroRect, ofView: sender, preferredEdge: preferredEdge)
		}*/
	}
}
