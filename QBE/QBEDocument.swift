import Cocoa

class QBEDocument: NSDocument, NSCoding {
	var head: QBEStep?
	
	override init () {
		let raster = QBERaster()
	}
	
	var steps: [QBEStep] { get {
		var s: [QBEStep] = []
		var current = head
		
		while current != nil {
			s.append(current!)
			current = current!.previous
		}
		
		return s.reverse()
	} }
	
	required init(coder aDecoder: NSCoder) {
		let raster = QBERaster()
		head = (aDecoder.decodeObjectForKey("head") as? QBEStep) ?? QBERasterStep(raster: raster)
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
		coder.encodeObject(head, forKey: "head")
	}
	
	override func dataOfType(typeName: String, error outError: NSErrorPointer) -> NSData? {
		return NSKeyedArchiver.archivedDataWithRootObject(self)
	}
	
	override func readFromData(data: NSData, ofType typeName: String, error outError: NSErrorPointer) -> Bool {
		if let x = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? QBEDocument {
			head = x.head
		}
		return true
	}
}