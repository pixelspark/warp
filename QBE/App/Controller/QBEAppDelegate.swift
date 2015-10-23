import Cocoa
import WarpCore

@NSApplicationMain
class QBEAppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
	var locale: QBELocale!
	
	func applicationDidFinishLaunching(aNotification: NSNotification) {
		applyDefaults()
		NSUserNotificationCenter.defaultUserNotificationCenter().delegate = self
		NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("defaultsChanged:"), name: NSUserDefaultsDidChangeNotification, object: nil)
	}
	
	func defaultsChanged(nf: NSNotification) {
		applyDefaults()
	}
	
	private func applyDefaults() {
		let language = NSUserDefaults.standardUserDefaults().stringForKey("locale") ?? QBELocale.defaultLanguage
		self.locale = QBELocale(language: language)
	}
	
	func applicationWillTerminate(aNotification: NSNotification) {
		// Insert code here to tear down your application
	}
	
	class var sharedInstance: QBEAppDelegate { get {
		return NSApplication.sharedApplication().delegate as! QBEAppDelegate
	} }

	/** This ensures that all our user notifications are shown at all times, even when the application is still frontmost. */
	func userNotificationCenter(center: NSUserNotificationCenter, shouldPresentNotification notification: NSUserNotification) -> Bool {
		return true
	}

	func application(sender: NSApplication, openFile filename: String) -> Bool {
		let dc = NSDocumentController.sharedDocumentController()
		let u = NSURL(fileURLWithPath: filename)
		// What kind of file is this?
		if let importStep = QBEFactory.sharedInstance.stepForReadingFile(u) {
			let doc = QBEDocument()
			doc.addTablet(QBETablet(chain: QBEChain(head: importStep)))
			dc.addDocument(doc)
			doc.makeWindowControllers()
			doc.showWindows()
			return true
		}
		
		return false
	}
}