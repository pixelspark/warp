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
		if menuItem.action == #selector(QBEStepsItemView.remove(_:)) {
			return true
		}
		else if menuItem.action == #selector(QBEStepsItemView.showSuggestions(_:)) {
			if let s = step, let alternatives = s.alternatives where alternatives.count > 0 {
				return true
			}
		}
		
		return false
	}
	
	@IBAction func showSuggestions(_ sender: NSObject) {
		if let s = step, let alternatives = s.alternatives where alternatives.count > 0 {
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
			if let sv = self.superview as? QBECollectionView where !sv.active {
				NSColor.secondarySelectedControlColor().set()
			}
			else {
				NSColor.blue().withAlphaComponent(0.2).set()
			}
			//NSColor.selectedControlColor().set()
		}
		else if self.highlighted {
			NSColor.secondarySelectedControlColor().set()
		}
		else {
			NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0).set()
		}

		let rr = NSBezierPath(roundedRect: self.bounds.inset(2.0), xRadius: 3.0, yRadius: 3.0)
		rr.fill()
	}
	
	override var allowsVibrancy: Bool { get {
		return true
	} }
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
