import Foundation
import Cocoa

internal extension CGRect {
	func inset(inset: CGFloat) -> CGRect {
		return CGRectMake(
			self.origin.x + inset,
			self.origin.y + inset,
			self.size.width - 2*inset,
			self.size.height - 2*inset
		)
	}
}

class QBEResizableView: NSView {
	private var resizerView: QBEResizerView! = nil
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		self.wantsLayer = true
		self.layer?.shadowRadius = 4.0
		self.layer?.shadowColor = NSColor.shadowColor().CGColor
		self.layer?.shadowOpacity = 0.3;
		
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
			let pt = convertPoint(convertPoint(aPoint, fromView: superview), toView: cv)
			let ht = cv.hitTest(pt)
			if let collectionView = ht as? NSCollectionView {
				return self.resizerView
			}
		}
		return super.hitTest(aPoint)
	}
	
	override func updateTrackingAreas() {
		self.trackingAreas.each({(t) in self.removeTrackingArea(t as! NSTrackingArea)})
		addTrackingArea(NSTrackingArea(rect: self.bounds, options: NSTrackingAreaOptions.MouseEnteredAndExited | NSTrackingAreaOptions.ActiveInKeyWindow, owner: self, userInfo: nil))
	}
	
	override func mouseEntered(theEvent: NSEvent) {
		resizerView.hide = false
	}
	
	override func mouseExited(theEvent: NSEvent) {
		resizerView.hide = true
	}
	
	override func drawRect(dirtyRect: NSRect) {
		NSColor.windowBackgroundColor().set()
		NSRectFill(self.bounds.inset(self.resizerView.inset))
	}
}

private enum QBEResizerAnchor {
	case None
	case North
	case NorthEast
	case East
	case SouthEast
	case South
	case SouthWest
	case West
	case NorthWest
	
	var debugDescription: String { get {
		switch self {
		case .None: return "NONE"
		case .North: return "N"
		case .NorthEast: return "NE"
		case .East: return "E"
		case .SouthEast: return "SE"
		case .South: return "S"
		case .SouthWest: return "SW"
		case .West: return "W"
		case .NorthWest: return "NW"
		}
		} }
	
	func offset(rect: CGRect, horizontal: CGFloat, vertical: CGFloat) -> CGRect {
		switch self {
		case .North: return CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height + vertical)
		case .South: return CGRectMake(rect.origin.x, rect.origin.y + vertical, rect.size.width, rect.size.height - vertical)
		case .East: return CGRectMake(rect.origin.x, rect.origin.y, rect.size.width + horizontal, rect.size.height)
		case .West: return CGRectMake(rect.origin.x + horizontal, rect.origin.y, rect.size.width - horizontal, rect.size.height)
			
		case .NorthEast: return CGRectMake(rect.origin.x, rect.origin.y, rect.size.width + horizontal, rect.size.height + vertical)
		case .SouthEast: return CGRectMake(rect.origin.x, rect.origin.y + vertical, rect.size.width + horizontal, rect.size.height - vertical)
		case .NorthWest: return CGRectMake(rect.origin.x + horizontal, rect.origin.y, rect.size.width - horizontal, rect.size.height + vertical)
		case .SouthWest: return CGRectMake(rect.origin.x + horizontal, rect.origin.y + vertical, rect.size.width - horizontal, rect.size.height - vertical)
			
		case .None: return CGRectMake(rect.origin.x + horizontal, rect.origin.y + vertical, rect.size.width, rect.size.height)
			
		default:
			return rect
		}
	}
	
	func frameInBounds(bounds: CGRect, withInset inset: CGFloat) -> CGRect {
		switch self {
		case .SouthWest: return CGRectMake(inset/2, inset/2, inset, inset)
		case .SouthEast: return CGRectMake(bounds.size.width - 1.5*inset, inset/2, inset, inset)
		case .NorthEast: return CGRectMake(bounds.size.width - 1.5*inset, bounds.size.height - 1.5*inset, inset, inset)
		case .NorthWest: return CGRectMake(inset/2, bounds.size.height - 1.5*inset, inset, inset)
		case .North: return CGRectMake((bounds.size.width - inset)/2, inset/2, inset, inset)
		case .South: return CGRectMake((bounds.size.width - inset)/2, bounds.size.height - 1.5*inset, inset, inset)
		case .West: return CGRectMake(inset/2, (bounds.size.height - inset)/2, inset, inset)
		case .East: return CGRectMake(bounds.size.width - 1.5*inset, (bounds.size.height - inset)/2, inset, inset)
		case .None: return CGRectZero
		}
	}
	
	var cursor: NSCursor? { get {
		switch self {
		case .North: return NSCursor.resizeUpCursor()
		case .South: return NSCursor.resizeDownCursor()
		case .East: return NSCursor.resizeRightCursor()
		case .West: return NSCursor.resizeLeftCursor()
		case .NorthEast: return NSCursor.resizeRightCursor()
		case .SouthEast: return NSCursor.resizeRightCursor()
		case .NorthWest: return NSCursor.resizeLeftCursor()
		case .SouthWest: return NSCursor.resizeLeftCursor()
		default: return NSCursor.dragCopyCursor()
		}
		} }
}


private class QBEResizerView: NSView {
	private struct ResizingSession {
		let downPoint: NSPoint
		let downRect: NSRect
		let downAnchor: QBEResizerAnchor
	}
	
	private let inset: CGFloat = 10.0
	private var resizingSession: ResizingSession? = nil
	private var visibleAnchors: Set<QBEResizerAnchor> = [/*.South, .North, .East, .West,*/ .SouthEast, .SouthWest, .NorthEast, .NorthWest];
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		self.wantsLayer = true
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	var contentView: NSView? { didSet {
		update()
	} }
	
	var hide: Bool = false { didSet {
		if self.resizingSession == nil {
			self.hidden = hide
		}
	} }
	
	var isResizing: Bool { get {
		return resizingSession != nil
	} }
	
	private override func hitTest(aPoint: NSPoint) -> NSView? {
		let pt = convertPoint(aPoint, fromView: superview)
		
		for anchor in visibleAnchors {
			let frame = anchor.frameInBounds(self.bounds, withInset: inset)
			if frame.contains(pt) {
				return self
			}
		}
		return nil
	}
	
	override func drawRect(dirtyRect: NSRect) {
		let context = NSGraphicsContext.currentContext()?.CGContext
		CGContextSaveGState(context)
		
		// Draw the bounding box
		let borderColor = isResizing ? NSColor.blueColor() : NSColor.grayColor()
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
		let gradient = CGGradientCreateWithColorComponents(baseSpace, isResizing ? activeColors: inactiveColors, nil, 2);
		
		// (4) Set up the stroke for drawing the border of each of the anchor points.
		CGContextSetLineWidth(context, 1);
		CGContextSetShadow(context, CGSizeMake(0.5, 0.5), 1);
		CGContextSetStrokeColorWithColor(context, NSColor.whiteColor().CGColor);
		
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
		CGContextRestoreGState(context)
	}
	
	private func updateSize(theEvent: NSEvent) {
		if let rs = resizingSession {
			let locationInView = superview!.superview!.convertPoint(theEvent.locationInWindow, fromView: nil)
			
			let delta = (locationInView.x - rs.downPoint.x, locationInView.y - rs.downPoint.y)
			self.superview?.frame = rs.downAnchor.offset(rs.downRect, horizontal: delta.0, vertical: delta.1)
			self.frame = self.superview!.bounds
		}
		
		update()
	}
	
	private func update() {
		self.contentView?.frame = self.bounds.inset(self.inset)
		
		// Set cursor rects
		self.resetCursorRects()
		for anchor in visibleAnchors {
			let frame = anchor.frameInBounds(self.bounds, withInset: inset * 3)
			if let c = anchor.cursor {
				self.addCursorRect(frame, cursor: c)
			}
		}
	}
	
	private func anchorForPoint(locationInView: CGPoint) -> QBEResizerAnchor {
		let dx = locationInView.x
		let dy = locationInView.y
		
		let insetWithMargin = inset * 3
		
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
	}
	
	override func mouseDragged(theEvent: NSEvent) {
		updateSize(theEvent)
	}
	
	override func mouseUp(theEvent: NSEvent) {
		updateSize(theEvent)
		resizingSession = nil
		setNeedsDisplayInRect(self.bounds)
		self.hidden = hide
	}
}