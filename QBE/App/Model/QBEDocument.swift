import Cocoa

class QBEDocument: NSDocument, NSSecureCoding {
	private(set) var tablets: [QBETablet] = []
	
	override init () {
	}
	
	required init(coder aDecoder: NSCoder) {
		let raster = QBERaster()
		if let head = (aDecoder.decodeObjectOfClass(QBEStep.self, forKey: "head") as? QBEStep) {
			let legacyTablet = QBETablet(chain: QBEChain(head: head))
			tablets.append(legacyTablet)
		}
		else {
			let classes = Set<NSObject>(arrayLiteral: [QBETablet.self, NSArray.self])
			tablets = aDecoder.decodeObjectOfClasses(classes, forKey: "tablets") as? [QBETablet] ?? []
		}
		
		super.init()
		tablets.each({$0.document = self})
	}
	
	func addTablet(tablet: QBETablet) {
		assert(tablet.document == nil, "tablet must not be associated with another document already")
		tablet.document = self
		tablets.append(tablet)
	}
	
	override func windowControllerDidLoadNib(aController: NSWindowController) {
		super.windowControllerDidLoadNib(aController)
		// Add any code here that needs to be executed once the windowController has loaded the document's window.
	}
	
	override class func autosavesInPlace() -> Bool {
		return true
	}
	
	override func makeWindowControllers() {
		let storyboard = NSStoryboard(name: "Main", bundle: nil)!
		let windowController = storyboard.instantiateControllerWithIdentifier("Document Window Controller") as! NSWindowController
		self.addWindowController(windowController)
	}
	
	func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(tablets, forKey: "tablets")
	}
	
	static func supportsSecureCoding() -> Bool {
		return true
	}
	
	override func dataOfType(typeName: String, error outError: NSErrorPointer) -> NSData? {
		return NSKeyedArchiver.archivedDataWithRootObject(self)
	}
	
	override func writeToURL(url: NSURL, ofType typeName: String, error outError: NSErrorPointer) -> Bool {
		self.tablets.each({$0.willSaveToDocument(url)})
		return super.writeToURL(url, ofType: typeName, error: outError)
	}
	
	override func readFromURL(url: NSURL, ofType typeName: String, error outError: NSErrorPointer) -> Bool {
		let r = super.readFromURL(url, ofType: typeName, error: outError)
		self.tablets.each({$0.didLoadFromDocument(url)})
		return r
	}
	
	override func readFromData(data: NSData, ofType typeName: String, error outError: NSErrorPointer) -> Bool {
		if let x = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? QBEDocument {
			tablets = x.tablets
		}
		return true
	}
}