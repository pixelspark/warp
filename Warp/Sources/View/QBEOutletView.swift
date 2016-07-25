import Cocoa

@objc protocol QBEOutletDropTarget: NSObjectProtocol {
	func receiveDropFromOutlet(_ draggedObject: AnyObject?)
}

private extension NSPasteboard {
	var pasteURL: URL? { get {
		var pasteboardRef: Pasteboard? = nil
		PasteboardCreate(self.name, &pasteboardRef)
		if let realRef = pasteboardRef {
			PasteboardSynchronize(realRef)
			var pasteURL: CFURL? = nil
			PasteboardCopyPasteLocation(realRef, &pasteURL)

			if let realURL = pasteURL {
				let url = realURL as URL
				return url
			}
		}

		return nil
	} }
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
		register(forDraggedTypes: [QBEOutletView.dragType])
		self.wantsLayer = true
		self.layer!.cornerRadius = QBEResizableView.cornerRadius
		self.layer!.masksToBounds = true
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		isDraggingOver = true
		setNeedsDisplay(self.bounds)
		return delegate != nil ? NSDragOperation.private : NSDragOperation()
	}
	
	override func draggingExited(_ sender: NSDraggingInfo?) {
		isDraggingOver = false
		setNeedsDisplay(self.bounds)
	}
	
	override func draggingEnded(_ sender: NSDraggingInfo?) {
		isDraggingOver = false
		setNeedsDisplay(self.bounds)
	}
	
	override func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
		let pboard = draggingInfo.draggingPasteboard()
		
		if let _ = pboard.data(forType: QBEOutletView.dragType) {
			if let ov = draggingInfo.draggingSource() as? QBEOutletView {
				delegate?.receiveDropFromOutlet(ov.draggedObject)
				return true
			}
		}
		return false
	}
	
	override func hitTest(_ aPoint: NSPoint) -> NSView? {
		return nil
	}
	
	override func draw(_ dirtyRect: NSRect) {
		if isDraggingOver {
			NSColor.blue().withAlphaComponent(0.15).set()
		}
		else {
			NSColor.clear().set()
		}
		
		NSRectFill(dirtyRect)
	}
	
	override var acceptsFirstResponder: Bool { get { return false } }
}

/** 
QBELaceView draws the actual 'lace' between source and dragging target when dragging an outlet. It is put inside the
QBELaceWindow, which overlays both source and target point. 
*/
private class QBELaceView: NSView {
	weak var source: QBEOutletView? { didSet { setNeedsDisplay(self.bounds) } }
	var targetScreenPoint: CGPoint = CGPoint(x: 0, y: 0) { didSet { setNeedsDisplay(self.bounds) } }
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}
	
	private var sourceScreenRect: CGRect? { get {
		if let s = source {
			let frameInWindow = s.convert(s.bounds, to: nil)
			return s.window?.convertToScreen(frameInWindow)
		}
		return nil
	} }
	
	private override func hitTest(_ aPoint: NSPoint) -> NSView? {
		return nil
	}
	
	private override func draw(_ dirtyRect: NSRect) {
		if let context = NSGraphicsContext.current()?.cgContext {
			context.saveGState()
			
			if let sourceRect = sourceScreenRect, let w = self.window {
				// Translate screen point to point in this view
				let sourcePointWindow = w.convertFromScreen(sourceRect).center
				let sourcePointView = self.convert(sourcePointWindow, from: nil)
				let targetPointWindow = w.convertFromScreen(CGRect(x: targetScreenPoint.x, y: targetScreenPoint.y, width: 1, height: 1)).origin
				let targetPointView = self.convert(targetPointWindow, from: nil)
				
				// Draw a line
				context.moveTo(x: sourcePointView.x, y: sourcePointView.y)
				context.addLineTo(x: targetPointView.x, y: targetPointView.y)
				NSColor.blue().setStroke()
				context.setLineWidth(3.0)
				context.strokePath()
			}
			
			context.restoreGState()
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
	var targetScreenPoint: CGPoint = CGPoint(x: 0, y: 0) { didSet { updateGeometry() } }
	private var laceView: QBELaceView
	
	init() {
		laceView = QBELaceView(frame: NSZeroRect)
		super.init(contentRect: NSZeroRect, styleMask: NSBorderlessWindowMask, backing: NSBackingStoreType.buffered, defer: false)
		backgroundColor = NSColor.clear()
		isReleasedWhenClosed = false
		isOpaque = false
		isMovableByWindowBackground = false
		isExcludedFromWindowsMenu = true
		self.hasShadow = true
		self.acceptsMouseMovedEvents = false
		laceView.frame = self.contentLayoutRect
		contentView = laceView
		unregisterDraggedTypes()
		ignoresMouseEvents = true
	}
	
	var sourceScreenFrame: CGRect? { get {
		if let s = source {
			let frameInWindow = s.convert(s.bounds, to: nil)
			return s.window?.convertToScreen(frameInWindow)
		}
		return nil
	} }
	
	private func updateGeometry() {
		if let s = source, let frameInScreen = sourceScreenFrame, targetScreenPoint.x.isFinite && targetScreenPoint.y.isFinite {
			let rect = CGRect(
				x: min(frameInScreen.center.x, targetScreenPoint.x),
				y: min(frameInScreen.center.y, targetScreenPoint.y),
				width: max(frameInScreen.center.x, targetScreenPoint.x) - min(frameInScreen.center.x, targetScreenPoint.x),
				height: max(frameInScreen.center.y, targetScreenPoint.y) - min(frameInScreen.center.y, targetScreenPoint.y)
			)
			self.setFrame(rect.insetBy(dx: -s.bounds.size.width, dy: -s.bounds.size.height), display: true, animate: false)
		}
		
		laceView.source = source
		laceView.targetScreenPoint = targetScreenPoint
		laceView.setNeedsDisplay(laceView.bounds)
	}
}

@objc protocol QBEOutletViewDelegate: NSObjectProtocol {
	func outletViewWillStartDragging(_ view: QBEOutletView)
	func outletViewDidEndDragging(_ view: QBEOutletView)
	@objc optional func outletViewWasClicked(_ view: QBEOutletView)
	func outletView(_ view: QBEOutletView, didDropAtURL: URL)
}

/** 
QBEOutletView shows an 'outlet' from which an item can be dragged. Views that want to accept outlet drops need to accept
the QBEOutletView.dragType dragging type. Upon receiving a dragged outlet, they should find the dragging source (which 
will be the sending QBEOutletView) and then obtain the draggedObject from that view. */
@IBDesignable class QBEOutletView: NSView, NSDraggingSource, NSPasteboardItemDataProvider {
	static let dragType = "nl.pixelspark.Warp.Outlet"

	@IBInspectable var progress: Double = 1.0 { didSet {
		assert(progress >= 0.0 && progress <= 1.0, "progress must be [0,1]")
		setNeedsDisplay(self.bounds)
	} }
	@IBInspectable var enabled: Bool = true { didSet { setNeedsDisplay(self.bounds) } }
	@IBInspectable var connected: Bool = false { didSet { setNeedsDisplay(self.bounds) } }
	weak var delegate: QBEOutletViewDelegate? = nil
	var draggedObject: AnyObject? = nil
	
	private var dragLineWindow: QBELaceWindow?
	
	override func mouseDown(_ theEvent: NSEvent) {
		if enabled {
			delegate?.outletViewWillStartDragging(self)
			
			if draggedObject != nil {
				let pboardItem = NSPasteboardItem()
				pboardItem.setData("[dragged outlet]".data(using: String.Encoding.utf8, allowLossyConversion: false), forType: QBEOutletView.dragType)

				/* When this item is dragged to a finder window, promise to write a CSV file there. Our provideDatasetForType 
				function is called as soon as the system actually wants us to write that file. */
				pboardItem.setDataProvider(self, forTypes: [kPasteboardTypeFileURLPromise])
				pboardItem.setString(kUTTypeCommaSeparatedText as String, forType: kPasteboardTypeFilePromiseContent)

				let dragItem = NSDraggingItem(pasteboardWriter: pboardItem)
				self.beginDraggingSession(with: [dragItem] as [NSDraggingItem], event: theEvent, source: self)
			}
		}
	}

	func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: String) {
		if type == kPasteboardTypeFileURLPromise {
			// pasteURL is the directory to write something to. Now is a good time to pop up an export dialog
			if let pu = pasteboard?.pasteURL {
				self.delegate?.outletView(self, didDropAtURL: pu)
				item.setString(pu.absoluteString, forType: kPasteboardTypeFileURLPromise)
			}
		}
	}
	
	override func draw(_ dirtyRect: NSRect) {
		if let context = NSGraphicsContext.current()?.cgContext {
			context.saveGState()
			
			// Largest square that fits in this view
			let minDimension = min(self.bounds.size.width, self.bounds.size.height)
			let square = CGRect(x: (self.bounds.size.width - minDimension) / 2, y: (self.bounds.size.height - minDimension) / 2, width: minDimension, height: minDimension).insetBy(dx: 3.0, dy: 3.0)
			
			if !square.origin.x.isInfinite && !square.origin.y.isInfinite {
				// Draw the outer ring (always visible, dimmed if no dragging item set)
				let isProgressing = self.progress < 1.0
				let isDragging = (draggedObject != nil)
				let baseColor: NSColor
				if enabled {
					if isDragging {
						baseColor = NSColor(calibratedRed: 100.0/255.0, green: 97.0/255.0, blue: 97.0/255.0, alpha: 1.0)
					}
					else {
						baseColor = NSColor(calibratedRed: 100.0/255.0, green: 97.0/255.0, blue: 97.0/255.0, alpha: 0.5)
					}
				}
				else {
					if isProgressing {
						baseColor = NSColor(calibratedRed: 100.0/255.0, green: 97.0/255.0, blue: 97.0/255.0, alpha: 0.2)
					}
					else {
						baseColor = NSColor(calibratedRed: 100.0/255.0, green: 97.0/255.0, blue: 97.0/255.0, alpha: 0.2)
					}
				}

				baseColor.setStroke()
				context.setLineWidth(3.0)

				let ring = CGMutablePath()
				var t = CGAffineTransform(translationX: square.center.x, y: square.center.y)
				let progress = self.enabled ? 1.0 : self.progress
				let offset: CGFloat = 3.14159 / 2.0
				ring.addArc(&t, x: 0, y: 0, radius: square.size.width / 2, startAngle: offset + CGFloat(2.0 * 3.141459 * (1.0 - progress)), endAngle: offset + CGFloat(2.0 * 3.14159), clockwise: false)
				context.addPath(ring)
				context.strokePath()

				//CGContextStrokeEllipseInRect(context, square)
				
				// Draw the inner circle (if the outlet is connected)
				if connected || dragLineWindow !== nil {
					if dragLineWindow !== nil {
						NSColor.blue().setFill()
					}
					else {
						baseColor.setFill()
					}
					let connectedSquare = square.insetBy(dx: 3.0, dy: 3.0)
					context.fillEllipse(in: connectedSquare)
				}
			}
			
			context.restoreGState()
		}
	}
	
	override func updateTrackingAreas() {
		resetCursorRects()
		addCursorRect(self.bounds, cursor: NSCursor.openHand())
		self.window?.invalidateCursorRects(for: self)
	}
	
	func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
		return NSDragOperation.copy
	}
	
	func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
		dragLineWindow = QBELaceWindow()
		dragLineWindow!.source = self
		dragLineWindow?.targetScreenPoint = screenPoint
		dragLineWindow!.orderFront(nil)
		setNeedsDisplay(self.bounds)
		NSCursor.closedHand().push()
	}
	
	func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
		dragLineWindow?.targetScreenPoint = screenPoint
		dragLineWindow?.update()
	}
	
	func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
		defer {
			dragLineWindow?.close()
			dragLineWindow = nil
			setNeedsDisplay(self.bounds)
			NSCursor.closedHand().pop()
		}

		let screenRect = CGRect(x: screenPoint.x, y: screenPoint.y, width: 0, height: 0)
		if let windowRect = self.window?.convertFromScreen(screenRect) {
			let viewRect = self.convert(windowRect, from: nil)
			if self.bounds.contains(viewRect.origin) {
				self.delegate?.outletViewWasClicked?(self)
				return
			}
		}

		self.delegate?.outletViewDidEndDragging(self)
	}
}
