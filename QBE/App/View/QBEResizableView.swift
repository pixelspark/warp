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
			let pt = convertPoint(aPoint, fromView: superview)
			let ht = cv.hitTest(pt)
			if let collectionView = ht as? NSCollectionView {
				return self.resizerView
			}
		}
		
		if !selected {
			return self.frame.contains(aPoint) ? self.resizerView : nil
		}
		

		return super.hitTest(aPoint)
	}
	
	override func updateTrackingAreas() {
		self.trackingAreas.each({(t) in self.removeTrackingArea(t as! NSTrackingArea)})
		addTrackingArea(NSTrackingArea(rect: self.bounds, options: NSTrackingAreaOptions.MouseEnteredAndExited | NSTrackingAreaOptions.ActiveInKeyWindow, owner: self, userInfo: nil))
	}
	
	override func mouseEntered(theEvent: NSEvent) {
		self.resizerView.hide = false
	}
	
	override func mouseExited(theEvent: NSEvent) {
		self.resizerView.hide = true
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
	
	override func drawRect(dirtyRect: NSRect) {
		let context = NSGraphicsContext.currentContext()?.CGContext
		CGContextSaveGState(context)
		
		// Draw the bounding box
		let selected = (self.superview as! QBEResizableView).selected
		let borderColor = selected ? NSColor.blueColor() : NSColor.grayColor()
		CGContextSetLineWidth(context, 1.0)
		CGContextSetStrokeColorWithColor(context, borderColor.CGColor)
		CGContextAddRect(context, self.bounds.inset(inset))
		CGContextStrokePath(context)
		
		// Create the gradient to paint the anchor points.
		let activeColors: [CGFloat] = [
			0.4, 0.8, 1.0, 1.0,
			0.0, 0.0, 1.0, 1.0
		];
		
		let inactiveColors: [CGFloat] = [
			0.4, 0.4, 0.4, 0.5,
			0.8, 0.8, 0.8, 0.5
		];
		
		let baseSpace = CGColorSpaceCreateDeviceRGB();
		let gradient = CGGradientCreateWithColorComponents(baseSpace, selected ? activeColors: inactiveColors, nil, 2);
		
		// (4) Set up the stroke for drawing the border of each of the anchor points.
		CGContextSetLineWidth(context, 1);
		CGContextSetShadow(context, CGSizeMake(0.5, 0.5), 1);
		CGContextSetStrokeColorWithColor(context, NSColor.whiteColor().CGColor);
		
		if !hide {
			// Fill each anchor point using the gradient, then stroke the border.
			for anchor in visibleAnchors {
				let currPoint = anchor.frameInBounds(self.bounds, withInset: inset)
				CGContextSaveGState(context)
				CGContextAddEllipseInRect(context, currPoint)
				CGContextClip(context)
				let startPoint = CGPointMake(CGRectGetMidX(currPoint), CGRectGetMinY(currPoint))
				let endPoint = CGPointMake(CGRectGetMidX(currPoint), CGRectGetMaxY(currPoint))
				CGContextDrawLinearGradient(context, gradient, startPoint, endPoint, 0)
				CGContextRestoreGState(context)
				CGContextStrokeEllipseInRect(context, CGRectInset(currPoint, 1, 1))
			}
		}
		CGContextRestoreGState(context)
	}
	
	private func updateSize(theEvent: NSEvent) {
		if let rs = resizingSession {
			let locationInView = superview!.superview!.convertPoint(theEvent.locationInWindow, fromView: nil)
			
			let delta = (Int(locationInView.x - rs.downPoint.x), Int(locationInView.y - rs.downPoint.y))
			let newFrame = rs.downAnchor.offset(rs.downRect, horizontal: CGFloat(delta.0), vertical: CGFloat(delta.1))
			if newFrame.size.width > 50 && newFrame.size.height > 50 {
				self.superview?.frame = newFrame
				self.frame = self.superview!.bounds
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
			let locationInView = self.convertPoint(theEvent.locationInWindow, fromView: nil)
			let locationInSuperView = superview!.superview!.convertPoint(theEvent.locationInWindow, fromView: nil)
			resizingSession = ResizingSession(downPoint: locationInSuperView, downRect: self.superview!.frame, downAnchor: rs.downAnchor)
		}

		
		// Set cursor rects
		self.resetCursorRects()
		for anchor in visibleAnchors {
			let frame = anchor.frameInBounds(self.bounds, withInset: inset)
			if let c = anchor.cursor {
				self.addCursorRect(frame, cursor: c)
			}
		}
		self.window?.invalidateCursorRectsForView(self)
	}
	
	private func anchorForPoint(locationInView: CGPoint) -> QBEAnchor {
		let dx = locationInView.x
		let dy = locationInView.y
		
		let insetWithMargin = inset * 2
		
		let horizontalMargin = self.bounds.width - 2 * insetWithMargin
		let verticalMargin = self.bounds.height - 2 * insetWithMargin
		
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
		
		resizingSession = ResizingSession(downPoint: locationInSuperView, downRect: self.superview!.frame, downAnchor: realAnchor)
		setNeedsDisplayInRect(self.bounds)
		NSCursor.closedHandCursor().push()
	}
	
	override func mouseDragged(theEvent: NSEvent) {
		updateSize(theEvent)
	}
	
	override func mouseUp(theEvent: NSEvent) {
		let locationInView = self.convertPoint(theEvent.locationInWindow, fromView: nil)
		let locationInSuperView = superview!.superview!.convertPoint(theEvent.locationInWindow, fromView: nil)
		
		if theEvent.clickCount > 1 {
			if let p = superview as? QBEResizableView {
				p.delegate?.resizableViewWasDoubleClicked(p)
			}
		}
		else {
			if let r = resizingSession where locationInSuperView != resizingSession?.downPoint {
				updateSize(theEvent)
				
				if let p = superview as? QBEResizableView {
					p.delegate?.resizableView(p, changedFrameTo: p.frame)
				}
			}
			else {
				if let sv = superview, psv = sv.superview {
					psv.addSubview(sv)
				}
				
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