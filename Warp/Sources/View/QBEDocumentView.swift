import Cocoa
import WarpCore

@objc protocol QBEDocumentViewDelegate: NSObjectProtocol {
	func documentView(view: QBEDocumentView, didSelectTablet: QBETablet?)
	func documentView(view: QBEDocumentView, didSelectArrow: QBETabletArrow?)
	func documentView(view: QBEDocumentView, wantsZoomToView: NSView)
}

internal class QBEDocumentView: NSView, QBEResizableDelegate, QBEFlowchartViewDelegate {
	@IBOutlet weak var delegate: QBEDocumentViewDelegate?
	var flowchartView: QBEFlowchartView!
	private var draggingOver: Bool = false
	
	override init(frame frameRect: NSRect) {
		flowchartView = QBEFlowchartView(frame: frameRect)
		super.init(frame: frameRect)
		flowchartView.frame = self.bounds
		flowchartView.delegate = self
		addSubview(flowchartView)
		self.wantsLayer = true
	}
	
	override func prepareForDragOperation(sender: NSDraggingInfo) -> Bool {
		return true
	}
	
	func removeAllTablets() {
		subviews.forEach { ($0 as? QBEResizableTabletView)?.removeFromSuperview() }
	}
	
	func selectTablet(tablet: QBETablet?, notifyDelegate: Bool = true) {
		if let t = tablet {
			for sv in subviews {
				if let tv = sv as? QBEResizableTabletView {
					if tv.tabletController.tablet == t {
						selectView(tv, wasAlreadySelected: !notifyDelegate)
						return
					}
				}
			}
		}
		else {
			selectView(nil)
		}
	}
	
	func flowchartView(view: QBEFlowchartView, didSelectArrow arrow: QBEArrow?) {
		selectView(nil)
		if let tabletArrow = arrow as? QBETabletArrow {
			delegate?.documentView(self, didSelectArrow: tabletArrow)
		}
	}
	
	private func selectView(view: QBEResizableTabletView?, wasAlreadySelected: Bool = false) {
		// Deselect other views
		for sv in subviews {
			if let tv = sv as? QBEResizableTabletView {
				tv.selected = (tv == view)
				if tv == view {
					self.window?.makeFirstResponder(tv.tabletController.view)

					if !wasAlreadySelected {
						delegate?.documentView(self, didSelectTablet: tv.tabletController.tablet)
					}
					self.window?.update()
				}
			}
		}
		
		if view == nil {
			if !wasAlreadySelected {
				delegate?.documentView(self, didSelectTablet: nil)
			}
		}
	}
	
	private func zoomToView(view: QBEResizableTabletView) {
		delegate?.documentView(self, wantsZoomToView: view)
	}
	
	func resizableViewWasSelected(view: QBEResizableView, wasAlreadySelected: Bool) {
		flowchartView.selectedArrow = nil
		selectView(view as? QBEResizableTabletView, wasAlreadySelected: wasAlreadySelected)
	}
	
	func resizableViewWasDoubleClicked(view: QBEResizableView) {
		zoomToView(view as! QBEResizableTabletView)
	}
	
	func resizableView(view: QBEResizableView, changedFrameTo frame: CGRect) {
		if let tv = view as? QBEResizableTabletView {
			let tablet = tv.tabletController.tablet
			let sizeChanged = tablet.frame == nil || tablet.frame!.size.width != frame.size.width || tablet.frame!.size.height != frame.size.height
			tablet.frame = frame
			tabletsChanged()
			if tv.selected && sizeChanged {
				tv.scrollRectToVisible(tv.bounds)
			}
		}
		setNeedsDisplayInRect(self.bounds)
	}
	
	var boundsOfAllTablets: CGRect? { get {
		// Find out the bounds of all tablets combined
		var allBounds: CGRect? = nil
		for vw in subviews {
			if vw !== flowchartView {
				allBounds = allBounds == nil ? vw.frame : CGRectUnion(allBounds!, vw.frame)
			}
		}
		return allBounds
	} }
	
	func reloadData() {
		tabletsChanged()
	}
	
	func resizeDocument() {
		let parentSize = self.superview?.bounds ?? CGRectMake(0,0,500,500)
		let contentMinSize = boundsOfAllTablets ?? parentSize
		
		// Determine new size of the document
		let margin: CGFloat = 500
		var newBounds = contentMinSize.insetBy(dx: -margin, dy: -margin)
		let offset = CGPointMake(-newBounds.origin.x, -newBounds.origin.y)
		newBounds.offsetInPlace(dx: offset.x, dy: offset.y)
		
		// Translate the 'visible rect' (just like we will translate tablets)
		let newVisible = self.visibleRect.offsetBy(dx: offset.x, dy: offset.y)
		
		// Move all tablets
		for vw in subviews {
			if let tv = vw as? QBEResizableTabletView {
				let tablet = tv.tabletController.tablet
				if let tabletFrame = tablet.frame {
					tablet.frame = tabletFrame.offsetBy(dx: offset.x, dy: offset.y)
					tv.frame = tablet.frame!
				}
			}
		}
		
		// Set new document bounds and scroll to the 'old' location in the new coordinate system
		self.frame = CGRectMake(0, 0, newBounds.size.width, newBounds.size.height)
		self.scrollRectToVisible(newVisible)
	}
	
	// Call whenever tablets are added/removed or resized
	private func tabletsChanged() {
		self.flowchartView.frame = self.bounds
		// Update flowchart
		var arrows: [QBEArrow] = []
		for va in subviews {
			if let vc = va as? QBEResizableTabletView {
				arrows += (vc.tabletController.tablet.arrows as [QBEArrow])
			}
		}
		flowchartView.arrows = arrows
	}
	
	private var selectedView: QBEResizableTabletView? { get {
		for vw in subviews {
			if let tv = vw as? QBEResizableTabletView {
				if tv.selected {
					return tv
				}
			}
		}
		return nil
	}}
	
	var selectedTablet: QBETablet? { get {
		return selectedView?.tabletController.tablet
	} }
	
	var selectedTabletController: QBETabletViewController? { get {
		return selectedView?.tabletController
	} }
	
	override func mouseDown(theEvent: NSEvent) {
		selectView(nil)
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	func removeTablet(tablet: QBETablet, completion: (() -> ())? = nil) {
		for subview in subviews {
			if let rv = subview as? QBEResizableTabletView {
				let ct = rv.tabletController.tablet
				if ct == tablet {
					subview.removeFromSuperview(true) {
						assertMainThread()
						
						self.tabletsChanged()
						completion?()
					}
					return
				}
			}
		}
	}
	
	func addTablet(tabletController: QBETabletViewController, animated: Bool = true, completion: (() -> ())? = nil) {
		let resizer = QBEResizableTabletView(frame: tabletController.tablet.frame!, controller: tabletController)
		resizer.contentView = tabletController.view
		resizer.delegate = self
	
		self.addSubview(resizer, animated: animated, completion: completion)
		tabletsChanged()
	}
	
	/** This view needs to be able to be first responder, so that QBEDocumentViewCOntroller can respond to first 
	responder actions even when there are no children selected. */
	override var acceptsFirstResponder: Bool { get { return true } }
}

private class QBEResizableTabletView: QBEResizableView {
	let tabletController: QBETabletViewController
	
	init(frame: CGRect, controller: QBETabletViewController) {
		self.tabletController = controller
		super.init(frame: frame)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}

class QBEScrollView: NSScrollView {
	private var oldZoomedRect: NSRect? = nil
	private(set) var magnifiedView: NSView? = nil
	private var magnificationInProgress = false
	
	func zoomView(view: NSView, completion: (() -> ())? = nil) {
		// First just try to magnify to the tablet
		if self.magnification < 1.0 {
			NSAnimationContext.runAnimationGroup({ (ac) -> Void in
				ac.duration = 0.3
				self.animator().magnifyToFitRect(view.frame)
			}, completionHandler: {
				// If the tablet is too large, we are still zoomed out a bit. Force zoom in by zooming in on a part of the tablet
				if self.magnification < 1.0 {
					NSAnimationContext.runAnimationGroup({ (ac) -> Void in
						ac.duration = 0.3
						let maxSize = self.bounds
						let frame = view.frame
						let zoomedHeight = min(maxSize.size.height, frame.size.height)
						let zoom = CGRectMake(frame.origin.x, frame.origin.y + (frame.size.height - zoomedHeight), min(maxSize.size.width, frame.size.width), zoomedHeight)
						self.animator().magnifyToFitRect(zoom)
					}, completionHandler: completion)
				}
			})
		}
		else {
			self.magnifyView(view, completion: completion)
		}
	}
	
	func magnifyView(view: NSView?, completion: (() -> ())? = nil) {
		assertMainThread()

		if magnificationInProgress {
			completion?()
			return
		}

		magnificationInProgress = true

		let completer = {() -> () in
			assertMainThread()
			self.magnificationInProgress = false
			completion?()
		}

		let zoom = {() -> () in
			if let zv = view {
				self.magnifiedView = zv
				self.oldZoomedRect = zv.frame
				self.hasHorizontalScroller = false
				self.hasVerticalScroller = false
				
				// Approximate the document visible rectangle at magnification 1.0, to smoothen the animation
				let oldMagnification = self.magnification
				self.magnification = 1.0
				let visibleRect = self.documentVisibleRect
				self.magnification = oldMagnification

				NSAnimationContext.runAnimationGroup({ (ac) -> Void in
					self.animator().magnification = 1.0
					ac.duration = 0.3
					zv.animator().frame = visibleRect
				}) {
					// Final adjustment
					zv.frame = self.documentVisibleRect
					NSAnimationContext.runAnimationGroup({ (ac) -> Void in
						ac.duration = 0.1
						zv.animator().frame = self.documentVisibleRect.inset(-11.0)
					}, completionHandler: completer)
				}
			}
			else {
				self.oldZoomedRect = nil
				self.hasHorizontalScroller = true
				self.hasVerticalScroller = true
				
				if let oldView = self.magnifiedView {
					self.magnifiedView = nil
					NSAnimationContext.runAnimationGroup({ (ac) -> Void in
						ac.duration = 0.3
						oldView.animator().scrollRectToVisible(oldView.bounds)
					}, completionHandler: completer)
				}
				else {
					completer()
				}
			}
		}
		
		// Un-zoom the old view (if any)
		if let old = self.magnifiedView, oldRect = self.oldZoomedRect {
			old.autoresizingMask = NSAutoresizingMaskOptions.ViewNotSizable
			NSAnimationContext.runAnimationGroup({ (ac) -> Void in
				ac.duration = 0.3
				old.animator().frame = oldRect
			}, completionHandler: zoom)
			
		}
		else {
			zoom()
		}
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	override func scrollWheel(theEvent: NSEvent) {
		if magnifiedView == nil {
			super.scrollWheel(theEvent)
		}
		else {
			self.magnifyView(nil)
		}
	}
}

protocol QBEWorkspaceViewDelegate: NSObjectProtocol {
	/** Files were dropped in the workspace. */
	func workspaceView(view: QBEWorkspaceView, didReceiveFiles: [String], atLocation: CGPoint)

	/** A chain was dropped to the workspace. The chain already exists in the workspace. */
	func workspaceView(view: QBEWorkspaceView, didReceiveChain: QBEChain, atLocation: CGPoint)

	/** A step was dropped to the workspace. The step is not an existing step instance (e.g. it is created anew). */
	func workspaceView(view: QBEWorkspaceView, didReceiveStep: QBEStep, atLocation: CGPoint)

	/** A column set was dropped in the workspace */
	func workspaceView(view: QBEWorkspaceView, didRecieveColumnSet:[Column], fromDataViewController: QBEDataViewController)
}

class QBEWorkspaceView: QBEScrollView {
	private var draggingOver: Bool = false
	weak var delegate: QBEWorkspaceViewDelegate? = nil
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	override func awakeFromNib() {
		registerForDraggedTypes([NSFilenamesPboardType, QBEOutletView.dragType, MBTableGridColumnDataType, QBEStep.dragType])
	}
	
	override func draggingEntered(sender: NSDraggingInfo) -> NSDragOperation {
		let pboard = sender.draggingPasteboard()
		
		if let _: [String] = pboard.propertyListForType(NSFilenamesPboardType) as? [String] {
			draggingOver = true
			setNeedsDisplayInRect(self.bounds)
			return NSDragOperation.Copy
		}
		else if let _ = pboard.dataForType(QBEStep.dragType) {
			draggingOver = true
			setNeedsDisplayInRect(self.bounds)
			return NSDragOperation.Copy
		}
		else if let _ = pboard.dataForType(QBEOutletView.dragType) {
			draggingOver = true
			setNeedsDisplayInRect(self.bounds)
			return NSDragOperation.Link
		}
		else if let _ = pboard.dataForType(MBTableGridColumnDataType) {
			draggingOver = true
			setNeedsDisplayInRect(self.bounds)
			return NSDragOperation.Link
		}
		return NSDragOperation.None
	}
	
	override func draggingUpdated(sender: NSDraggingInfo) -> NSDragOperation {
		return draggingEntered(sender)
	}
	
	override func draggingExited(sender: NSDraggingInfo?) {
		draggingOver = false
		setNeedsDisplayInRect(self.bounds)
	}
	
	override func draggingEnded(sender: NSDraggingInfo?) {
		draggingOver = false
		setNeedsDisplayInRect(self.bounds)
	}
	
	override func drawRect(dirtyRect: NSRect) {
		if draggingOver {
			NSColor.blueColor().colorWithAlphaComponent(0.15).set()
		}
		else {
			NSColor.clearColor().set()
		}
		NSRectFill(dirtyRect)
	}
	
	override func prepareForDragOperation(sender: NSDraggingInfo) -> Bool {
		return true
	}
	
	override func performDragOperation(draggingInfo: NSDraggingInfo) -> Bool {
		let pboard = draggingInfo.draggingPasteboard()
		let pointInWorkspace = self.convertPoint(draggingInfo.draggingLocation(), fromView: nil)
		let pointInDocument = self.convertPoint(pointInWorkspace, toView: self.documentView as? NSView)
		
		if let _ = pboard.dataForType(QBEOutletView.dragType) {
			if let ov = draggingInfo.draggingSource() as? QBEOutletView {
				if let draggedChain = ov.draggedObject as? QBEChain {
					delegate?.workspaceView(self, didReceiveChain: draggedChain, atLocation: pointInDocument)
					return true
				}
			}
		}
		else if let stepData = pboard.dataForType(QBEStep.dragType) {
			if let step = NSKeyedUnarchiver.unarchiveObjectWithData(stepData) as? QBEStep {
				delegate?.workspaceView(self, didReceiveStep: step, atLocation: pointInDocument)
				return true
			}
		}
		else if let d = pboard.dataForType(MBTableGridColumnDataType) {
			if	let grid = draggingInfo.draggingSource() as? MBTableGrid,
				let dc = grid.dataSource as? QBEDataViewController,
				let indexSet = NSKeyedUnarchiver.unarchiveObjectWithData(d) as? NSIndexSet,
				let names = dc.raster?.columnNames.objectsAtIndexes(indexSet) {
					delegate?.workspaceView(self, didRecieveColumnSet:names, fromDataViewController: dc)
			}
		}
		else if let files: [String] = pboard.propertyListForType(NSFilenamesPboardType) as? [String] {
			delegate?.workspaceView(self, didReceiveFiles: files, atLocation: pointInDocument)
		}
		return true
	}
}