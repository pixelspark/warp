import Cocoa

@objc protocol QBEArrow: NSObjectProtocol {
	var sourceFrame: CGRect { get }
	var targetFrame: CGRect { get }
}

protocol QBEFlowchartViewDelegate: NSObjectProtocol {
	func flowchartView(_ view: QBEFlowchartView, didSelectArrow: QBEArrow?)
}

class QBEFlowchartView: NSView {
	weak var delegate: QBEFlowchartViewDelegate? = nil
	
	var selectedArrow: QBEArrow? = nil { didSet {
		setNeedsDisplay(self.bounds)
	} }
	
	var arrows: [QBEArrow] = [] { didSet {
		setNeedsDisplay(self.bounds)
	} }
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	override var allowsVibrancy: Bool { get { return true } }
	
	override func mouseDown(_ theEvent: NSEvent) {
		let location = self.convert(theEvent.locationInWindow, from: nil)
		selectedArrow = arrowAtPoint(location)
		self.delegate?.flowchartView(self, didSelectArrow: selectedArrow)
	}
	
	override func hitTest(_ aPoint: NSPoint) -> NSView? {
		if let _ = arrowAtPoint(convert(aPoint, from: superview)) {
			return self
		}
		return super.hitTest(aPoint)
	}
	
	override var acceptsFirstResponder: Bool { get { return true } }
	
	@IBAction func delete(_ sender: NSObject) {
		/// FIXME implement
	}
	
	private func arrowAtPoint(_ point: CGPoint) -> QBEArrow? {
		// Select an arrow?
		for arrow in arrows {
			let path = pathForArrow(arrow)
			let strokedPath = CGPath(copyByStroking: path, transform: nil, lineWidth: 16.0, lineCap: CGLineCap.butt, lineJoin: CGLineJoin.miter, miterLimit: 0.5)
			if ((strokedPath?.containsPoint(nil, point: point, eoFill: true)) != nil) {
				return arrow
			}
		}
		
		return nil
	}

	/** Return a bent path for this arrow. The corners of the path will be rounded if `rounded` is set to true (the 
	default). */
	private func pathForArrow(_ arrow: QBEArrow, rounded: Bool = true) -> CGPath {
		let (sourceAnchor, targetAnchor) = QBEAnchor.anchorsForArrow(arrow.sourceFrame, to: arrow.targetFrame)
		let sourcePoint = sourceAnchor.pointInBounds(arrow.sourceFrame)
		let targetPoint = targetAnchor.pointInBounds(arrow.targetFrame, isDestination: true)
		
		// Draw the arrow
		let p = CGMutablePath()
		p.moveTo(nil, x: sourcePoint.x, y: sourcePoint.y)
		var bendpoints = QBEAnchor.bendpointsBetween(arrow.sourceFrame, fromAnchor: sourceAnchor, to: arrow.targetFrame, toAnchor: targetAnchor)

		if rounded {
			bendpoints.append(targetPoint)
			var lastPoint = sourcePoint
			let cornerRadius: CGFloat = 10.0
			for (idx, bendpoint) in bendpoints.enumerated() {
				if idx < bendpoints.count - 1 {
					// Choose a point between the last point and the bendpoint to act as starting point for the curve
					let firstDist = lastPoint.distanceTo(bendpoint)
					let firstRadius = min(firstDist, cornerRadius)
					let firstWeight = firstDist < cornerRadius ? 0.5 : firstRadius / firstDist
					let firstBetween = CGPoint(x: lastPoint.x * firstWeight + bendpoint.x * (1.0 - firstWeight), y: lastPoint.y * firstWeight + bendpoint.y * (1.0 - firstWeight))

					// Choose a point between the bendpoint and the next point to act as ending point for the curve
					let secondPoint = bendpoints[idx+1]
					let secondDist = secondPoint.distanceTo(bendpoint)
					let secondRadius = min(cornerRadius, secondDist)
					let secondWeight = secondDist < cornerRadius ? 0.5 : secondRadius / secondDist
					let secondBetween = CGPoint(x: secondPoint.x * secondWeight + bendpoint.x * (1.0 - secondWeight), y: secondPoint.y * secondWeight + bendpoint.y * (1.0 - secondWeight))

					// Draw a straight line to the curve starting point, the draw the curve to the next 'halfway point'
					p.addLineTo(nil, x: firstBetween.x, y: firstBetween.y)
					p.addQuadCurve(nil, cpx: bendpoint.x, cpy: bendpoint.y, endingAtX: secondBetween.x, y: secondBetween.y)
					lastPoint = secondBetween
				}
			}

			// The last line is a straight line again, from the last halfway point
			p.addLineTo(nil, x: targetPoint.x, y: targetPoint.y)
		}
		else {
			for bendpoint in bendpoints {
				p.addLineTo(nil, x: bendpoint.x, y: bendpoint.y)
			}
			p.addLineTo(nil, x: targetPoint.x, y: targetPoint.y)
		}
		return p
	}

	private func drawArrow(_ arrow: QBEArrow, context: CGContext) {
		let color = (arrow === selectedArrow) ? NSColor(calibratedRed: 0.3, green: 0.3, blue: 0.8, alpha: 1.0) : NSColor.gray()
		color.set()

		// Draw arrow line
		context.setStrokeColor(color.cgColor)
		context.addPath(pathForArrow(arrow))
		context.strokePath()

		// Draw arrow head
		let (sourceAnchor, targetAnchor) = QBEAnchor.anchorsForArrow(arrow.sourceFrame, to: arrow.targetFrame)
		if let firstBendpoint = QBEAnchor.bendpointsBetween(arrow.sourceFrame, fromAnchor: sourceAnchor, to: arrow.targetFrame, toAnchor: targetAnchor).last {
			let targetPoint = targetAnchor.pointInBounds(arrow.targetFrame, isDestination: true)

			context.setFillColor(color.cgColor)
			context.drawArrowheadAt(targetPoint, fromPoint: firstBendpoint, length: 6.0, width: 6.0)
		}
	}
	
	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		
		if let context = NSGraphicsContext.current()?.cgContext {
			context.saveGState()
			context.setLineWidth(2.0)
			
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
			
			context.restoreGState()
		}
	}
}

extension CGContext {
	func drawArrowheadAt(_ targetPoint: CGPoint, fromPoint: CGPoint, length: CGFloat, width: CGFloat) {
		if targetPoint.distanceTo(fromPoint) > length {
			let shaftDx = (targetPoint.x - fromPoint.x) / targetPoint.distanceTo(fromPoint)
			let shaftDy = (targetPoint.y - fromPoint.y) / targetPoint.distanceTo(fromPoint)
			let headBase = CGPoint(x: targetPoint.x - length * shaftDx, y: targetPoint.y - length * shaftDy)

			let deltaXWing = width * shaftDx
			let deltaYWing = width * shaftDy
			let leftWing = CGPoint(x: headBase.x - deltaYWing, y: headBase.y + deltaXWing)
			let rightWing = CGPoint(x: headBase.x + deltaYWing, y: headBase.y - deltaXWing)

			let head = CGMutablePath()
			head.moveTo(nil, x: targetPoint.x, y: targetPoint.y)
			head.addLineTo(nil, x: leftWing.x, y: leftWing.y)
			head.addLineTo(nil, x: rightWing.x, y: rightWing.y)
			head.addLineTo(nil, x: targetPoint.x, y: targetPoint.y)
			self.addPath(head)
			self.fillPath()
		}
	}
}
