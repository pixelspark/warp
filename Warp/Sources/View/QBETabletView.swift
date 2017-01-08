/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Cocoa

/** The view of a QBETabletViewController should subclass this view. It is used to identify pieces of the tablet that are
draggable (see QBEResizableView's hitTest). */
internal class QBETabletView: NSView {
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	override func awakeFromNib() {
		self.wantsLayer = true
		self.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
		self.layer?.cornerRadius = QBEResizableView.cornerRadius
		self.layer?.masksToBounds = true
	}

	override func draw(_ dirtyRect: NSRect) {
		if NSGraphicsContext.currentContextDrawingToScreen() {
			NSColor.windowBackgroundColor.set()
			NSRectFill(self.bounds)


			let gradientHeight: CGFloat = 30.0
			let g = NSGradient(starting: NSColor(calibratedWhite: 1.0, alpha: 0.5), ending: NSColor(calibratedWhite: 1.0, alpha: 0.0))
			let gradientFrame = NSMakeRect(self.bounds.origin.x, self.bounds.origin.y + self.bounds.size.height - gradientHeight, self.bounds.size.width, gradientHeight)
			g?.draw(in: gradientFrame, angle: 270.0)
		}
		else {
			NSColor.clear.set()
			NSRectFill(dirtyRect)
		}
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override func becomeFirstResponder() -> Bool {
		for sv in self.subviews {
			if sv.acceptsFirstResponder && self.window!.makeFirstResponder(sv) {
				return true
			}
		}
		return true // Tablet controller becomes first responder
	}

	override var allowsVibrancy: Bool { return true }
}
