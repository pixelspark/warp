import Cocoa

protocol QBEDocumentViewDelegate: NSObjectProtocol {
	func documentView(view: QBEDocumentView, didReceiveFiles: [String], atLocation: CGPoint)
	func documentViewDidClickNowhere(view: QBEDocumentView)
}

class QBEDocumentView: NSView {
	weak var delegate: QBEDocumentViewDelegate?
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		
		registerForDraggedTypes([NSFilenamesPboardType])
	}
	
	override func draggingEntered(sender: NSDraggingInfo) -> NSDragOperation {
		return NSDragOperation.Copy
	}
	
	override func draggingUpdated(sender: NSDraggingInfo) -> NSDragOperation {
		return NSDragOperation.Copy
	}
	
	override func prepareForDragOperation(sender: NSDraggingInfo) -> Bool {
		return true
	}
	
	override func performDragOperation(sender: NSDraggingInfo) -> Bool {
		let pboard = sender.draggingPasteboard()
		
		if let files: [String] = pboard.propertyListForType(NSFilenamesPboardType) as? [String] {
			delegate?.documentView(self, didReceiveFiles: files, atLocation: self.convertPoint(sender.draggingLocation(), fromView: nil))
		}
		return true
	}
	
	override func mouseDown(theEvent: NSEvent) {
		delegate?.documentViewDidClickNowhere(self)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	func addTablet(tablet: NSView) {
		self.addSubview(tablet, animated: true)
	}
	
	/** This view needs to be able to be first responder, so that QBEDocumentViewCOntroller can respond to first 
	responder actions even when there are no children selected. **/
	override var acceptsFirstResponder: Bool { get { return true } }
}