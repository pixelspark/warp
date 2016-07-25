import Cocoa
import WarpCore

@IBDesignable class QBEStepsItemView: NSView {
	private var highlighted = false
	@IBOutlet var label: NSTextField?
	@IBOutlet var imageView: NSImageView?
	@IBOutlet var previousImageView: NSImageView?
	@IBOutlet var nextImageView: NSImageView?
	
	var selected: Bool = false { didSet {
		update()
	} }
	
	override var acceptsFirstResponder: Bool { get { return true } }
	
	override init(frame: NSRect) {
		super.init(frame: frame)
		setup()
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setup()
	}
	
	private func setup() {
		self.addToolTip(frame, owner: self, userData: nil)
		self.addTrackingArea(NSTrackingArea(rect: frame, options: [NSTrackingAreaOptions.mouseEnteredAndExited, NSTrackingAreaOptions.activeInActiveApp], owner: self, userInfo: nil))
	}
	
	override func mouseEntered(_ theEvent: NSEvent) {
		highlighted = true
		update()
		setNeedsDisplay(self.bounds)
	}
	
	override func mouseExited(_ theEvent: NSEvent) {
		highlighted = false
		update()
		setNeedsDisplay(self.bounds)
	}
	
	override func view(_ view: NSView, stringForToolTip tag: NSToolTipTag, point: NSPoint, userData data: UnsafeMutablePointer<Void>?) -> String {
		return step?.explain(Language()) ?? ""
	}
	
	var step: QBEStep? { didSet {
		update()
	} }
	
	@IBAction func remove(_ sender: NSObject) {
		if let s = step {
			if let cv = self.superview as? NSCollectionView {
				if let sc = cv.delegate as? QBEStepsViewController {
					sc.delegate?.stepsController(sc, didRemoveStep: s)
				}
			}
		}
	}

	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		return self.validate(menuItem)
	}
	
	func validate(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(QBEStepsItemView.remove(_:)) {
			return true
		}
		else if menuItem.action == #selector(QBEStepsItemView.showSuggestions(_:)) {
			if let s = step, let alternatives = s.alternatives, alternatives.count > 0 {
				return true
			}
		}
		
		return false
	}
	
	@IBAction func showSuggestions(_ sender: NSObject) {
		if let s = step, let alternatives = s.alternatives, alternatives.count > 0 {
			if let cv = self.superview as? NSCollectionView {
				if let sc = cv.delegate as? QBEStepsViewController {
					sc.delegate?.stepsController(sc, showSuggestionsForStep: s, atView: self)
				}
			}
		}
	}
	
	override func hitTest(_ aPoint: NSPoint) -> NSView? {
		if self.selected {
			return super.hitTest(aPoint)
		}
		return self.frame.contains(aPoint) ? self : nil
	}
	
	private func update() {
		label?.attributedStringValue = AttributedString(string: step?.explain(Language()) ?? "??")
		
		if let s = step {
			if let icon = QBEFactory.sharedInstance.iconForStep(s) {
				imageView?.image = NSImage(named: icon)
			}
			
			nextImageView?.isHidden = (s.next == nil) || selected || highlighted
			previousImageView?.isHidden = (s.previous == nil) // || selected || highlighted
		}
	}
	
	override func draw(_ dirtyRect: NSRect) {
		NSColor.clear().set()
		NSRectFill(dirtyRect)

		if self.selected {
			if let sv = self.superview as? QBECollectionView , !sv.active {
				NSColor.secondarySelectedControlColor().set()
			}
			else {
				NSColor.blue().withAlphaComponent(0.2).set()
			}
		}
		else if self.highlighted {
			NSColor.secondarySelectedControlColor().set()
		}
		else {
			NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0).set()
		}

		var corners = Set<QBECorner>()
		if step?.previous == nil {
			corners.insert(.topLeft)
		}

		let rr = NSBezierPath.rounded(rectangle: self.bounds.inset(2.0), withRadius: QBEResizableView.cornerRadius - 1.0, corners: corners)
		rr.fill()
	}
	
	override var allowsVibrancy: Bool { get {
		return true
	} }
}

private extension NSRect {
	var topCenter: NSPoint { return NSMakePoint(NSMidX(self), NSMaxY(self)) }
	var topLeft: NSPoint { return NSMakePoint(NSMinX(self), NSMaxY(self)) }
	var topRight: NSPoint { return NSMakePoint(NSMaxX(self), NSMaxY(self)) }
	var leftCenter: NSPoint { return NSMakePoint(NSMinX(self), NSMidY(self)) }
	var bottomCenter: NSPoint { return NSMakePoint(NSMidX(self), NSMinY(self)) }
	var bottomLeft: NSPoint { return self.origin }
	var bottomRight: NSPoint { return NSMakePoint(NSMaxX(self), NSMinY(self)) }
	var rightCenter: NSPoint { return NSMakePoint(NSMaxX(self), NSMidY(self)) }
}

private enum QBECorner {
	case topLeft
	case topRight
	case bottomLeft
	case bottomRight
}

private extension NSBezierPath {
	class func rounded(rectangle rect: NSRect, withRadius radius: CGFloat, corners: Set<QBECorner>? = nil) -> NSBezierPath {
		let corners = corners ?? Set<QBECorner>([.topLeft, .topRight, .bottomLeft, .bottomRight])
		// Make sure silly values simply lead to un-rounded corners
		if radius <= 0 {
			return NSBezierPath(rect: rect)
		}

		let innerRect = rect.inset(radius)
		let path = NSBezierPath()

		// Bottom left
		if corners.contains(.bottomLeft) {
			path.move(to: NSMakePoint(rect.origin.x, rect.origin.y + radius))
			path.appendArc(withCenter: innerRect.bottomLeft, radius: radius, startAngle: 180.0, endAngle: 270.0)
		}
		else {
			path.move(to: NSMakePoint(rect.origin.x, rect.origin.y))
		}

		path.relativeLine(to: NSMakePoint(NSWidth(innerRect) + (corners.contains(.bottomRight) ? 0.0 : radius) + (corners.contains(.bottomLeft) ? 0.0 : radius), 0.0)) // Bottom edge.

		// Bottom right
		if corners.contains(.bottomRight) {
			path.appendArc(withCenter: innerRect.bottomRight, radius: radius, startAngle: 270.0, endAngle: 360.0)
		}
		path.relativeLine(to: NSMakePoint(0.0, NSHeight(innerRect) + (corners.contains(.topRight) ? 0.0 : radius) + (corners.contains(.bottomRight) ? 0.0 : radius)))	// Right edge.

		// Top right
		if corners.contains(.topRight) {
			path.appendArc(withCenter: innerRect.topRight, radius: radius, startAngle: 0.0, endAngle: 90.0)
		}
		path.relativeLine(to: NSMakePoint(-NSWidth(innerRect) - (corners.contains(.topLeft) ? 0.0 : radius) - (corners.contains(.topRight) ? 0.0 : radius), 0.0)) // Top edge

		// Top left
		if corners.contains(.topLeft) {
			path.appendArc(withCenter: innerRect.topLeft, radius: radius, startAngle: 90.0, endAngle: 180.0)
		}

		path.close()  // Implicitly causes left edge.
			
		return path
	}

}

class QBEStepsItem: NSCollectionViewItem {
	var step: QBEStep? { get {
		return self.representedObject as? QBEStep
	} }
	
	override var representedObject: AnyObject? { didSet {
		if let v = self.view as? QBEStepsItemView {
			v.step = representedObject as? QBEStep
		}
	} }
	
	override var isSelected: Bool { didSet {
		if let v = self.view as? QBEStepsItemView {
			v.selected = isSelected
			v.setNeedsDisplay(v.bounds)
		}
	} }
}
