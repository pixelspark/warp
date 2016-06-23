import Cocoa
import WarpCore

extension String {
	var localized: String {
		return NSLocalizedString(self, comment: "")
	}
}

@NSApplicationMain
class QBEAppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
	internal var locale: Language!
	internal let jobsManager = QBEJobsManager()
	
	func applicationDidFinishLaunching(_ aNotification: Notification) {
		applyDefaults()
		NSUserNotificationCenter.default().delegate = self
		NotificationCenter.default().addObserver(self, selector: #selector(QBEAppDelegate.defaultsChanged(_:)), name: UserDefaults.didChangeNotification, object: nil)
	}
	
	func defaultsChanged(_ nf: Notification) {
		applyDefaults()
	}
	
	private func applyDefaults() {
		let language = UserDefaults.standard().string(forKey: "locale") ?? Language.defaultLanguage
		self.locale = Language(language: language)
	}
	
	func applicationWillTerminate(_ aNotification: Notification) {
		// Insert code here to tear down your application
	}
	
	class var sharedInstance: QBEAppDelegate { get {
		return NSApplication.shared().delegate as! QBEAppDelegate
	} }

	/** This ensures that all our user notifications are shown at all times, even when the application is still frontmost. */
	func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
		return true
	}

	func application(_ sender: NSApplication, openFile filename: String) -> Bool {
		let dc = NSDocumentController.shared()
		let u = URL(fileURLWithPath: filename)

		// Check to see if the file being opened is a document
		var type: AnyObject? = nil
		do {
			try (u as NSURL).getResourceValue(&type, forKey: URLResourceKey.typeIdentifierKey)
			if let uti = type as? String {
				if NSWorkspace.shared().type(uti, conformsToType: "nl.pixelspark.Warp.Document") {
					dc.openDocument(withContentsOf: u, display: true, completionHandler: { (doc, alreadyOpen, error) -> Void in
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

	@IBAction func showHelp(_ sender: NSObject) {
		if let u = Bundle.main().infoDictionary?["WarpHelpURL"] as? String, let url = URL(string: u) {
			NSWorkspace.shared().open(url)
		}
	}
}
