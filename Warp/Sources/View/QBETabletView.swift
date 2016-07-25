import Cocoa

/** The view of a QBETabletViewController should subclass this view. It is used to identify pieces of the tablet that are
draggable (see QBEResizableView's hitTest). */
internal class QBETabletView: NSView {
	

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	override func awakeFromNib() {
		self.wantsLayer = true
		self.layer?.backgroundColor = NSColor.windowBackgroundColor().cgColor
		self.layer?.cornerRadius = QBEResizableView.cornerRadius
		self.layer?.masksToBounds = true
	}

	override func draw(_ dirtyRect: NSRect) {
		if NSGraphicsContext.currentContextDrawingToScreen() {
			NSColor.windowBackgroundColor().set()
			NSRectFill(self.bounds)


			let gradientHeight: CGFloat = 30.0
			let g = NSGradient(starting: NSColor(calibratedWhite: 1.0, alpha: 0.5), ending: NSColor(calibratedWhite: 1.0, alpha: 0.0))
			let gradientFrame = NSMakeRect(self.bounds.origin.x, self.bounds.origin.y + self.bounds.size.height - gradientHeight, self.bounds.size.width, gradientHeight)
			g?.draw(in: gradientFrame, angle: 270.0)
		}
		else {
			NSColor.clear().set()
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
