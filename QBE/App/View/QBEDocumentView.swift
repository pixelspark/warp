import Cocoa

protocol QBEDocumentViewDelegate: NSObjectProtocol {
	func documentView(view: QBEDocumentView, didReceiveFiles: [String])
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
			delegate?.documentView(self, didReceiveFiles: files)
		}
		return true
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

private extension NSView {
	func addSubview(view: NSView, animated: Bool) {
		if !animated {
			self.addSubview(view)
			return
		}
		
		let duration = 0.35
		view.wantsLayer = true
		self.addSubview(view)
		
		CATransaction.begin()
		CATransaction.setAnimationDuration(duration)
		let ta = CABasicAnimation(keyPath: "transform")
		
		// Scale, but centered in the middle of the view
		var begin = CATransform3DIdentity
		begin = CATransform3DTranslate(begin, view.bounds.size.width/2, view.bounds.size.height/2, 0.0)
		begin = CATransform3DScale(begin, 0.0, 0.0, 0.0)
		begin = CATransform3DTranslate(begin, -view.bounds.size.width/2, -view.bounds.size.height/2, 0.0)
		
		var end = CATransform3DIdentity
		end = CATransform3DTranslate(end, view.bounds.size.width/2, view.bounds.size.height/2, 0.0)
		end = CATransform3DScale(end, 1.0, 1.0, 0.0)
		end = CATransform3DTranslate(end, -view.bounds.size.width/2, -view.bounds.size.height/2, 0.0)
		
		// Fade in
		ta.fromValue = NSValue(CATransform3D: begin)
		ta.toValue = NSValue(CATransform3D: end)
		ta.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
		view.layer?.addAnimation(ta, forKey: "transformAnimation")
		
		let oa = CABasicAnimation(keyPath: "opacity")
		oa.fromValue = 0.0
		oa.toValue = 1.0
		oa.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
		view.layer?.addAnimation(oa, forKey: "opacityAnimation")
		
		CATransaction.commit()
	}
}