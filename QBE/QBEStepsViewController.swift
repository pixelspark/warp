import Foundation
import Cocoa

protocol QBEStepsControllerDelegate: NSObjectProtocol {
	func stepsController(vc: QBEStepsViewController, didSelectStep: QBEStep)
}

@IBDesignable class QBEStepsItemView: NSView {
	private var highlighted = false
	@IBOutlet var label: NSTextField?
	@IBOutlet var imageView: NSImageView?
	@IBOutlet var previousImageView: NSImageView?
	@IBOutlet var nextImageView: NSImageView?
	
	var selected: Bool = false { didSet {
		update()
	} }
	
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
		self.addTrackingArea(NSTrackingArea(rect: frame, options: NSTrackingAreaOptions.MouseEnteredAndExited | NSTrackingAreaOptions.ActiveInActiveApp, owner: self, userInfo: nil))
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
		return step?.explain(QBEDefaultLocale(), short: false) ?? ""
	}
	
	var step: QBEStep? { didSet {
		update()
	} }
	
	private func update() {
		if let e = step?.explanation {
			label?.attributedStringValue = e
		}
		else {
			label?.attributedStringValue = NSAttributedString(string: step?.explain(QBEDefaultLocale(), short: true) ?? "??")
		}
		
		if let s = step {
			if let icon = QBEStepIcons[s.className] {
				imageView?.image = NSImage(named: icon)
			}
			
			nextImageView?.hidden = (s.next == nil) || selected || highlighted
			previousImageView?.hidden = (s.previous == nil) // || selected || highlighted
		}
	}
	
	override func drawRect(dirtyRect: NSRect) {
		if self.selected {
			NSColor.secondarySelectedControlColor().set()
		}
		else if self.highlighted {
			NSColor.selectedControlColor().set()
		}
		else {
			NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0).set()
		}
		
		NSRectFill(self.bounds)
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

class QBEStepsViewController: NSViewController, NSCollectionViewDelegate {
	@IBOutlet var collectionView: NSCollectionView!
	weak var delegate: QBEStepsControllerDelegate?
	
	private var ignoreSelection = false
	
	var steps: [QBEStep]? { didSet {
		update()
	} }
	
	var currentStep: QBEStep? { didSet {
		update()
	} }
	
	override func awakeFromNib() {
		super.awakeFromNib()
	}
	
	private func update() {
		QBEAsyncMain {
			if let cv = self.collectionView {
				if cv.itemPrototype != nil {
					cv.content = self.steps ?? []
				}
				
				// Update current selection
				var indexSet = NSMutableIndexSet()
				
				for itemNumber in 0..<cv.content.count {
					if let step = cv.content[itemNumber] as? QBEStep {
						if step == self.currentStep {
							indexSet.addIndex(itemNumber)
						}
					}
				}
				
				cv.selectionIndexes = indexSet
			}
		}
	}
	
	override func observeValueForKeyPath(keyPath: String, ofObject object: AnyObject, change: [NSObject : AnyObject], context: UnsafeMutablePointer<Void>) {
		if ignoreSelection {
			return
		}
		
		if collectionView?.selectionIndexes.count > 0 {
			if let selected = collectionView?.selectionIndexes.firstIndex {
				if let step = collectionView?.content[selected] as? QBEStep {
					ignoreSelection = true
					QBEAsyncMain {
						self.delegate?.stepsController(self, didSelectStep: step)
						self.ignoreSelection = false
						return;
					}
				}
			}
		}
	}
	
	override func viewWillAppear() {
		collectionView?.itemPrototype = QBEStepsItem(nibName: "QBEStepsItem", bundle: nil)
		collectionView?.content = steps ?? []
		collectionView.addObserver(self, forKeyPath: "selectionIndexes", options: NSKeyValueObservingOptions.New, context: nil)
		update()
	}
}