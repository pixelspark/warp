import Cocoa

@IBDesignable class QBEStepsItemView: NSView {
	private var highlighted = false
	@IBOutlet var label: NSTextField?
	@IBOutlet var imageView: NSButton?
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
		self.addToolTipRect(frame, owner: self, userData: nil)
		self.addTrackingArea(NSTrackingArea(rect: frame, options: [NSTrackingAreaOptions.MouseEnteredAndExited, NSTrackingAreaOptions.ActiveInActiveApp], owner: self, userInfo: nil))
	}
	
	override func mouseEntered(theEvent: NSEvent) {
		highlighted = true
		update()
		setNeedsDisplayInRect(self.bounds)
	}
	
	override func mouseExited(theEvent: NSEvent) {
		highlighted = false
		update()
		setNeedsDisplayInRect(self.bounds)
	}
	
	override func view(view: NSView, stringForToolTip tag: NSToolTipTag, point: NSPoint, userData data: UnsafeMutablePointer<Void>) -> String {
		return step?.explain(QBELocale()) ?? ""
	}
	
	var step: QBEStep? { didSet {
		update()
	} }
	
	@IBAction func remove(sender: NSObject) {
		if let s = step {
			if let cv = self.superview as? NSCollectionView {
				if let sc = cv.delegate as? QBEStepsViewController {
					sc.delegate?.stepsController(sc, didRemoveStep: s)
				}
			}
		}
	}
	
	override func validateMenuItem(menuItem: NSMenuItem) -> Bool {
		if menuItem.action == Selector("remove:") {
			return true
		}
		else if menuItem.action == Selector("showSuggestions:") {
			if let s = step, let alternatives = s.alternatives where alternatives.count > 0 {
				return true
			}
		}
		
		return false
	}
	
	@IBAction func showSuggestions(sender: NSObject) {
		if let s = step, let alternatives = s.alternatives where alternatives.count > 0 {
			if let cv = self.superview as? NSCollectionView {
				if let sc = cv.delegate as? QBEStepsViewController {
					sc.delegate?.stepsController(sc, showSuggestionsForStep: s, atView: self)
				}
			}
		}
	}
	
	override func hitTest(aPoint: NSPoint) -> NSView? {
		if self.selected {
			return super.hitTest(aPoint)
		}
		return self.frame.contains(aPoint) ? self : nil
	}
	
	private func update() {
		label?.attributedStringValue = NSAttributedString(string: step?.explain(QBELocale()) ?? "??")
		
		if let s = step {
			if let icon = QBEFactory.sharedInstance.iconForStep(s) {
				imageView?.image = NSImage(named: icon)
			}
			
			nextImageView?.hidden = (s.next == nil) || selected || highlighted
			previousImageView?.hidden = (s.previous == nil) // || selected || highlighted
		}
	}
	
	override func drawRect(dirtyRect: NSRect) {
		if self.selected {
			NSColor.blueColor().colorWithAlphaComponent(0.15).set()
			//NSColor.selectedControlColor().set()
		}
		else if self.highlighted {
			NSColor.secondarySelectedControlColor().set()
		}
		else {
			NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0).set()
		}
		
		NSRectFill(dirtyRect)
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
	
	override var selected: Bool { didSet {
		if let v = self.view as? QBEStepsItemView {
			v.selected = selected
			v.setNeedsDisplayInRect(v.bounds)
		}
	} }
}