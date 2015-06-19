import Foundation

internal enum QBEAnchor {
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
	
	var mirror: QBEAnchor {
		get {
			switch self {
			case .North: return .South
			case .NorthEast: return .SouthWest
			case .East: return .West
			case .SouthEast: return .NorthWest
			case .South: return .North
			case .SouthWest: return .NorthEast
			case .West: return .East
			case .NorthWest: return .SouthEast
			case .None: return .None
			}
		}
	}
	
	/** Calculate the location of the bend points of a flowchart arrow between two rectangles, starting and ending at the
		specified anchor. */
	static func bendpointsBetween(from: CGRect, fromAnchor: QBEAnchor, to: CGRect, toAnchor: QBEAnchor) -> [CGPoint] {
		let sourcePoint = fromAnchor.pointInBounds(from, inset: 0.0)
		let targetPoint = toAnchor.pointInBounds(to, inset: 0.0)
		
		let overlaps = CGRectIntersectsRect(from, to)
		
		// Anchors opposite to each other: two bends
		if !overlaps && fromAnchor.mirror == toAnchor {
			if fromAnchor == .North || toAnchor == .North {
				// Meet in the middle vertically
				return [CGPointMake(sourcePoint.x, (sourcePoint.y + targetPoint.y) / 2), CGPointMake(targetPoint.x, (sourcePoint.y + targetPoint.y) / 2)]
			}
			else {
				// Meet in the middle horizontally
				return [CGPointMake((sourcePoint.x + targetPoint.x) / 2, sourcePoint.y), CGPointMake((sourcePoint.x + targetPoint.x) / 2, targetPoint.y)]
			}
		}
		else {
			return [CGPointMake(sourcePoint.x, targetPoint.y)]
		}
	}
	
	/** Determines the anchors that should be used for drawing a flowchart arrow between two rectangles. Returns a tuple
		of the (sourceAnchor, targetAnchor). */
	static func anchorsForArrow(from: CGRect, to: CGRect) -> (QBEAnchor, QBEAnchor) {
		let fromXStart = from.origin.x
		let fromXEnd = from.origin.x + from.size.width
		let toXStart = to.origin.x
		let toXEnd = to.origin.x + to.size.width
		let fromYStart = from.origin.y
		let fromYEnd = from.origin.y + from.size.height
		let toYStart = to.origin.y
		let toYEnd = to.origin.y + to.size.height
		
		// Target is completely to the left of the source (target anchor = EAST)
		if toXEnd < fromXStart {
			// Target is completely under the source (from anchor = NORTH)
			if toYEnd < fromYStart {
				return (.North, .East)
			}
			// Target is completely above the source (from anchor = SOUTH)
			else if toYStart > fromYEnd {
				return (.South, .East)
			}
			// Target overlaps the source vertically (from anchor = WEST in most cases)
			else {
				return (.West, .East)
			}
		}
		// Target is completely to the right of the source (target anchor = WEST)
		else if toXStart > fromXEnd {
			// Target is completely under the source (from anchor = NORTH)
			if toYEnd < fromYStart {
				return (.North, .West)
			}
				// Target is completely above the source (from anchor = SOUTH)
			else if toYStart > fromYEnd {
				return (.South, .West)
			}
				// Target overlaps the source vertically (from anchor = EAST in most cases)
			else {
				return (.East, .West)
			}
		}
		// Target partially or fully overlaps horizontally with the source
		else {
			// Target is completely under the source (from anchor = NORTH)
			if toYEnd < fromYStart {
				return (.North, .South)
			}
			// Target is completely above the source (from anchor = SOUTH)
			else if toYStart > fromYEnd {
				return (.South, .North)
			}
				// Target overlaps the source vertically (from anchor = EAST in most cases)
			else {
				let closestFrom = to.center.x > from.center.x ? QBEAnchor.West : QBEAnchor.East
				let closestTo = to.center.y > from.center.y ? QBEAnchor.South : QBEAnchor.North
				
				if !from.contains(closestFrom.pointInBounds(to)) && !to.contains(closestTo.pointInBounds(from)) {
					return (closestTo, closestFrom)
				}
				return (.None, .None)
			}
		}
	}
	
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
		}
	}
	
	func pointInBounds(bounds: CGRect, inset: CGFloat = 0.0) -> CGPoint {
		return self.frameInBounds(bounds, withInset: inset).center
	}
	
	func frameInBounds(bounds: CGRect, withInset inset: CGFloat) -> CGRect {
		switch self {
		case .SouthWest: return CGRectMake(bounds.origin.x + inset/2, bounds.origin.y + inset/2, inset, inset)
		case .SouthEast: return CGRectMake(bounds.origin.x + bounds.size.width - 1.5*inset, bounds.origin.y + inset/2, inset, inset)
		case .NorthEast: return CGRectMake(bounds.origin.x + bounds.size.width - 1.5*inset, bounds.origin.y + bounds.size.height - 1.5*inset, inset, inset)
		case .NorthWest: return CGRectMake(bounds.origin.x + inset/2, bounds.origin.y + bounds.size.height - 1.5*inset, inset, inset)
		case .North: return CGRectMake(bounds.origin.x + (bounds.size.width - inset)/2, bounds.origin.y + inset/2, inset, inset)
		case .South: return CGRectMake(bounds.origin.x + (bounds.size.width - inset)/2, bounds.origin.y + bounds.size.height - 1.5*inset, inset, inset)
		case .West: return CGRectMake(bounds.origin.x + inset/2, bounds.origin.y + (bounds.size.height - inset)/2, inset, inset)
		case .East: return CGRectMake(bounds.origin.x + bounds.size.width - 1.5*inset, bounds.origin.y + (bounds.size.height - inset)/2, inset, inset)
		case .None: return CGRectZero
		}
	}
	
	var cursor: NSCursor? { get {
		/*switch self {
		case .North: return NSCursor.resizeUpCursor()
		case .South: return NSCursor.resizeDownCursor()
		case .East: return NSCursor.resizeRightCursor()
		case .West: return NSCursor.resizeLeftCursor()
		case .NorthEast: return NSCursor.resizeRightCursor()
		case .SouthEast: return NSCursor.resizeRightCursor()
		case .NorthWest: return NSCursor.resizeLeftCursor()
		case .SouthWest: return NSCursor.resizeLeftCursor()
		default: return NSCursor.dragCopyCursor()
		}*/
		return NSCursor.closedHandCursor()
	} }
}