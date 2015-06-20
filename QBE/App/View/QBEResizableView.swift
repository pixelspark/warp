import Foundation
import Cocoa

protocol QBEResizableDelegate: NSObjectProtocol {
	func resizableView(view: QBEResizableView, changedFrameTo: CGRect)
	func resizableViewWasSelected(view: QBEResizableView)
	func resizableViewWasDoubleClicked(view: QBEResizableView)
}

class QBEResizableView: NSView {
	private var resizerView: QBEResizerView! = nil
	weak var delegate: QBEResizableDelegate?
	
	var selected: Bool = false { didSet {
		setNeedsDisplayInRect(self.bounds)
		resizerView.setNeedsDisplayInRect(resizerView.bounds)
	} }
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		self.wantsLayer = true
		self.layer?.shadowRadius = 4.0
		self.layer?.shadowColor = NSColor.shadowColor().CGColor
		self.layer?.shadowOpacity = 0.3
		
		resizerView = QBEResizerView(frame: self.bounds)
		resizerView.hide = true
		addSubview(resizerView)
	}
	
	required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}
	
	var contentView: NSView? { didSet {
		oldValue?.removeFromSuperview()
		
		if let c = contentView {
			c.removeFromSuperview()
			resizerView.contentView = contentView
			self.addSubview(c, positioned: NSWindowOrderingMode.Below, relativeTo: resizerView)
		}
		else {
			resizerView.contentView = nil
		}
	} }
	
	override func hitTest(aPoint: NSPoint) -> NSView? {
		if let cv = contentView {
			// Make the background of an NSCollectionView grabbable for dragging
			let pt = convertPoint(aPoint, fromView: superview)
			let ht = cv.hitTest(pt)
			if let _ = ht as? NSCollectionView {
				return self.resizerView
			}
		}

		return super.hitTest(aPoint)
	}
	
	override func updateTrackingAreas() {
		self.trackingAreas.each({(t) in self.removeTrackingArea(t)})
		addTrackingArea(NSTrackingArea(rect: self.bounds, options: [NSTrackingAreaOptions.MouseEnteredAndExited, NSTrackingAreaOptions.ActiveInKeyWindow], owner: self, userInfo: nil))
	}
	
	override func resetCursorRects() {
		// Find NSCollectionView children and show a grab cursor for them
		findGrabbableViews(self)
	}
	
	private func findGrabbableViews(parent: NSView) {
		let down = (NSEvent.pressedMouseButtons() & (1 << 0)) != 0
		
		parent.subviews.each { (subview) -> () in
			if subview is NSCollectionView {
				self.addCursorRect(subview.convertRect(subview.bounds, toView: self), cursor: down ? NSCursor.closedHandCursor() : NSCursor.openHandCursor())
			}
			findGrabbableViews(subview)
		}
	}
	
	override func mouseEntered(theEvent: NSEvent) {
		self.resizerView.hide = false
	}
	
	override func mouseExited(theEvent: NSEvent) {
		self.resizerView.hide = true
	}
	
	override func mouseDown(theEvent: NSEvent) {
		self.window?.invalidateCursorRectsForView(self)
	}
	
	override func mouseUp(theEvent: NSEvent) {
		self.window?.invalidateCursorRectsForView(self)
	}

	override func drawRect(dirtyRect: NSRect) {
		NSColor.windowBackgroundColor().set()
		NSRectFill(self.bounds.inset(self.resizerView.inset))
	}
	
	override var acceptsFirstResponder: Bool { get { return true } }
}


private class QBEResizerView: NSView {
	private struct ResizingSession {
		let downPoint: NSPoint
		var downRect: NSRect
		let downAnchor: QBEAnchor
		var moved = false
	}
	
	private let inset: CGFloat = 10.0
	private var resizingSession: ResizingSession? = nil
	private var visibleAnchors: Set<QBEAnchor> = [/*.South, .North, .East, .West,*/ .SouthEast, .SouthWest, .NorthEast, .NorthWest];
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		self.wantsLayer = true
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	var contentView: NSView? { didSet {
		update(nil)
	} }
	
	var hide: Bool = false { didSet {
		setNeedsDisplayInRect(self.bounds)
	} }
	
	var isResizing: Bool { get {
		return resizingSession != nil
	} }
	
	private override func hitTest(aPoint: NSPoint) -> NSView? {
		let pt = convertPoint(aPoint, fromView: superview)
		return self.bounds.contains(pt) && !self.bounds.inset(inset).contains(pt) ? self : nil
		
		/*for anchor in visibleAnchors {
			let frame = anchor.frameInBounds(self.bounds, withInset: inset)
			if frame.contains(pt) {
				return self
			}
		}
		return nil*/
	}
	
	private func updateSize(theEvent: NSEvent) {
		if let rs = resizingSession {
			let locationInView = superview!.superview!.convertPoint(theEvent.locationInWindow, fromView: nil)
			
			let delta = (Int(locationInView.x - rs.downPoint.x), Int(locationInView.y - rs.downPoint.y))
			let newFrame = rs.downAnchor.offset(rs.downRect, horizontal: CGFloat(delta.0), vertical: CGFloat(delta.1))
			let minSize = self.contentView!.fittingSize
			if newFrame.size.width >= minSize.width && newFrame.size.height > minSize.height {
				self.superview?.frame = newFrame
				self.frame = self.superview!.bounds
				resizingSession!.moved = true
			}
		}
		
		update(theEvent)
	}
	
	private func update(event: NSEvent?) {
		self.contentView?.frame = self.bounds.inset(self.inset)
		
		if let p = superview as? QBEResizableView {
			p.delegate?.resizableView(p, changedFrameTo: p.frame)
		}
		
		if let theEvent = event, let rs = resizingSession {
			let locationInSuperView = superview!.superview!.convertPoint(theEvent.locationInWindow, fromView: nil)
			resizingSession = ResizingSession(downPoint: locationInSuperView, downRect: self.superview!.frame, downAnchor: rs.downAnchor, moved: rs.moved)
		}

		self.window?.invalidateCursorRectsForView(self)
	}
	
	private override func resetCursorRects() {
		for anchor in visibleAnchors {
			let frame = anchor.frameInBounds(self.bounds, withInset: inset)
			if let c = anchor.cursor {
				self.addCursorRect(frame, cursor: c)
			}
		}
	}
	
	private func anchorForPoint(locationInView: CGPoint) -> QBEAnchor {
		let dx = locationInView.x
		let dy = locationInView.y
		
		let insetWithMargin = inset * 2
		
		// What anchor are we dragging?
		if dx < insetWithMargin {
			if dy > self.bounds.height-insetWithMargin {
				return .NorthWest
			}
			else if dy < insetWithMargin {
				return .SouthWest
			}
			else {
				return .West
			}
		}
		else if dx > self.bounds.width-insetWithMargin {
			if dy > self.bounds.height-insetWithMargin {
				return .NorthEast
			}
			else if dy < insetWithMargin {
				return .SouthEast
			}
			else {
				return .East
			}
		}
		else {
			if dy > self.bounds.height-insetWithMargin {
				return .North
			}
			else if dy < insetWithMargin {
				return .South
			}
			else {
				return .None
			}
		}
	}
	
	override func mouseDown(theEvent: NSEvent) {
		let locationInView = self.convertPoint(theEvent.locationInWindow, fromView: nil)
		let locationInSuperView = superview!.superview!.convertPoint(theEvent.locationInWindow, fromView: nil)
		
		let closestAnchor = anchorForPoint(locationInView)
		let realAnchor = visibleAnchors.contains(closestAnchor) ? closestAnchor : .None
		
		// Order view to front
		if let sv = superview, psv = sv.superview {
			psv.addSubview(sv)
		}
		
		resizingSession = ResizingSession(downPoint: locationInSuperView, downRect: self.superview!.frame, downAnchor: realAnchor, moved: false)
		setNeedsDisplayInRect(self.bounds)
	}
	
	override func mouseDragged(theEvent: NSEvent) {
		updateSize(theEvent)
	}
	
	override func mouseUp(theEvent: NSEvent) {
		if theEvent.clickCount > 1 {
			if let p = superview as? QBEResizableView {
				p.delegate?.resizableViewWasDoubleClicked(p)
			}
		}
		else {
			if let r = resizingSession {
				if r.moved {
					if let p = superview as? QBEResizableView {
						p.delegate?.resizableView(p, changedFrameTo: p.frame)
					}
				}
			}
				
			if resizingSession == nil || !resizingSession!.moved {
				if let p = superview as? QBEResizableView {
					if !p.selected {
						p.delegate?.resizableViewWasSelected(p)
					}
				}
			}
		}
		
		resizingSession = nil
		setNeedsDisplayInRect(self.bounds)
	}
}