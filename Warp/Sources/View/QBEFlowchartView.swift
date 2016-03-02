import Cocoa

@objc protocol QBEArrow: NSObjectProtocol {
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
		if let _ = arrowAtPoint(convertPoint(aPoint, fromView: superview)) {
			return self
		}
		return super.hitTest(aPoint)
	}
	
	override var acceptsFirstResponder: Bool { get { return true } }
	
	@IBAction func delete(sender: NSObject) {
		/// FIXME implement
	}
	
	private func arrowAtPoint(point: CGPoint) -> QBEArrow? {
		// Select an arrow?
		for arrow in arrows {
			let path = pathForArrow(arrow)
			let strokedPath = CGPathCreateCopyByStrokingPath(path, nil, 16.0, CGLineCap.Butt, CGLineJoin.Miter, 0.5)
			if CGPathContainsPoint(strokedPath, nil, point, true) {
				return arrow
			}
		}
		
		return nil
	}

	/** Return a bent path for this arrow. The corners of the path will be rounded if `rounded` is set to true (the 
	default). */
	private func pathForArrow(arrow: QBEArrow, rounded: Bool = true) -> CGPathRef {
		let (sourceAnchor, targetAnchor) = QBEAnchor.anchorsForArrow(arrow.sourceFrame, to: arrow.targetFrame)
		let sourcePoint = sourceAnchor.pointInBounds(arrow.sourceFrame)
		let targetPoint = targetAnchor.pointInBounds(arrow.targetFrame, isDestination: true)
		
		// Draw the arrow
		let p = CGPathCreateMutable()
		CGPathMoveToPoint(p, nil, sourcePoint.x, sourcePoint.y)
		var bendpoints = QBEAnchor.bendpointsBetween(arrow.sourceFrame, fromAnchor: sourceAnchor, to: arrow.targetFrame, toAnchor: targetAnchor)

		if rounded {
			bendpoints.append(targetPoint)
			var lastPoint = sourcePoint
			let w: CGFloat = 0.25 // Determines the 'roundedness' of the path
			for (idx, bendpoint) in bendpoints.enumerate() {
				if idx < bendpoints.count - 1 {
					// Choose a point between the last point and the bendpoint to act as starting point for the curve
					let firstBetween = CGPointMake((lastPoint.x * w + bendpoint.x) / (w + 1.0), (lastPoint.y * w + bendpoint.y) / (w + 1.0))

					// Choose a point between the bendpoint and the next point to act as ending point for the curve
					let secondPoint = bendpoints[idx+1]
					let secondBetween = CGPointMake((secondPoint.x * w + bendpoint.x) / (w + 1.0), (secondPoint.y * w + bendpoint.y) / (w + 1.0))

					// Draw a straight line to the curve starting point, the draw the curve to the next 'halfway point'
					CGPathAddLineToPoint(p, nil, firstBetween.x, firstBetween.y)
					CGPathAddQuadCurveToPoint(p, nil, bendpoint.x, bendpoint.y, secondBetween.x, secondBetween.y)
					lastPoint = secondBetween
				}
			}

			// The last line is a straight line again, from the last halfway point
			CGPathAddLineToPoint(p, nil, targetPoint.x, targetPoint.y)
		}
		else {
			for bendpoint in bendpoints {
				CGPathAddLineToPoint(p, nil, bendpoint.x, bendpoint.y)
			}
			CGPathAddLineToPoint(p, nil, targetPoint.x, targetPoint.y)
		}
		return p
	}

	private func drawArrow(arrow: QBEArrow, context: CGContext) {
		let color = (arrow === selectedArrow) ? NSColor(calibratedRed: 0.3, green: 0.3, blue: 0.8, alpha: 1.0) : NSColor.grayColor()
		color.set()

		// Draw arrow line
		CGContextSetStrokeColorWithColor(context, color.CGColor)
		CGContextAddPath(context, pathForArrow(arrow))
		CGContextStrokePath(context)

		// Draw arrow head
		let (sourceAnchor, targetAnchor) = QBEAnchor.anchorsForArrow(arrow.sourceFrame, to: arrow.targetFrame)
		if let firstBendpoint = QBEAnchor.bendpointsBetween(arrow.sourceFrame, fromAnchor: sourceAnchor, to: arrow.targetFrame, toAnchor: targetAnchor).last {
			let targetPoint = targetAnchor.pointInBounds(arrow.targetFrame, isDestination: true)

			CGContextSetFillColorWithColor(context, color.CGColor)
			context.drawArrowheadAt(targetPoint, fromPoint: firstBendpoint, length: 6.0, width: 6.0)
		}
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

extension CGContextRef {
	func drawArrowheadAt(targetPoint: CGPoint, fromPoint: CGPoint, length: CGFloat, width: CGFloat) {
		if targetPoint.distanceTo(fromPoint) > length {
			let shaftDx = (targetPoint.x - fromPoint.x) / targetPoint.distanceTo(fromPoint)
			let shaftDy = (targetPoint.y - fromPoint.y) / targetPoint.distanceTo(fromPoint)
			let headBase = CGPointMake(targetPoint.x - length * shaftDx, targetPoint.y - length * shaftDy)

			let deltaXWing = width * shaftDx
			let deltaYWing = width * shaftDy
			let leftWing = CGPointMake(headBase.x - deltaYWing, headBase.y + deltaXWing)
			let rightWing = CGPointMake(headBase.x + deltaYWing, headBase.y - deltaXWing)

			let head = CGPathCreateMutable()
			CGPathMoveToPoint(head, nil, targetPoint.x, targetPoint.y)
			CGPathAddLineToPoint(head, nil, leftWing.x, leftWing.y)
			CGPathAddLineToPoint(head, nil, rightWing.x, rightWing.y)
			CGPathAddLineToPoint(head, nil, targetPoint.x, targetPoint.y)
			CGContextAddPath(self, head)
			CGContextFillPath(self)
		}
	}
}