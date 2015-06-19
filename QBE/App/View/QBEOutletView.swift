import Cocoa

@objc protocol QBEOutletDropTarget: NSObjectProtocol {
	func receiveDropFromOutlet(draggedObject: AnyObject?)
}

/**
QBEOutletDropView provides a 'drop zone' for outlets. Set a delegate to accept objects received from dropped outlet 
connections.
*/
class QBEOutletDropView: NSView {
	private var isDraggingOver: Bool = false
	weak var delegate: QBEOutletDropTarget? = nil
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		registerForDraggedTypes([QBEOutletView.dragType])
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	override func draggingEntered(sender: NSDraggingInfo) -> NSDragOperation {
		isDraggingOver = true
		setNeedsDisplayInRect(self.bounds)
		return delegate != nil ? NSDragOperation.Private : NSDragOperation.None
	}
	
	override func draggingExited(sender: NSDraggingInfo?) {
		isDraggingOver = false
		setNeedsDisplayInRect(self.bounds)
	}
	
	override func draggingEnded(sender: NSDraggingInfo?) {
		isDraggingOver = false
		setNeedsDisplayInRect(self.bounds)
	}
	
	override func performDragOperation(draggingInfo: NSDraggingInfo) -> Bool {
		let pboard = draggingInfo.draggingPasteboard()
		
		if let _ = pboard.dataForType(QBEOutletView.dragType) {
			if let ov = draggingInfo.draggingSource() as? QBEOutletView {
				delegate?.receiveDropFromOutlet(ov.draggedObject)
				return true
			}
		}
		return false
	}
	
	override func hitTest(aPoint: NSPoint) -> NSView? {
		return nil
	}
	
	override func drawRect(dirtyRect: NSRect) {
		if isDraggingOver {
			NSColor.blueColor().colorWithAlphaComponent(0.15).set()
		}
		else {
			NSColor.clearColor().set()
		}
		
		NSRectFill(self.bounds)
	}
	
	override var acceptsFirstResponder: Bool { get { return false } }
}

/** 
QBELaceView draws the actual 'lace' between source and dragging target when dragging an outlet. It is put inside the
QBELaceWindow, which overlays both source and target point. 
*/
private class QBELaceView: NSView {
	weak var source: QBEOutletView? { didSet { setNeedsDisplayInRect(self.bounds) } }
	var targetScreenPoint: CGPoint = CGPointMake(0, 0) { didSet { setNeedsDisplayInRect(self.bounds) } }
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}
	
	private var sourceScreenRect: CGRect? { get {
		if let s = source {
			let frameInWindow = s.convertRect(s.bounds, toView: nil)
			return s.window?.convertRectToScreen(frameInWindow)
		}
		return nil
	} }
	
	private override func hitTest(aPoint: NSPoint) -> NSView? {
		return nil
	}
	
	private override func drawRect(dirtyRect: NSRect) {
		if let context = NSGraphicsContext.currentContext()?.CGContext {
			CGContextSaveGState(context)
			
			if let sourceRect = sourceScreenRect, w = self.window {
				// Translate screen point to point in this view
				let sourcePointWindow = w.convertRectFromScreen(sourceRect).center
				let sourcePointView = self.convertPoint(sourcePointWindow, fromView: nil)
				let targetPointWindow = w.convertRectFromScreen(CGRectMake(targetScreenPoint.x, targetScreenPoint.y, 1, 1)).origin
				let targetPointView = self.convertPoint(targetPointWindow, fromView: nil)
				
				// Draw a line
				CGContextMoveToPoint(context, sourcePointView.x, sourcePointView.y)
				CGContextAddLineToPoint(context, targetPointView.x, targetPointView.y)
				NSColor.blueColor().setStroke()
				CGContextSetLineWidth(context, 3.0)
				CGContextStrokePath(context)
			}
			
			CGContextRestoreGState(context)
		}
	}
}

/** 
QBELaceWindow is an overlay window created before an outlet is being dragged, and is resized to cover both the source
outlet view as well as the (current) target dragging point. The overlay window is used to draw a 'lace' between source 
and dragging target (much like in Interface Builder)
*/
private class QBELaceWindow: NSWindow {
	weak var source: QBEOutletView? { didSet { updateGeometry() } }
	var targetScreenPoint: CGPoint = CGPointMake(0, 0) { didSet { updateGeometry() } }
	private var laceView: QBELaceView
	
	init() {
		laceView = QBELaceView(frame: NSZeroRect)
		super.init(contentRect: NSZeroRect, styleMask: NSBorderlessWindowMask, backing: NSBackingStoreType.Buffered, `defer`: false)
		backgroundColor = NSColor.clearColor()
		releasedWhenClosed = false
		opaque = false
		movableByWindowBackground = false
		excludedFromWindowsMenu = true
		self.hasShadow = true
		self.acceptsMouseMovedEvents = false
		laceView.frame = self.contentLayoutRect
		contentView = laceView
		unregisterDraggedTypes()
		ignoresMouseEvents = true
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}
	
	var sourceScreenFrame: CGRect? { get {
		if let s = source {
			let frameInWindow = s.convertRect(s.bounds, toView: nil)
			return s.window?.convertRectToScreen(frameInWindow)
		}
		return nil
	} }
	
	private func updateGeometry() {
		if let s = source, frameInScreen = sourceScreenFrame {
			let rect = CGRectMake(
				min(frameInScreen.center.x, targetScreenPoint.x),
				min(frameInScreen.center.y, targetScreenPoint.y),
				max(frameInScreen.center.x, targetScreenPoint.x) - min(frameInScreen.center.x, targetScreenPoint.x),
				max(frameInScreen.center.y, targetScreenPoint.y) - min(frameInScreen.center.y, targetScreenPoint.y)
			)
			self.setFrame(CGRectInset(rect, -s.bounds.size.width, -s.bounds.size.height), display: true, animate: false)
		}
		
		laceView.source = source
		laceView.targetScreenPoint = targetScreenPoint
		laceView.setNeedsDisplayInRect(laceView.bounds)
	}
}

@objc protocol QBEOutletViewDelegate: NSObjectProtocol {
	optional func outletViewWillStartDragging(view: QBEOutletView)
	optional func outletViewDidEndDragging(view: QBEOutletView)
}

/** 
QBEOutletView shows an 'outlet' from which an item can be dragged. Views that want to accept outlet drops need to accept
the QBEOutletView.dragType dragging type. Upon receiving a dragged outlet, they should find the dragging source (which 
will be the sending QBEOutletView) and then obtain the draggedObject from that view. */
@IBDesignable class QBEOutletView: NSView, NSDraggingSource {
	static let dragType = "nl.pixelspark.Warp.Outlet"
	
	@IBInspectable var connected: Bool = false { didSet { setNeedsDisplayInRect(self.bounds) } }
	weak var delegate: QBEOutletViewDelegate? = nil
	var draggedObject: AnyObject? = nil
	
	private var dragLineWindow: QBELaceWindow?
	
	override func mouseDown(theEvent: NSEvent) {
		delegate?.outletViewWillStartDragging?(self)
		
		if draggedObject != nil {
			let pboardItem = NSPasteboardItem()
			pboardItem.setData("[dragged outlet]".dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false), forType: QBEOutletView.dragType)
			let dragItem = NSDraggingItem(pasteboardWriter: pboardItem)
			self.beginDraggingSessionWithItems([dragItem] as [NSDraggingItem], event: theEvent, source: self)
		}
	}
	
	override func drawRect(dirtyRect: NSRect) {
		if let context = NSGraphicsContext.currentContext()?.CGContext {
			CGContextSaveGState(context)
			
			// Largest square that fits in this view
			let minDimension = min(self.bounds.size.width, self.bounds.size.height)
			let square = CGRectInset(CGRectMake((self.bounds.size.width - minDimension) / 2, (self.bounds.size.height - minDimension) / 2, minDimension, minDimension), 3.0, 3.0)
			
			if !isinf(square.origin.x) && !isinf(square.origin.y) {
				// Draw the outer ring (always visible, dimmed if no dragging item set)
				let baseColor = NSColor(calibratedRed: 100.0/255.0, green: 97.0/255.0, blue: 97.0/255.0, alpha: draggedObject == nil ? 0.5 : 1.0)
				baseColor.setStroke()
				CGContextSetLineWidth(context, 3.0)
				CGContextStrokeEllipseInRect(context, square)
				
				// Draw the inner circle (if the outlet is connected)
				if connected || dragLineWindow !== nil {
					if dragLineWindow !== nil {
						NSColor.blueColor().setFill()
					}
					else {
						baseColor.setFill()
					}
					let connectedSquare = CGRectInset(square, 3.0, 3.0)
					CGContextFillEllipseInRect(context, connectedSquare)
				}
			}
			
			CGContextRestoreGState(context)
		}
	}
	
	override func updateTrackingAreas() {
		resetCursorRects()
		addCursorRect(self.bounds, cursor: NSCursor.openHandCursor())
		self.window?.invalidateCursorRectsForView(self)
	}
	
	func draggingSession(session: NSDraggingSession, sourceOperationMaskForDraggingContext context: NSDraggingContext) -> NSDragOperation {
		return NSDragOperation.Link
	}
	
	func draggingSession(session: NSDraggingSession, willBeginAtPoint screenPoint: NSPoint) {
		dragLineWindow = QBELaceWindow()
		dragLineWindow!.source = self
		dragLineWindow?.targetScreenPoint = screenPoint
		dragLineWindow!.orderFront(nil)
		setNeedsDisplayInRect(self.bounds)
		NSCursor.closedHandCursor().push()
	}
	
	func draggingSession(session: NSDraggingSession, movedToPoint screenPoint: NSPoint) {
		dragLineWindow?.targetScreenPoint = screenPoint
	}
	
	func draggingSession(session: NSDraggingSession, endedAtPoint screenPoint: NSPoint, operation: NSDragOperation) {
		dragLineWindow?.close()
		dragLineWindow = nil
		setNeedsDisplayInRect(self.bounds)
		NSCursor.closedHandCursor().pop()
		self.delegate?.outletViewDidEndDragging?(self)
	}
}
