import Cocoa

protocol QBEArrow: NSObjectProtocol {
	var sourceFrame: CGRect { get }
	var targetFrame: CGRect { get }
}

protocol QBEFlowchartViewDelegate: NSObjectProtocol {
	func flowchartView(view: QBEFlowchartView, didSelectArrow: QBEArrow?)
}

class QBEFlowchartView: NSView {
	weak var delegate: QBEFlowchartViewDelegate? = nil
	
	var selectedArrow: QBEArrow? = nil { didSet {
		setNeedsDisplayInRect(self.bounds)
	} }
	
	var arrows: [QBEArrow] = [] { didSet {
		setNeedsDisplayInRect(self.bounds)
	} }
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	override var allowsVibrancy: Bool { get { return true } }
	
	override func mouseDown(theEvent: NSEvent) {
		let location = self.convertPoint(theEvent.locationInWindow, fromView: nil)
		selectedArrow = arrowAtPoint(location)
		self.delegate?.flowchartView(self, didSelectArrow: selectedArrow)
	}
	
	override func hitTest(aPoint: NSPoint) -> NSView? {
		if let a = arrowAtPoint(convertPoint(aPoint, fromView: superview)) {
			return self
		}
		return super.hitTest(aPoint)
	}
	
	override var acceptsFirstResponder: Bool { get { return true } }
	
	@IBAction func delete(sender: NSObject) {
		/// FIXME implement
		println("Delete \(selectedArrow)")
	}
	
	private func arrowAtPoint(point: CGPoint) -> QBEArrow? {
		// Select an arrow?
		for arrow in arrows {
			let path = pathForArrow(arrow)
			let strokedPath = CGPathCreateCopyByStrokingPath(path, nil, 16.0, kCGLineCapButt, kCGLineJoinMiter, 0.5)
			if CGPathContainsPoint(strokedPath, nil, point, true) {
				return arrow
			}
		}
		
		return nil
	}
	
	private func pathForArrow(arrow: QBEArrow) -> CGPathRef {
		let (sourceAnchor, targetAnchor) = QBEAnchor.anchorsForArrow(arrow.sourceFrame, to: arrow.targetFrame)
		let sourcePoint = sourceAnchor.pointInBounds(arrow.sourceFrame)
		let targetPoint = targetAnchor.pointInBounds(arrow.targetFrame)
		
		// Draw the arrow
		let p = CGPathCreateMutable()
		CGPathMoveToPoint(p, nil, sourcePoint.x, sourcePoint.y)
		let bendpoints = QBEAnchor.bendpointsBetween(arrow.sourceFrame, fromAnchor: sourceAnchor, to: arrow.targetFrame, toAnchor: targetAnchor)
		for bendpoint in bendpoints {
			CGPathAddLineToPoint(p, nil, bendpoint.x, bendpoint.y)
		}
		CGPathAddLineToPoint(p, nil, targetPoint.x, targetPoint.y)
		return p
	}
	
	private func drawArrow(arrow: QBEArrow, context: CGContext) {
		let color = (arrow === selectedArrow) ? NSColor.blueColor() : NSColor.grayColor()
		color.set()
		
		CGContextSetFillColorWithColor(context, color.CGColor)
		CGContextSetStrokeColorWithColor(context, color.CGColor)
		CGContextAddPath(context, pathForArrow(arrow))
		CGContextStrokePath(context)
	}
	
	override func drawRect(dirtyRect: NSRect) {
		super.drawRect(dirtyRect)
		
		if let context = NSGraphicsContext.currentContext()?.CGContext {
			CGContextSaveGState(context)
			CGContextSetLineWidth(context, 2.0)
			
			// Draw non-selected arrows
			for arrow in arrows {
				if arrow !== selectedArrow {
					drawArrow(arrow, context: context)
				}
			}
			
			// Draw selected arrow over the others
			if let sa = selectedArrow {
				drawArrow(sa, context: context)
			}
			
			CGContextRestoreGState(context)
		}
	}
}