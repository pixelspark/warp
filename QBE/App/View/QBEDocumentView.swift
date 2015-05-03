import Cocoa

@objc protocol QBEDocumentViewDelegate: NSObjectProtocol {
	func documentView(view: QBEDocumentView, didReceiveFiles: [String], atLocation: CGPoint)
	func documentView(view: QBEDocumentView, didSelectTablet: QBEChainViewController?)
}

internal class QBEDocumentView: NSView, QBEResizableDelegate {
	@IBOutlet weak var delegate: QBEDocumentViewDelegate?
	
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
	
	func selectTablet(tablet: QBETablet?) {
		if let t = tablet {
			for sv in subviews {
				if let tv = sv as? QBEResizableTabletView {
					if tv.tabletController.chain?.tablet == t {
						selectView(tv)
						return
					}
				}
			}
		}
		else {
			selectView(nil)
		}
	}
	
	private func selectView(view: QBEResizableTabletView?) {
		// Deselect other views
		for sv in subviews {
			if let tv = sv as? QBEResizableTabletView {
				tv.selected = (tv == view)
				if tv == view {
					delegate?.documentView(self, didSelectTablet: tv.tabletController)
				}
			}
		}
		
		if view == nil {
			delegate?.documentView(self, didSelectTablet: nil)
		}
	}
	
	func resizableViewWasSelected(view: QBEResizableView) {
		selectView(view as? QBEResizableTabletView)
	}
	
	func resizableView(view: QBEResizableView, changedFrameTo frame: CGRect) {
		if let tv = view as? QBEResizableTabletView {
			if let tablet = tv.tabletController.chain?.tablet {
				tablet.frame = frame
				tabletsChanged()
				if tv.selected {
					tv.scrollRectToVisible(tv.bounds)
				}
			}
		}
	}
	
	
	var boundsOfAllTablets: CGRect? { get {
		// Find out the bounds of all tablets combined
		var allBounds: CGRect? = nil
		for vw in subviews {
			allBounds = allBounds == nil ? vw.frame : CGRectUnion(allBounds!, vw.frame)
		}
		return allBounds
	} }
	
	// Call whenever tablets are added/removed or resized
	private func tabletsChanged() {
		if let ab = boundsOfAllTablets {
			// Determine new size of the document
			var newBounds = ab.rectByInsetting(dx: -300, dy: -300)
			let offset = CGPointMake(-newBounds.origin.x, -newBounds.origin.y)
			newBounds.offset(dx: offset.x, dy: offset.y)
			
			newBounds.size.width = max(self.superview!.bounds.size.width, newBounds.size.width)
			newBounds.size.height = max(self.superview!.bounds.size.height, newBounds.size.height)
			
			// Move all tablets
			for vw in subviews {
				if let tv = vw as? QBEResizableTabletView {
					if let tablet = tv.tabletController.chain?.tablet {
						if let tabletFrame = tablet.frame {
							tablet.frame = tabletFrame.rectByOffsetting(dx: offset.x, dy: offset.y)
							tv.frame = tablet.frame!
						}
					}
				}
			}
			
			// Set new document bounds
			let newBoundsVisible = self.visibleRect.rectByOffsetting(dx: -offset.x, dy: -offset.y)
			self.frame = CGRectMake(0, 0, newBounds.size.width, newBounds.size.height)
			//self.scrollRectToVisible(newBoundsVisible)
		}
	}
	
	private var selectedView: QBEResizableTabletView? { get {
		for vw in subviews {
			if let tv = vw as? QBEResizableTabletView {
				if tv.selected {
					return tv
				}
			}
		}
		return nil
	}}
	
	var selectedTablet: QBETablet? { get {
		return selectedView?.tabletController.chain?.tablet
	} }
	
	override func mouseDown(theEvent: NSEvent) {
		selectView(nil)
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	func removeTablet(tablet: QBETablet) {
		for subview in subviews {
			if let rv = subview as? QBEResizableTabletView {
				if let ct = rv.tabletController.chain?.tablet where ct == tablet {
					subview.removeFromSuperview()
				}
			}
		}
		tabletsChanged()
	}
	
	func addTablet(tabletController: QBEChainViewController) {
		if let tablet = tabletController.chain?.tablet {
			let resizer = QBEResizableTabletView(frame: tablet.frame!, controller: tabletController)
			resizer.contentView = tabletController.view
			resizer.delegate = self
		
			self.addSubview(resizer, animated: true)
			tabletsChanged()
		}
	}
	
	/** This view needs to be able to be first responder, so that QBEDocumentViewCOntroller can respond to first 
	responder actions even when there are no children selected. **/
	override var acceptsFirstResponder: Bool { get { return true } }
}

private class QBEResizableTabletView: QBEResizableView {
	let tabletController: QBEChainViewController
	
	init(frame: CGRect, controller: QBEChainViewController) {
		tabletController = controller
		super.init(frame: frame)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}