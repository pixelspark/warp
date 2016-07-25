import Cocoa
import WarpCore

@objc protocol QBEDocumentViewDelegate: NSObjectProtocol {
	func documentView(_ view: QBEDocumentView, didSelectTablet: QBETablet?)
	func documentView(_ view: QBEDocumentView, didSelectArrow: QBETabletArrow?)
	func documentView(_ view: QBEDocumentView, wantsZoomToView: NSView)
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

	override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
		return true
	}
	
	func removeAllTablets() {
		subviews.forEach { ($0 as? QBEResizableTabletView)?.removeFromSuperview() }
		self.tabletsChanged()
	}

	private func selectAnArrow(forTablet tablet: QBETablet) {
		if let a = self.flowchartView.selectedArrow as? QBETabletArrow, a.from == tablet || a.to == tablet {
			return
		}
		self.flowchartView.selectedArrow = tablet.arrows.first
	}
	
	func selectTablet(_ tablet: QBETablet?, notifyDelegate: Bool = true) {
		if let t = tablet {
			for sv in subviews {
				if let tv = sv as? QBEResizableTabletView {
					if tv.tabletController.tablet == t {
						selectView(tv, notifyDelegate: notifyDelegate)
						self.selectAnArrow(forTablet: t)
						return
					}
				}
			}
		}
		else {
			selectView(nil)
			self.flowchartView.selectedArrow = nil
		}
	}
	
	func flowchartView(_ view: QBEFlowchartView, didSelectArrow arrow: QBEArrow?) {
		selectView(nil)
		if let tabletArrow = arrow as? QBETabletArrow {
			delegate?.documentView(self, didSelectArrow: tabletArrow)
		}
	}
	
	private func selectView(_ view: QBEResizableTabletView?, notifyDelegate: Bool = true) {
		// Deselect other views
		for sv in subviews {
			if let tv = sv as? QBEResizableTabletView {
				tv.selected = (tv == view)
				if tv == view {
					self.window?.makeFirstResponder(tv.tabletController.view)

					if notifyDelegate {
						delegate?.documentView(self, didSelectTablet: tv.tabletController.tablet)
					}
					self.window?.update()
				}
			}
		}
		
		if view == nil {
			if notifyDelegate {
				delegate?.documentView(self, didSelectTablet: nil)
			}
		}
	}
	
	private func zoomToView(_ view: QBEResizableTabletView) {
		delegate?.documentView(self, wantsZoomToView: view)
	}
	
	func resizableViewWasSelected(_ view: QBEResizableView) {
		flowchartView.selectedArrow = nil
		selectView(view as? QBEResizableTabletView)
	}
	
	func resizableViewWasDoubleClicked(_ view: QBEResizableView) {
		zoomToView(view as! QBEResizableTabletView)
	}
	
	func resizableView(_ view: QBEResizableView, changedFrameTo frame: CGRect) {
		if let tv = view as? QBEResizableTabletView {
			let tablet = tv.tabletController.tablet
			let sizeChanged = tablet?.frame == nil || tablet?.frame!.size.width != frame.size.width || tablet?.frame!.size.height != frame.size.height
			tablet?.frame = frame
			tabletsChanged()
			if tv.selected && sizeChanged {
				tv.scrollToVisible(tv.bounds)
			}
		}
		setNeedsDisplay(self.bounds)
	}
	
	var boundsOfAllTablets: CGRect? { get {
		// Find out the bounds of all tablets combined
		var allBounds: CGRect? = nil
		for vw in subviews {
			if vw !== flowchartView {
				allBounds = allBounds == nil ? vw.frame : allBounds!.union(vw.frame)
			}
		}
		return allBounds
	} }
	
	func reloadData() {
		tabletsChanged()
	}
	
	func resizeDocument() {
		let parentSize = self.superview?.bounds ?? CGRect(x: 0,y: 0,width: 500,height: 500)
		let contentMinSize = boundsOfAllTablets ?? parentSize
		
		// Determine new size of the document
		let margin: CGFloat = 500
		var newBounds = contentMinSize.insetBy(dx: -margin, dy: -margin)
		let offset = CGPoint(x: -newBounds.origin.x, y: -newBounds.origin.y)
		newBounds.offsetInPlace(dx: offset.x, dy: offset.y)
		
		// Translate the 'visible rect' (just like we will translate tablets)
		let newVisible = self.visibleRect.offsetBy(dx: offset.x, dy: offset.y)
		
		// Move all tablets
		for vw in subviews {
			if let tv = vw as? QBEResizableTabletView {
				let tablet = tv.tabletController.tablet
				if let tabletFrame = tablet?.frame {
					tablet?.frame = tabletFrame.offsetBy(dx: offset.x, dy: offset.y)
					tv.frame = (tablet?.frame!)!
				}
			}
		}
		
		// Set new document bounds and scroll to the 'old' location in the new coordinate system
		self.frame = CGRect(x: 0, y: 0, width: newBounds.size.width, height: newBounds.size.height)
		self.scrollToVisible(newVisible)
	}
	
	// Call whenever tablets are added/removed or resized
	private func tabletsChanged() {
		assertMainThread()
		self.flowchartView.frame = self.bounds
		// Update flowchart
		var arrows: [QBEArrow] = []
		for va in subviews {
			if let vc = va as? QBEResizableTabletView {
				arrows += (vc.tabletController.tablet.arrows as [QBEArrow])
			}
		}

		// Apply changes to flowchart and animate them
		let tr = CATransition()
		tr.duration = 0.3
		tr.type = kCATransitionFade
		tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
		self.flowchartView.layer?.add(tr, forKey: kCATransition)
		self.flowchartView.arrows = arrows
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
	
	override func mouseDown(_ theEvent: NSEvent) {
		selectView(nil)
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	func removeTablet(_ tablet: QBETablet, completion: (() -> ())? = nil) {
		for subview in subviews {
			if let rv = subview as? QBEResizableTabletView {
				let ct = rv.tabletController.tablet
				if ct == tablet {
					subview.removeFromSuperview(true) {
						assertMainThread()
						completion?()
						self.tabletsChanged()
					}
					return
				}
			}
		}
	}
	
	func addTablet(_ tabletController: QBETabletViewController, animated: Bool = true, completion: (() -> ())? = nil) {
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
	
	func zoomView(_ view: NSView, completion: (() -> ())? = nil) {
		// First just try to magnify to the tablet
		if self.magnification < 1.0 {
			NSAnimationContext.runAnimationGroup({ (ac) -> Void in
				ac.duration = 0.3
				self.animator().magnify(toFit: view.frame)
			}, completionHandler: {
				// If the tablet is too large, we are still zoomed out a bit. Force zoom in by zooming in on a part of the tablet
				if self.magnification < 1.0 {
					NSAnimationContext.runAnimationGroup({ (ac) -> Void in
						ac.duration = 0.3
						let maxSize = self.bounds
						let frame = view.frame
						let zoomedHeight = min(maxSize.size.height, frame.size.height)
						let zoom = CGRect(x: frame.origin.x, y: frame.origin.y + (frame.size.height - zoomedHeight), width: min(maxSize.size.width, frame.size.width), height: zoomedHeight)
						self.animator().magnify(toFit: zoom)
					}, completionHandler: completion)
				}
			})
		}
		else {
			self.magnifyView(view, completion: completion)
		}
	}
	
	func magnifyView(_ view: NSView?, completion: (() -> ())? = nil) {
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
						oldView.animator().scrollToVisible(oldView.bounds)
					}, completionHandler: completer)
				}
				else {
					completer()
				}
			}
		}
		
		// Un-zoom the old view (if any)
		if let old = self.magnifiedView, let oldRect = self.oldZoomedRect {
			old.autoresizingMask = NSAutoresizingMaskOptions()
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
	
	override func scrollWheel(_ theEvent: NSEvent) {
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
	func workspaceView(_ view: QBEWorkspaceView, didReceiveFiles: [String], atLocation: CGPoint)

	/** A chain was dropped to the workspace. The chain already exists in the workspace. */
	func workspaceView(_ view: QBEWorkspaceView, didReceiveChain: QBEChain, atLocation: CGPoint)

	/** A step was dropped to the workspace. The step is not an existing step instance (e.g. it is created anew). */
	func workspaceView(_ view: QBEWorkspaceView, didReceiveStep: QBEStep, atLocation: CGPoint)

	/** A column set was dropped in the workspace */
	func workspaceView(_ view: QBEWorkspaceView, didReceiveColumnSet:[Column], fromDatasetViewController: QBEDatasetViewController)
}

class QBEWorkspaceView: QBEScrollView {
	private var draggingOver: Bool = false
	weak var delegate: QBEWorkspaceViewDelegate? = nil
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	override func awakeFromNib() {
		register(forDraggedTypes: [NSFilenamesPboardType, QBEOutletView.dragType, MBTableGridColumnDataType, QBEStep.dragType])
	}
	
	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		let pboard = sender.draggingPasteboard()
		
		if let _: [String] = pboard.propertyList(forType: NSFilenamesPboardType) as? [String] {
			draggingOver = true
			setNeedsDisplay(self.bounds)
			return NSDragOperation.copy
		}
		else if let _ = pboard.data(forType: QBEStep.dragType) {
			draggingOver = true
			setNeedsDisplay(self.bounds)
			return NSDragOperation.copy
		}
		else if let _ = pboard.data(forType: QBEOutletView.dragType) {
			draggingOver = true
			setNeedsDisplay(self.bounds)
			return NSDragOperation.link
		}
		else if let _ = pboard.data(forType: MBTableGridColumnDataType) {
			draggingOver = true
			setNeedsDisplay(self.bounds)
			return NSDragOperation.link
		}
		return NSDragOperation()
	}
	
	override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
		return draggingEntered(sender)
	}
	
	override func draggingExited(_ sender: NSDraggingInfo?) {
		draggingOver = false
		setNeedsDisplay(self.bounds)
	}
	
	override func draggingEnded(_ sender: NSDraggingInfo?) {
		draggingOver = false
		setNeedsDisplay(self.bounds)
	}
	
	override func draw(_ dirtyRect: NSRect) {
		if draggingOver {
			NSColor.blue().withAlphaComponent(0.15).set()
		}
		else {
			NSColor.clear().set()
		}
		NSRectFill(dirtyRect)
	}

	@objc override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
		return true
	}
	
	override func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
		let pboard = draggingInfo.draggingPasteboard()
		let pointInWorkspace = self.convert(draggingInfo.draggingLocation(), from: nil)
		let pointInDocument = self.convert(pointInWorkspace, to: self.documentView)
		
		if pboard.data(forType: QBEOutletView.dragType) != nil {
			if let ov = draggingInfo.draggingSource() as? QBEOutletView {
				if let draggedChain = ov.draggedObject as? QBEChain {
					delegate?.workspaceView(self, didReceiveChain: draggedChain, atLocation: pointInDocument)
					return true
				}
			}
		}
		else if let stepDataset = pboard.data(forType: QBEStep.dragType) {
			if let step = NSKeyedUnarchiver.unarchiveObject(with: stepDataset) as? QBEStep {
				delegate?.workspaceView(self, didReceiveStep: step, atLocation: pointInDocument)
				return true
			}
		}
		else if let d = pboard.data(forType: MBTableGridColumnDataType) {
			if	let grid = draggingInfo.draggingSource() as? MBTableGrid,
				let dc = grid.dataSource as? QBEDatasetViewController,
				let indexSet = NSKeyedUnarchiver.unarchiveObject(with: d) as? IndexSet,
				let names = dc.raster?.columns.objectsAtIndexes(indexSet) {
					delegate?.workspaceView(self, didReceiveColumnSet:names, fromDatasetViewController: dc)
			}
		}
		else if let files: [String] = pboard.propertyList(forType: NSFilenamesPboardType) as? [String] {
			delegate?.workspaceView(self, didReceiveFiles: files, atLocation: pointInDocument)
		}
		return true
	}
}
