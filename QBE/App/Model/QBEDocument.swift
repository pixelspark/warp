import Cocoa
import WarpCore

class QBEDocument: NSDocument, NSSecureCoding {
	private(set) var tablets: [QBETablet] = []
	
	override init () {
	}
	
	required init?(coder aDecoder: NSCoder) {
		if let head = aDecoder.decodeObjectOfClass(QBEStep.self, forKey: "head") {
			let legacyTablet = QBETablet(chain: QBEChain(head: head))
			tablets.append(legacyTablet)
		}
		else {
			let classes = Set<NSObject>(arrayLiteral: [QBETablet.self, NSArray.self])
			tablets = aDecoder.decodeObjectOfClasses(classes, forKey: "tablets") as? [QBETablet] ?? []
		}
		
		super.init()
		tablets.forEach { $0.document = self }
	}
	
	func removeTablet(tablet: QBETablet) {
		assert(tablet.document == self, "tablet must belong to this document")
		tablet.document = nil
		tablets.remove(tablet)
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
		let storyboard = NSStoryboard(name: "Main", bundle: nil)

		if !QBESettings.sharedInstance.once("tour", callback: { () -> () in
			let ctr = storyboard.instantiateControllerWithIdentifier("tour") as! NSWindowController
			self.addWindowController(ctr)
		}) {
			let windowController = storyboard.instantiateControllerWithIdentifier("Document Window Controller") as! NSWindowController
			self.addWindowController(windowController)
		}
	}
	
	func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(tablets, forKey: "tablets")
	}
	
	static func supportsSecureCoding() -> Bool {
		return true
	}
	
	override func dataOfType(typeName: String) throws -> NSData {
		return NSKeyedArchiver.archivedDataWithRootObject(self)
	}
	
	override func writeToURL(url: NSURL, ofType typeName: String) throws {
		self.tablets.forEach { $0.willSaveToDocument(url) }
		try super.writeToURL(url, ofType: typeName)
	}
	
	override func readFromURL(url: NSURL, ofType typeName: String) throws {
		try super.readFromURL(url, ofType: typeName)
		self.tablets.forEach { $0.didLoadFromDocument(url) }
	}
	
	override func readFromData(data: NSData, ofType typeName: String) throws {
		if let x = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? QBEDocument {
			tablets = x.tablets
			tablets.forEach { $0.document = self }
		}
	}
}