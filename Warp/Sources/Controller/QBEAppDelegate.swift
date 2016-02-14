import Cocoa
import WarpCore

@NSApplicationMain
class QBEAppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
	internal var locale: Locale!
	internal let jobsManager = QBEJobsManager()
	
	func applicationDidFinishLaunching(aNotification: NSNotification) {
		applyDefaults()
		NSUserNotificationCenter.defaultUserNotificationCenter().delegate = self
		NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("defaultsChanged:"), name: NSUserDefaultsDidChangeNotification, object: nil)
	}
	
	func defaultsChanged(nf: NSNotification) {
		applyDefaults()
	}
	
	private func applyDefaults() {
		let language = NSUserDefaults.standardUserDefaults().stringForKey("locale") ?? Locale.defaultLanguage
		self.locale = Locale(language: language)
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

		// Check to see if the file being opened is a document
		var type: AnyObject? = nil
		do {
			try u.getResourceValue(&type, forKey: NSURLTypeIdentifierKey)
			if let uti = type as? String {
				if NSWorkspace.sharedWorkspace().type(uti, conformsToType: "nl.pixelspark.Warp.Document") {
					dc.openDocumentWithContentsOfURL(u, display: true, completionHandler: { (doc, alreadyOpen, error) -> Void in
					})
					return true
				}
			}
		}
		catch {
			print("ApplicationOpenFile error: could not check whether opened file is a document")
		}

		// This may be a file we can import
		if let importStep = QBEFactory.sharedInstance.stepForReadingFile(u) {
			let doc = QBEDocument()
			doc.addTablet(QBEChainTablet(chain: QBEChain(head: importStep)))
			dc.addDocument(doc)
			doc.makeWindowControllers()
			doc.showWindows()
			return true
		}

		return false
	}
}