/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Cocoa
import WarpCore

@objc protocol QBEDocumentViewDelegate: NSObjectProtocol {
	func documentView(_ view: QBEDocumentView, didSelectTablet: QBETablet?)
	func documentView(_ view: QBEDocumentView, didSelectArrow: QBETabletArrow?)
	func documentView(_ view: QBEDocumentView, wantsZoomTo: QBETabletViewController)
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
		// Update 'selected' state on tablet views
		for sv in subviews {
			if let tv = sv as? QBEResizableTabletView {
				tv.selected = (tv == view)
			}
		}

		if let tv = view {
			if notifyDelegate {
				delegate?.documentView(self, didSelectTablet: tv.tabletController.tablet)
			}
			self.window?.makeFirstResponder(tv.tabletController.view)
			self.window?.update()
		}
		else {
			if notifyDelegate {
				delegate?.documentView(self, didSelectTablet: nil)
			}
		}
	}
	
	private func zoomToView(_ view: QBEResizableTabletView) {
		delegate?.documentView(self, wantsZoomTo: view.tabletController)
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
		let parentSize = self.superview?.bounds ?? CGRect(x: 0,y: 0,width: 500, height: 500)
		let contentMinSize = boundsOfAllTablets?.union(parentSize) ?? parentSize
		
		// Determine new size of the document
		let margin: CGFloat = 500
		var newBounds = contentMinSize.insetBy(dx: -margin, dy: -margin)
		let offset = CGPoint(x: -newBounds.origin.x, y: -newBounds.origin.y)
		newBounds = newBounds.offsetBy(dx: offset.x, dy: offset.y)
		
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
		tr.type = CATransitionType.fade
		tr.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
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
	
	override func mouseDown(with theEvent: NSEvent) {
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

	override func draw(_ dirtyRect: NSRect) {
		NSColor.clear.set()
		dirtyRect.fill()
	}
}

class QBEScrollView: NSScrollView {
	required init?(coder: NSCoder) {
		super.init(coder: coder)
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
	func workspaceView(_ view: QBEWorkspaceView, didReceiveColumnSet:OrderedSet<Column>, fromDatasetViewController: QBEDatasetViewController)
}

class QBEWorkspaceView: QBEScrollView {
	private var draggingOver: Bool = false
	weak var delegate: QBEWorkspaceViewDelegate? = nil
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	override func awakeFromNib() {
		registerForDraggedTypes([NSPasteboard.PasteboardType.filePromise, QBEOutletView.dragType, NSPasteboard.PasteboardType(MBTableGridColumnDataType), QBEStep.dragType])
	}
	
	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		let pboard = sender.draggingPasteboard
		
		if let _: [String] = pboard.propertyList(forType: NSPasteboard.PasteboardType.filePromise) as? [String] {
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
		else if let _ = pboard.data(forType: NSPasteboard.PasteboardType(MBTableGridColumnDataType)) {
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
	
	override func draggingEnded(_ sender: NSDraggingInfo) {
		draggingOver = false
		setNeedsDisplay(self.bounds)
	}
	
	override func draw(_ dirtyRect: NSRect) {
		if draggingOver {
			NSColor.blue.withAlphaComponent(0.15).set()
		}
		else {
			NSColor.clear.set()
		}
		dirtyRect.fill()
	}

	@objc override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
		return true
	}
	
	override func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
		let pboard = draggingInfo.draggingPasteboard
		let pointInWorkspace = self.convert(draggingInfo.draggingLocation, from: nil)
		let pointInDocument = self.convert(pointInWorkspace, to: self.documentView)
		
		if pboard.data(forType: QBEOutletView.dragType) != nil {
			if let ov = draggingInfo.draggingSource as? QBEOutletView {
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
		else if let d = pboard.data(forType: NSPasteboard.PasteboardType(MBTableGridColumnDataType)) {
			if	let grid = draggingInfo.draggingSource as? MBTableGrid,
				let dc = grid.dataSource as? QBEDatasetViewController,
				let indexSet = NSKeyedUnarchiver.unarchiveObject(with: d) as? IndexSet,
				let nsa = dc.raster?.columns {
					let names = OrderedSet(Array(nsa).objectsAtIndexes(indexSet))
					delegate?.workspaceView(self, didReceiveColumnSet:names, fromDatasetViewController: dc)
			}
		}
		else if let files: [String] = pboard.propertyList(forType: NSPasteboard.PasteboardType.filePromise) as? [String] {
			delegate?.workspaceView(self, didReceiveFiles: files, atLocation: pointInDocument)
		}
		return true
	}
}
