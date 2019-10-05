/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import Cocoa

protocol QBEResizableDelegate: NSObjectProtocol {
	func resizableView(_ view: QBEResizableView, changedFrameTo: CGRect)
	func resizableViewWasSelected(_ view: QBEResizableView)
	func resizableViewWasDoubleClicked(_ view: QBEResizableView)
}

class QBEResizableView: NSView {
	static let cornerRadius: CGFloat = 8.0
	private var resizerView: QBEResizerView! = nil
	weak var delegate: QBEResizableDelegate?
	
	var selected: Bool = false { didSet {
		setNeedsDisplay(self.bounds)
		self.needsDisplay = true
		resizerView.setNeedsDisplay(resizerView.bounds)
		DispatchQueue.main.async {
			self.addSubview(self.resizerView, positioned: .above, relativeTo: nil)
		}
	} }
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		self.wantsLayer = true
		self.layer!.isOpaque = true
		self.layer!.drawsAsynchronously = false
		self.layer!.masksToBounds = true
		self.layer!.cornerRadius = type(of: self).cornerRadius
		self.layer!.shadowRadius = 3.0
		self.layer!.shadowColor = NSColor.shadowColor.cgColor
		self.layer!.shadowOpacity = 0.3
		self.layerContentsRedrawPolicy = .onSetNeedsDisplay

		resizerView = QBEResizerView(frame: self.bounds)
		resizerView.autoresizingMask = [NSView.AutoresizingMask.height, NSView.AutoresizingMask.width]
		resizerView.hide = true
		self.needsDisplay = true
		addSubview(resizerView)
	}
	
	required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	var contentView: NSView? { didSet {
		oldValue?.removeFromSuperview()
		
		if let c = contentView {
			c.removeFromSuperview()
			c.wantsLayer = true
			c.layer!.cornerRadius = type(of: self).cornerRadius
			c.layer!.masksToBounds = true
			c.translatesAutoresizingMaskIntoConstraints = false

			self.addSubview(c, positioned: NSWindow.OrderingMode.below, relativeTo: resizerView)
			self.addSubview(resizerView, positioned: .above, relativeTo: nil)
			resizerView.contentView = c

			self.addConstraints([
				NSLayoutConstraint(item: c, attribute: .top, relatedBy: .equal, toItem: self, attribute: .top, multiplier: 1.0, constant: self.resizerView.inset),
				NSLayoutConstraint(item: c, attribute: .left, relatedBy: .equal, toItem: self, attribute: .left, multiplier: 1.0, constant: self.resizerView.inset),
				NSLayoutConstraint(item: c, attribute: .right, relatedBy: .equal, toItem: self, attribute: .right, multiplier: 1.0, constant: -self.resizerView.inset),
				NSLayoutConstraint(item: c, attribute: .bottom, relatedBy: .equal, toItem: self, attribute: .bottom, multiplier: 1.0, constant: -self.resizerView.inset)
			])
		}
		else {
			resizerView.contentView = nil
		}
	} }
	
	override func hitTest(_ aPoint: NSPoint) -> NSView? {
		if let cv = contentView {
			// Dirty hack to find out when one of our subviews is clicked, so we can select ourselves
			let pt = convert(aPoint, from: superview)
			if let ht = cv.hitTest(pt) {
				if let ev = self.window?.currentEvent, ev.type == NSEvent.EventType.leftMouseDown {
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
		addTrackingArea(NSTrackingArea(rect: self.bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil))
		super.updateTrackingAreas()
	}
	
	override func resetCursorRects() {
		// Find NSCollectionView children and show a grab cursor for them
		findGrabbableViews(self)
	}
	
	private func findGrabbableViews(_ parent: NSView) {		
		parent.subviews.forEach { (subview) -> () in
			if subview is NSCollectionView {
				self.addCursorRect(subview.convert(subview.bounds, to: self), cursor: NSCursor.openHand)
			}
			findGrabbableViews(subview)
		}
	}
	
	override func mouseEntered(with theEvent: NSEvent) {
		self.resizerView.hide = false
	}
	
	override func mouseExited(with theEvent: NSEvent) {
		self.resizerView.hide = true
	}
	
	override func mouseDown(with theEvent: NSEvent) {
		self.window?.invalidateCursorRects(for: self)
		self.updateTrackingAreas()
	}
	
	override func mouseUp(with theEvent: NSEvent) {
		self.window?.invalidateCursorRects(for: self)
		self.updateTrackingAreas()
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
	private var visibleAnchors: Set<QBEAnchor> = [.south, .north, .east, .west, .southEast, .southWest, .northEast, .northWest];
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		self.wantsLayer = true
		self.layer?.drawsAsynchronously = false
		self.layer?.cornerRadius = QBEResizableView.cornerRadius
		self.layer?.masksToBounds = true
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	var contentView: NSView? { didSet {
		update(nil)
	} }
	
	var hide: Bool = false { didSet {
		setNeedsDisplay(self.bounds)
	} }
	
	var isResizing: Bool {
		return resizingSession != nil
	}

	var selected: Bool {
		return (self.superview as! QBEResizableView).selected
	}
	
	internal override func hitTest(_ aPoint: NSPoint) -> NSView? {
		let pt = convert(aPoint, from: superview)

		// If a subview is about to receive a mouse down event, then this tablet should be selected.
		if self.bounds.contains(pt) {
			if !self.selected {
				if let ev = self.window?.currentEvent, ev.type == NSEvent.EventType.leftMouseDown {
					self.mouseDownInSubiew(ev)
				}
			}
		}

		return self.bounds.contains(pt) && !self.bounds.inset(inset).contains(pt) ? self : nil
	}
	
	private func updateSize(_ theEvent: NSEvent) {
		if let rs = resizingSession {
			let locationInView = superview!.superview!.convert(theEvent.locationInWindow, from: nil)
			
			let delta = (Int(locationInView.x - rs.downPoint.x), Int(locationInView.y - rs.downPoint.y))
			let newFrame = rs.downAnchor.offset(rs.downRect, horizontal: CGFloat(delta.0), vertical: CGFloat(delta.1)).rounded
			let minSize = self.superview!.fittingSize
			if newFrame.size.width >= minSize.width && newFrame.size.height > minSize.height {
				self.superview?.frame = newFrame
				self.frame = self.superview!.bounds
				resizingSession!.moved = true
			}
		}
		
		update(theEvent)
	}
	
	private func update(_ event: NSEvent?) {
		if let p = superview as? QBEResizableView {
			p.delegate?.resizableView(p, changedFrameTo: p.frame)
		}
		
		if let theEvent = event, let rs = resizingSession {
			let locationInSuperView = superview!.superview!.convert(theEvent.locationInWindow, from: nil)
			resizingSession = ResizingSession(downPoint: locationInSuperView, downRect: self.superview!.frame, downAnchor: rs.downAnchor, moved: rs.moved)
		}
	}
	
	override func resetCursorRects() {
		self.addCursorRect(self.bounds.insetBy(dx: inset, dy: inset), cursor: NSCursor.openHand)
		if canResize {
			for anchor in visibleAnchors {
				let frame = anchor.frameInBounds(self.bounds, withInset: inset)
				if let c = anchor.cursor {
					self.addCursorRect(frame, cursor: c)
				}
			}
		}
	}
	
	private func anchorForPoint(_ locationInView: CGPoint) -> QBEAnchor {
		let dx = locationInView.x
		let dy = locationInView.y
		
		let insetWithMargin = inset * 2
		
		// What anchor are we dragging?
		if dx < insetWithMargin {
			if dy > self.bounds.height-insetWithMargin {
				return .northWest
			}
			else if dy < insetWithMargin {
				return .southWest
			}
			else {
				return .west
			}
		}
		else if dx > self.bounds.width-insetWithMargin {
			if dy > self.bounds.height-insetWithMargin {
				return .northEast
			}
			else if dy < insetWithMargin {
				return .southEast
			}
			else {
				return .east
			}
		}
		else {
			if dy > self.bounds.height - (insetWithMargin / 4.0 * 3.0) {
				return .north
			}
			else if dy < insetWithMargin {
				return .south
			}
			else {
				return .none
			}
		}
	}
	
	var canResize: Bool { get {
		// Find scroll view, if it is in zoomed mode we cannot resize
		var sv: NSView? = self
		while let svx = sv, !(svx is QBEWorkspaceView) {
			sv = svx.superview
		}
		
		return true
	} }
	
	override func mouseDown(with theEvent: NSEvent) {
		if canResize {
			let locationInView = self.convert(theEvent.locationInWindow, from: nil)
			let locationInSuperView = superview!.superview!.convert(theEvent.locationInWindow, from: nil)
			
			let closestAnchor = anchorForPoint(locationInView)
			let realAnchor = visibleAnchors.contains(closestAnchor) ? closestAnchor : .none
			
			// Order view to front
			if let sv = superview, let psv = sv.superview {
				psv.addSubview(sv)
			}
			
			resizingSession = ResizingSession(downPoint: locationInSuperView, downRect: self.superview!.frame, downAnchor: realAnchor, moved: false)
			setNeedsDisplay(self.bounds)
			self.window?.disableCursorRects()
			NSCursor.closedHand.set()
		}
	}

	// This draws on top of a tablet
	override func draw(_ dirtyRect: NSRect) {
		if let context = NSGraphicsContext.current?.cgContext {
			context.clear(dirtyRect)

			// Draw the bounding box
			let selected = (self.superview as! QBEResizableView).selected
			let borderColor = selected ? NSColor.selectedControlColor : NSColor.clear
			context.setStrokeColor(borderColor.cgColor)
			let bounds = self.bounds.inset(inset - 1.0)
			let rr = NSBezierPath(roundedRect: bounds, xRadius: QBEResizableView.cornerRadius, yRadius: QBEResizableView.cornerRadius)
			rr.lineWidth = 3.0
			rr.stroke()
		}
	}
	
	override func mouseDragged(with theEvent: NSEvent) {
		updateSize(theEvent)
	}

	func mouseDownInSubiew(_ event: NSEvent) {
		if resizingSession == nil || !resizingSession!.moved {
			if let p = superview as? QBEResizableView {
				if !p.selected {
					p.delegate?.resizableViewWasSelected(p)
				}
			}
		}
	}

	override func mouseUp(with theEvent: NSEvent) {
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
		self.window?.enableCursorRects()
		self.window?.resetCursorRects()
		//self.window?.invalidateCursorRects(for: self)
		setNeedsDisplay(self.bounds)
	}
}
