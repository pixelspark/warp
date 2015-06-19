import Cocoa

@NSApplicationMain
class QBEAppDelegate: NSObject, NSApplicationDelegate {
	var locale: QBELocale!
	
	func applicationDidFinishLaunching(aNotification: NSNotification) {
		applyDefaults()
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
	
	func application(sender: NSApplication, openFile filename: String) -> Bool {
		let dc = NSDocumentController.sharedDocumentController()
		let u = NSURL(fileURLWithPath: filename)
		// What kind of file is this?
		if let fileExtension = u.pathExtension {
			if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension, nil) {
				let utiString = uti.takeUnretainedValue()
				
				if utiString == "public.comma-separated-values-text" {
					// CSV file
					let doc = QBEDocument()
					doc.addTablet(QBETablet(chain: QBEChain(head: QBECSVSourceStep(url: u))))
					dc.addDocument(doc)
					doc.makeWindowControllers()
					doc.showWindows()
					return true
				}
			}
		}
		
		return false
	}
}