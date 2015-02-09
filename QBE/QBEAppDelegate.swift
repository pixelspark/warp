import Cocoa

@NSApplicationMain
class QBEAppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(aNotification: NSNotification) {
		// Insert code here to initialize your application
	}
	
	func applicationWillTerminate(aNotification: NSNotification) {
		// Insert code here to tear down your application
	}
	
	func application(sender: NSApplication, openFile filename: String) -> Bool {
		if let dc = NSDocumentController.sharedDocumentController() as? NSDocumentController {
			if let u = NSURL(fileURLWithPath: filename) {
				let doc = QBEDocument()
				
				/* TODO: check here what kind of file was opened; if it was a .csv, use QBECSVSourceStep, otherwise maybe
				QBESQLiteSourceStep, etc. */
				doc.head = QBECSVSourceStep(url: u)
				dc.addDocument(doc)
				doc.makeWindowControllers()
				doc.showWindows()
				return true
			}
		}
		return false
	}
}

