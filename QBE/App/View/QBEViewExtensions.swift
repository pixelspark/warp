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
	
	var center: CGPoint {
		return CGPointMake(self.origin.x + self.size.width/2, self.origin.y + self.size.height/2)
	}
	
	func centeredAt(point: CGPoint) -> CGRect {
		return CGRectMake(point.x - self.size.width/2, point.y - self.size.height/2, self.size.width, self.size.height)
	}
}

internal extension CGPoint {
	func offsetBy(point: CGPoint) -> CGPoint {
		return CGPointMake(self.x + point.x, self.y + point.y)
	}
	
	func distanceTo(point: CGPoint) -> CGFloat {
		return hypot(point.x - self.x, point.y - self.y)
	}
}

@IBDesignable class QBEBorderedView: NSView {
	@IBInspectable var leftBorder: Bool = false
	@IBInspectable var topBorder: Bool = false
	@IBInspectable var rightBorder: Bool = false
	@IBInspectable var bottomBorder: Bool = false
	@IBInspectable var backgroundColor: NSColor = NSColor.controlBackgroundColor()
	@IBInspectable var borderColor: NSColor = NSColor.controlDarkShadowColor()
	
	override func drawRect(dirtyRect: NSRect) {
		backgroundColor.set()
		NSRectFill(self.bounds)
		
		borderColor.setStroke()
		let bounds = self.bounds
		
		if leftBorder {
			NSRectFill(CGRectMake(bounds.origin.x, bounds.origin.y, 1, bounds.size.height))
		}
		
		if rightBorder {
			NSRectFill(CGRectMake(bounds.origin.x + bounds.size.width, bounds.origin.y, 1, bounds.size.height))
		}
		
		if topBorder {
			NSRectFill(CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.width, 1))
		}
		
		if bottomBorder {
			NSRectFill(CGRectMake(bounds.origin.x, bounds.origin.y + bounds.size.height, bounds.size.width, 1))
		}
	}
}

internal extension NSView {
	func addSubview(view: NSView, animated: Bool) {
		if !animated {
			self.addSubview(view)
			return
		}
		
		let duration = 0.35
		view.wantsLayer = true
		self.addSubview(view)
		
		CATransaction.begin()
		CATransaction.setAnimationDuration(duration)
		let ta = CABasicAnimation(keyPath: "transform")
		
		// Scale, but centered in the middle of the view
		var begin = CATransform3DIdentity
		begin = CATransform3DTranslate(begin, view.bounds.size.width/2, view.bounds.size.height/2, 0.0)
		begin = CATransform3DScale(begin, 0.0, 0.0, 0.0)
		begin = CATransform3DTranslate(begin, -view.bounds.size.width/2, -view.bounds.size.height/2, 0.0)
		
		var end = CATransform3DIdentity
		end = CATransform3DTranslate(end, view.bounds.size.width/2, view.bounds.size.height/2, 0.0)
		end = CATransform3DScale(end, 1.0, 1.0, 0.0)
		end = CATransform3DTranslate(end, -view.bounds.size.width/2, -view.bounds.size.height/2, 0.0)
		
		// Fade in
		ta.fromValue = NSValue(CATransform3D: begin)
		ta.toValue = NSValue(CATransform3D: end)
		ta.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
		view.layer?.addAnimation(ta, forKey: "transformAnimation")
		
		let oa = CABasicAnimation(keyPath: "opacity")
		oa.fromValue = 0.0
		oa.toValue = 1.0
		oa.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
		view.layer?.addAnimation(oa, forKey: "opacityAnimation")
		
		CATransaction.commit()
	}
}