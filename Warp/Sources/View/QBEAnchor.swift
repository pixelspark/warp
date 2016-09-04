/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation

internal enum QBEAnchor {
	case none
	case north
	case northEast
	case east
	case southEast
	case south
	case southWest
	case west
	case northWest
	
	var debugDescription: String { get {
		switch self {
		case .none: return "NONE"
		case .north: return "N"
		case .northEast: return "NE"
		case .east: return "E"
		case .southEast: return "SE"
		case .south: return "S"
		case .southWest: return "SW"
		case .west: return "W"
		case .northWest: return "NW"
		}
	} }
	
	var mirror: QBEAnchor {
		get {
			switch self {
			case .north: return .south
			case .northEast: return .southWest
			case .east: return .west
			case .southEast: return .northWest
			case .south: return .north
			case .southWest: return .northEast
			case .west: return .east
			case .northWest: return .southEast
			case .none: return .none
			}
		}
	}
	
	/** Calculate the location of the bend points of a flowchart arrow between two rectangles, starting and ending at the
		specified anchor. */
	static func bendpointsBetween(_ from: CGRect, fromAnchor: QBEAnchor, to: CGRect, toAnchor: QBEAnchor) -> [CGPoint] {
		let sourcePoint = fromAnchor.pointInBounds(from, isDestination: false)
		let targetPoint = toAnchor.pointInBounds(to, isDestination: true)
		
		let overlaps = from.intersects(to)
		
		// Anchors opposite to each other: two bends
		if !overlaps && fromAnchor.mirror == toAnchor {
			if fromAnchor == .north || toAnchor == .north {
				// Meet in the middle vertically
				return [CGPoint(x: sourcePoint.x, y: (sourcePoint.y + targetPoint.y) / 2), CGPoint(x: targetPoint.x, y: (sourcePoint.y + targetPoint.y) / 2)]
			}
			else {
				// Meet in the middle horizontally
				return [CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: sourcePoint.y), CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: targetPoint.y)]
			}
		}
		else {
			return [CGPoint(x: sourcePoint.x, y: targetPoint.y)]
		}
	}
	
	/** Determines the anchors that should be used for drawing a flowchart arrow between two rectangles. Returns a tuple
		of the (sourceAnchor, targetAnchor). */
	static func anchorsForArrow(_ from: CGRect, to: CGRect) -> (QBEAnchor, QBEAnchor) {
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
				return (.north, .east)
			}
			// Target is completely above the source (from anchor = SOUTH)
			else if toYStart > fromYEnd {
				return (.south, .east)
			}
			// Target overlaps the source vertically (from anchor = WEST in most cases)
			else {
				return (.west, .east)
			}
		}
		// Target is completely to the right of the source (target anchor = WEST)
		else if toXStart > fromXEnd {
			// Target is completely under the source (from anchor = NORTH)
			if toYEnd < fromYStart {
				return (.north, .west)
			}
				// Target is completely above the source (from anchor = SOUTH)
			else if toYStart > fromYEnd {
				return (.south, .west)
			}
				// Target overlaps the source vertically (from anchor = EAST in most cases)
			else {
				return (.east, .west)
			}
		}
		// Target partially or fully overlaps horizontally with the source
		else {
			// Target is completely under the source (from anchor = NORTH)
			if toYEnd < fromYStart {
				return (.north, .south)
			}
			// Target is completely above the source (from anchor = SOUTH)
			else if toYStart > fromYEnd {
				return (.south, .north)
			}
				// Target overlaps the source vertically (from anchor = EAST in most cases)
			else {
				let closestFrom = to.center.x > from.center.x ? QBEAnchor.west : QBEAnchor.east
				let closestTo = to.center.y > from.center.y ? QBEAnchor.south : QBEAnchor.north
				
				if !from.contains(closestFrom.pointInBounds(to)) && !to.contains(closestTo.pointInBounds(from)) {
					return (closestTo, closestFrom)
				}
				return (.none, .none)
			}
		}
	}
	
	func offset(_ rect: CGRect, horizontal: CGFloat, vertical: CGFloat) -> CGRect {
		switch self {
		case .north: return CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height + vertical)
		case .south: return CGRect(x: rect.origin.x, y: rect.origin.y + vertical, width: rect.size.width, height: rect.size.height - vertical)
		case .east: return CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.size.width + horizontal, height: rect.size.height)
		case .west: return CGRect(x: rect.origin.x + horizontal, y: rect.origin.y, width: rect.size.width - horizontal, height: rect.size.height)
			
		case .northEast: return CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.size.width + horizontal, height: rect.size.height + vertical)
		case .southEast: return CGRect(x: rect.origin.x, y: rect.origin.y + vertical, width: rect.size.width + horizontal, height: rect.size.height - vertical)
		case .northWest: return CGRect(x: rect.origin.x + horizontal, y: rect.origin.y, width: rect.size.width - horizontal, height: rect.size.height + vertical)
		case .southWest: return CGRect(x: rect.origin.x + horizontal, y: rect.origin.y + vertical, width: rect.size.width - horizontal, height: rect.size.height - vertical)
			
		case .none: return CGRect(x: rect.origin.x + horizontal, y: rect.origin.y + vertical, width: rect.size.width, height: rect.size.height)
		}
	}
	
	func pointInBounds(_ bounds: CGRect, isDestination: Bool = false) -> CGPoint {
		return self.frameInBounds(bounds, withInset: 0.0, isDestination: isDestination).center
	}

	/** Return the frame surrounding this anchor with the specified inset. If `isDestination` is set, the anchor is 
	shifted a little to ensure that arrows going to and from an object do not overlap (this only affects non-corner
	anchors, e.g. only north, south, east and west). */
	func frameInBounds(_ bounds: CGRect, withInset inset: CGFloat, isDestination: Bool = false) -> CGRect {
		let destOffset: CGFloat = isDestination ? 10.0 : -10.0
		switch self {
		case .southWest: return CGRect(x: bounds.origin.x + inset/2, y: bounds.origin.y + inset/2, width: inset, height: inset)
		case .southEast: return CGRect(x: bounds.origin.x + bounds.size.width - 1.5*inset, y: bounds.origin.y + inset/2, width: inset, height: inset)
		case .northEast: return CGRect(x: bounds.origin.x + bounds.size.width - 1.5*inset, y: bounds.origin.y + bounds.size.height - 1.5*inset, width: inset, height: inset)
		case .northWest: return CGRect(x: bounds.origin.x + inset/2, y: bounds.origin.y + bounds.size.height - 1.5*inset, width: inset, height: inset)
		case .north: return CGRect(x: bounds.origin.x + inset/2 + destOffset, y: bounds.origin.y + inset/2, width: bounds.size.width - inset/2.0, height: inset)
		case .south: return CGRect(x: bounds.origin.x + inset/2 + destOffset, y: bounds.origin.y + bounds.size.height - 1.5*inset, width: bounds.size.width - inset/2.0, height: inset)
		case .west: return CGRect(x: bounds.origin.x + inset/2, y: bounds.origin.y + inset/2.0 + destOffset, width: inset, height: bounds.size.height - inset/2.0)
		case .east: return CGRect(x: bounds.origin.x + bounds.size.width - 1.5*inset, y: bounds.origin.y + inset/2.0 + destOffset, width: inset, height: bounds.size.height - inset/2.0)
		case .none: return CGRect.zero
		}
	}
	
	var cursor: NSCursor? { get {
		switch self {
		case .north: return NSCursor.resizeDown()
		case .south: return NSCursor.resizeUp()
		case .east: return NSCursor.resizeRight()
		case .west: return NSCursor.resizeLeft()
		case .northEast: return NSCursor.resizeRight()
		case .southEast: return NSCursor.resizeRight()
		case .northWest: return NSCursor.resizeLeft()
		case .southWest: return NSCursor.resizeLeft()
		default: return NSCursor.openHand()
		}
	} }
}
