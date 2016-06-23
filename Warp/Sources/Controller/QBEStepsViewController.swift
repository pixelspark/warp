import Foundation
import Cocoa
import WarpCore

@objc protocol QBEStepsControllerDelegate: NSObjectProtocol {
	func stepsController(_ vc: QBEStepsViewController, didSelectStep: QBEStep)
	func stepsController(_ vc: QBEStepsViewController, didRemoveStep: QBEStep)
	func stepsController(_ vc: QBEStepsViewController, didMoveStep: QBEStep, afterStep: QBEStep?)
	func stepsController(_ vc: QBEStepsViewController, didInsertStep: QBEStep, afterStep: QBEStep?)
	func stepsController(_ vc: QBEStepsViewController, showSuggestionsForStep: QBEStep, atView: NSView?)
}

class QBECollectionView: NSCollectionView {
	var active: Bool = false

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
}

class QBEStepsViewController: NSViewController, NSCollectionViewDelegate {
	@IBOutlet var collectionView: QBECollectionView! = nil
	weak var delegate: QBEStepsControllerDelegate? = nil
	private var contents: NSArrayController? = nil
	
	private var ignoreSelection = false
	private static let dragType = "nl.pixelspark.Warp.QBEStepsViewController.Step"
	
	dynamic var steps: [QBEStep]? { didSet {
		ignoreSelection = true
		update()
		ignoreSelection = false
	} }

	var active: Bool = false { didSet {
		update()
		if let cv = self.collectionView {
			cv.setNeedsDisplay(cv.bounds)
			cv.subviews.forEach { $0.setNeedsDisplay($0.bounds) }
		}
	} }

	var currentStep: QBEStep? { didSet {
		ignoreSelection = true
		update()
		ignoreSelection = false
	} }
	
	override func awakeFromNib() {
		super.awakeFromNib()
		self.collectionView?.register(forDraggedTypes: [QBEStepsViewController.dragType, QBEStep.dragType, QBEOutletView.dragType])
	}
	
	func delete(_ sender: NSObject) {
		if let s = currentStep {
			delegate?.stepsController(self, didRemoveStep: s)
		}
	}
	
	private func update() {
		assertMainThread()
		self.collectionView?.active = self.active
		
		if let cv = self.collectionView {
			// Update current selection
			let indexSet = NSMutableIndexSet()
			
			for itemNumber in 0..<cv.content.count {
				if let step = cv.content[itemNumber] as? QBEStep {
					if step == self.currentStep {
						indexSet.add(itemNumber)
					}
				}
			}
			
			if !indexSet.isEqual(to: cv.selectionIndexes) {
				cv.selectionIndexes = indexSet as IndexSet
			}
		}
	}
	
	func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexes: IndexSet, with event: NSEvent) -> Bool {
		return true
	}
	
	func collectionView(_ collectionView: NSCollectionView, writeItemsAt indexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
		pasteboard.declareTypes([QBEStepsViewController.dragType, QBEStep.dragType], owner: nil)
		
		// We're writing an internal drag item (just the index) and an external drag item (serialized step)
		let data = NSKeyedArchiver.archivedData(withRootObject: indexes)
		pasteboard.setData(data, forType: QBEStepsViewController.dragType)
		
		let first = indexes.first
		if first != NSNotFound {
			if let step = steps?[first!] {
				let fullData = NSKeyedArchiver.archivedData(withRootObject: step)
				pasteboard.setData(fullData, forType: QBEStep.dragType)
			}
		}
		
		return true
	}
	
	func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndex proposedDropIndex: UnsafeMutablePointer<Int>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionViewDropOperation>) -> NSDragOperation {
		return NSDragOperation.move
	}
	
	func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, index: Int, dropOperation: NSCollectionViewDropOperation) -> Bool {
		let pboard = draggingInfo.draggingPasteboard()
		if let s = steps {
			let afterStep: QBEStep? = (index <= s.count && index >= 1) ? s[index-1] : nil
			
			// Check if we're doing an internal move
			if	let data = pboard.data(forType: QBEStepsViewController.dragType),
				let ds = draggingInfo.draggingSource() as? NSCollectionView where ds == collectionView {
				if let indices = NSKeyedUnarchiver.unarchiveObject(with: data) as? IndexSet {
					let draggedIndex = indices.first
					
					if draggedIndex != NSNotFound && draggedIndex < s.count {
						// Swap away
						let step = s[draggedIndex!]
						self.delegate?.stepsController(self, didMoveStep: step, afterStep: afterStep)
						return true
					}
				}
			}
			// ... or are receiving a step from some other place
			else if let data = pboard.data(forType: QBEStep.dragType) {
				if let step = NSKeyedUnarchiver.unarchiveObject(with: data) as? QBEStep {
					// We only want the dragged step, not its predecessors
					step.previous = nil
					self.delegate?.stepsController(self, didInsertStep: step, afterStep: afterStep)
				}
				return true
			}
		}
		return false
	}
	
	override func observeValue(forKeyPath keyPath: String?, of object: AnyObject?, change: [NSKeyValueChangeKey : AnyObject]?, context: UnsafeMutablePointer<Void>?) {
		if ignoreSelection {
			return
		}
		
		if collectionView?.selectionIndexes.count > 0 {
			if let selected = collectionView?.selectionIndexes.first {
				if let step = collectionView?.content[selected] as? QBEStep {
					ignoreSelection = true
					asyncMain {
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
	
	override func viewDidDisappear() {
		collectionView?.removeObserver(self, forKeyPath: "selectionIndexes")
		collectionView?.unbind(NSContentBinding)
		super.viewDidDisappear()
	}
	
	override func viewWillAppear() {
		collectionView?.itemPrototype = QBEStepsItem(nibName: "QBEStepsItem", bundle: nil)
		//collectionView?.content = steps
		collectionView?.bind(NSContentBinding, to: self, withKeyPath: "steps", options: nil)
		collectionView?.addObserver(self, forKeyPath: "selectionIndexes", options: NSKeyValueObservingOptions.new, context: nil)
		update()
	}
}
