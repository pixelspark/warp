import Foundation
import Cocoa

@objc protocol QBEStepsControllerDelegate: NSObjectProtocol {
	func stepsController(vc: QBEStepsViewController, didSelectStep: QBEStep)
	func stepsController(vc: QBEStepsViewController, didRemoveStep: QBEStep)
	func stepsController(vc: QBEStepsViewController, didMoveStep: QBEStep, afterStep: QBEStep!)
}

@IBDesignable class QBEStepsItemView: NSView {
	private var highlighted = false
	@IBOutlet var label: NSTextField?
	@IBOutlet var imageView: NSImageView?
	@IBOutlet var previousImageView: NSImageView?
	@IBOutlet var nextImageView: NSImageView?
	@IBOutlet var removeButton: NSButton?
	
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
		return step?.explain(QBELocale(), short: false) ?? ""
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
	
	private func update() {
		label?.attributedStringValue = NSAttributedString(string: step?.explain(QBELocale(), short: true) ?? "??")
		
		if let s = step {
			if let icon = QBEStepIcons[s.className] {
				imageView?.image = NSImage(named: icon)
			}
			
			removeButton?.hidden = !highlighted
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
	private var contents: NSArrayController?
	@IBOutlet var addButton: NSButton!
	
	private var ignoreSelection = false
	private static let DragType = "nl.pixelspark.Warp.QBEStepsViewController.Step"
	
	dynamic var steps: [QBEStep]? { didSet {
		ignoreSelection = true
		update()
		ignoreSelection = false
	} }
	
	var currentStep: QBEStep? { didSet {
		ignoreSelection = true
		update()
		ignoreSelection = false
	} }
	
	override func awakeFromNib() {
		super.awakeFromNib()
		self.collectionView?.registerForDraggedTypes([QBEStepsViewController.DragType])
	}
	
	func delete(sender: NSObject) {
		if let s = currentStep {
			delegate?.stepsController(self, didRemoveStep: s)
		}
	}
	
	private func update() {
		QBEAsyncMain {
			if let cv = self.collectionView {
				// Update current selection
				var indexSet = NSMutableIndexSet()
				
				for itemNumber in 0..<cv.content.count {
					if let step = cv.content[itemNumber] as? QBEStep {
						if step == self.currentStep {
							indexSet.addIndex(itemNumber)
						}
					}
				}
				
				if !indexSet.isEqualToIndexSet(cv.selectionIndexes) {
					cv.selectionIndexes = indexSet
				}
			}
		}
	}
	
	func collectionView(collectionView: NSCollectionView, canDragItemsAtIndexes indexes: NSIndexSet, withEvent event: NSEvent) -> Bool {
		return true
	}
	
	func collectionView(collectionView: NSCollectionView, writeItemsAtIndexes indexes: NSIndexSet, toPasteboard pasteboard: NSPasteboard) -> Bool {
		let data = NSKeyedArchiver.archivedDataWithRootObject(indexes)
		pasteboard.declareTypes([QBEStepsViewController.DragType], owner: nil)
		pasteboard.setData(data, forType: QBEStepsViewController.DragType)
		return true
	}
	
	func collectionView(collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndex proposedDropIndex: UnsafeMutablePointer<Int>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionViewDropOperation>) -> NSDragOperation {
		return NSDragOperation.Move
	}
	
	func collectionView(collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, index: Int, dropOperation: NSCollectionViewDropOperation) -> Bool {
		let pboard = draggingInfo.draggingPasteboard()
		if let data = pboard.dataForType(QBEStepsViewController.DragType) {
			if let indices = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? NSIndexSet {
				let draggedIndex = indices.firstIndex
				
				if let s = steps where draggedIndex != NSNotFound && draggedIndex < s.count {
					// Swap away
					let step = s[draggedIndex]
					let afterStep: QBEStep? = (index <= s.count && index >= 1) ? s[index-1] : nil
					self.delegate?.stepsController(self, didMoveStep: step, afterStep: afterStep)
					return true
				}
			}
		}
		return false
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
		else {
			ignoreSelection = true
			self.update()
			self.ignoreSelection = false
		}
	}
	
	override func viewWillAppear() {
		collectionView?.itemPrototype = QBEStepsItem(nibName: "QBEStepsItem", bundle: nil)
		//collectionView?.content = steps
		collectionView?.bind(NSContentBinding, toObject: self, withKeyPath: "steps", options: nil)
		collectionView.addObserver(self, forKeyPath: "selectionIndexes", options: NSKeyValueObservingOptions.New, context: nil)
		update()
	}
}