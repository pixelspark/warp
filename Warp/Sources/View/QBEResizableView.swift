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
		self.layer?.opaque = true
		self.layer?.drawsAsynchronously = true
		self.layer?.shadowRadius = 4.0
		self.layer?.shadowColor = NSColor.shadowColor().CGColor
		self.layer?.shadowOpacity = 0.3

		resizerView = QBEResizerView(frame: self.bounds)
		resizerView.autoresizingMask = [NSAutoresizingMaskOptions.ViewHeightSizable, NSAutoresizingMaskOptions.ViewWidthSizable]
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
			c.frame = self.bounds.inset(self.resizerView.inset)
			c.autoresizingMask = [NSAutoresizingMaskOptions.ViewHeightSizable, NSAutoresizingMaskOptions.ViewWidthSizable]
			self.addSubview(c, positioned: NSWindowOrderingMode.Below, relativeTo: resizerView)
		}
		else {
			resizerView.contentView = nil
		}
	} }
	
	override func hitTest(aPoint: NSPoint) -> NSView? {
		if let cv = contentView {
			// Dirty hack to find out when one of our subviews is clicked, so we can select ourselves
			let pt = convertPoint(aPoint, fromView: superview)
			if let ht = cv.hitTest(pt) {
				if let ev = self.window?.currentEvent where ev.type == NSEventType.LeftMouseDown {
					self.resizerView.mouseDownInSubiew(ev)
				}

				/* Make the background of an NSCollectionView or QBETabletView always grabbable for dragging. These are
				usually NSClipViews embedded in an NSScrollView. Note however that when field editors are involved, Cocoa
				will create views of _NSKeyboardFocusView around the keyboard focus area, which are also NSClipView. So
				therefore we check for exactly NSClipView, not 'subclass of' NSClipView. */
				if ht is NSCollectionView || ht is QBETabletView || ht.className == NSClipView.className() {
					return self.resizerView
				}
			}
		}

		return super.hitTest(aPoint)
	}
	
	override func updateTrackingAreas() {
		self.trackingAreas.forEach { self.removeTrackingArea($0) }
		addTrackingArea(NSTrackingArea(rect: self.bounds, options: [NSTrackingAreaOptions.MouseEnteredAndExited, NSTrackingAreaOptions.ActiveInKeyWindow], owner: self, userInfo: nil))
	}
	
	override func resetCursorRects() {
		// Find NSCollectionView children and show a grab cursor for them
		findGrabbableViews(self)
	}
	
	private func findGrabbableViews(parent: NSView) {
		let down = (NSEvent.pressedMouseButtons() & (1 << 0)) != 0
		
		parent.subviews.forEach { (subview) -> () in
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
	
	override var acceptsFirstResponder: Bool { get { return true } }
}


internal class QBEResizerView: NSView {
	private struct ResizingSession {
		let downPoint: NSPoint
		var downRect: NSRect
		let downAnchor: QBEAnchor
		var moved = false
	}
	
	let inset: CGFloat = 18.0
	private var resizingSession: ResizingSession? = nil
	private var visibleAnchors: Set<QBEAnchor> = [.South, .North, .East, .West, .SouthEast, .SouthWest, .NorthEast, .NorthWest];
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		self.wantsLayer = true
		self.layer?.drawsAsynchronously = true
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
	
	var isResizing: Bool {
		return resizingSession != nil
	}

	var selected: Bool {
		return (self.superview as! QBEResizableView).selected
	}
	
	internal override func hitTest(aPoint: NSPoint) -> NSView? {
		let pt = convertPoint(aPoint, fromView: superview)

		// If a subview is about to receive a mouse down event, then this tablet should be selected.
		if self.bounds.contains(pt) {
			if !self.selected {
				if let ev = self.window?.currentEvent where ev.type == NSEventType.LeftMouseDown {
					self.mouseDownInSubiew(ev)
				}
			}
		}

		return self.bounds.contains(pt) && !self.bounds.inset(inset).contains(pt) ? self : nil
	}
	
	private func updateSize(theEvent: NSEvent) {
		if let rs = resizingSession {
			let locationInView = superview!.superview!.convertPoint(theEvent.locationInWindow, fromView: nil)
			
			let delta = (Int(locationInView.x - rs.downPoint.x), Int(locationInView.y - rs.downPoint.y))
			let newFrame = rs.downAnchor.offset(rs.downRect, horizontal: CGFloat(delta.0), vertical: CGFloat(delta.1)).rounded
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
		if let p = superview as? QBEResizableView {
			p.delegate?.resizableView(p, changedFrameTo: p.frame)
		}
		
		if let theEvent = event, let rs = resizingSession {
			let locationInSuperView = superview!.superview!.convertPoint(theEvent.locationInWindow, fromView: nil)
			resizingSession = ResizingSession(downPoint: locationInSuperView, downRect: self.superview!.frame, downAnchor: rs.downAnchor, moved: rs.moved)
		}

		self.window?.invalidateCursorRectsForView(self)
	}
	
	override func resetCursorRects() {
		self.addCursorRect(self.bounds, cursor: self.isResizing ? NSCursor.closedHandCursor() : NSCursor.openHandCursor())
		if canResize {
			for anchor in visibleAnchors {
				let frame = anchor.frameInBounds(self.bounds, withInset: inset)
				if let c = anchor.cursor {
					self.addCursorRect(frame, cursor: c)
				}
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
			if dy > self.bounds.height - (insetWithMargin / 4.0 * 3.0) {
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
	
	var canResize: Bool { get {
		// Find scroll view, if it is in zoomed mode we cannot resize
		var sv: NSView? = self
		while let svx = sv where !(svx is QBEWorkspaceView) {
			sv = svx.superview
		}
		
		if let workspace = sv as? QBEWorkspaceView {
			return workspace.magnifiedView == nil
		}
		
		return true
	} }
	
	override func mouseDown(theEvent: NSEvent) {
		if canResize {
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
			self.window?.invalidateCursorRectsForView(self)
		}
	}
	
	override func drawRect(dirtyRect: NSRect) {
		if let context = NSGraphicsContext.currentContext()?.CGContext {
			CGContextClearRect(context, dirtyRect)

			// Draw the bounding box
			let selected = (self.superview as! QBEResizableView).selected
			let borderColor = selected ? NSColor.blueColor().colorWithAlphaComponent(0.5) : NSColor.clearColor()
			CGContextSetLineWidth(context, 2.0)
			CGContextSetStrokeColorWithColor(context, borderColor.CGColor)
			let bounds = self.bounds.inset(inset - 1.0)
			let rr = NSBezierPath(roundedRect: bounds, xRadius: 3.0, yRadius: 3.0)
			rr.stroke()
		}
	}
	
	override func mouseDragged(theEvent: NSEvent) {
		updateSize(theEvent)
	}

	func mouseDownInSubiew(event: NSEvent) {
		if resizingSession == nil || !resizingSession!.moved {
			if let p = superview as? QBEResizableView {
				if !p.selected {
					p.delegate?.resizableViewWasSelected(p)
				}
			}
		}
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
		self.window?.invalidateCursorRectsForView(self)
		setNeedsDisplayInRect(self.bounds)
	}
}