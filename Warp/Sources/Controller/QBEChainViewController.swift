/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Cocoa
import WarpCore

@objc internal protocol QBEChainViewDelegate: NSObjectProtocol {
	func chainView(_ view: QBEChainView, shouldInterceptEvent: NSEvent, forView: NSView) -> Bool
}

class QBEChainView: NSView {
	@IBOutlet weak var delegate: QBEChainViewDelegate?

	override var acceptsFirstResponder: Bool { get { return true } }

	override func becomeFirstResponder() -> Bool {
		return true
	}

	override var allowsVibrancy: Bool { return false }

	override func hitTest(_ point: NSPoint) -> NSView? {
		if let d = self.delegate,
			let p = super.hitTest(point),
			let ev = self.window!.currentEvent,
			d.chainView(self, shouldInterceptEvent: ev, forView: p) {
			return nil
		}
		return super.hitTest(point)
	}
}

protocol QBEChainViewControllerDelegate: NSObjectProtocol {
	/** Called when the chain view wants the delegate to present a configurator for a step. If 'necessary' is set to true,
	the step needs configuration right now in order to work. */
	func chainView(_ view: QBEChainViewController, configureStep: QBEStep?, necessary: Bool, delegate: QBESentenceViewDelegate)

	/** Called when the chain view wants the delegate to present a value for editing. */
	func chainView(_ view: QBEChainViewController, editValue: Value, changeable: Bool, callback: @escaping (Value) -> ())
	
	/** Called when the user closes a chain view. If it returns false, the removal is blocked. */
	func chainViewDidClose(_ view: QBEChainViewController) -> Bool
	
	/** Called when the chain has changed */
	func chainViewDidChangeChain(_ view: QBEChainViewController)

	/** Called when the chain view wants to export the chain (e.g. what would normally be accomplished by dragging out 
	the outlet to another place outside the tablet). */
	func chainView(_ view: QBEChainViewController, exportChain: QBEChain)
}

internal extension NSViewController {
	internal func showTip(_ message: String, atView: NSView) {
		assertMainThread()
		
		if let vc = self.storyboard?.instantiateController(withIdentifier: "tipController") as? QBETipViewController {
			vc.message = message
			self.presentViewController(vc, asPopoverRelativeTo: atView.bounds, of: atView, preferredEdge: NSRectEdge.maxY, behavior: NSPopoverBehavior.transient)
		}
	}
}

internal enum QBEEditingMode {
	case notEditing
	case enablingEditing
	case editing(identifiers: Set<Column>?, editingRaster: Raster)
}

@objc class QBEChainViewController: NSViewController, QBESuggestionsViewDelegate, QBESentenceViewDelegate,
	QBEDatasetViewDelegate, QBEStepsControllerDelegate, JobDelegate, QBEOutletViewDelegate, QBEOutletDropTarget,
	QBEFilterViewDelegate, QBEExportViewDelegate, QBEAlterTableViewDelegate,
	QBEColumnViewDelegate, QBEChainViewDelegate, QBEJSONViewControlllerDelegate {

	private var suggestions: Future<[QBEStep]>?
	private let calculator: QBECalculator = QBECalculator(incremental: true)
	private var dataViewController: QBEDatasetViewController?
	private var stepsViewController: QBEStepsViewController?
	private var outletDropView: QBEOutletDropView!
	private var hasFullDataset = false
	private var filterControllerJob: Job? = nil

	@IBOutlet var outletView: QBEOutletView!
	weak var delegate: QBEChainViewControllerDelegate?
	
	@IBOutlet var addStepMenu: NSMenu?
	
	internal var useFullDataset: Bool = false {
		didSet {
			if useFullDataset {
				calculate()
			}
		}
	}

	internal var editingMode: QBEEditingMode = .notEditing {
		didSet {
			assertMainThread()
			self.updateView()
		}
	}

	internal var supportsEditing: Bool {
		if let r = self.calculator.currentRaster?.result {
			if case .failure(_) = r {
				return false
			}

			if let _ = self.currentStep?.mutableDataset {
				return true
			}
		}
		return false
	}
	
	internal var locale: Language { get {
		return QBEAppDelegate.sharedInstance.locale ?? Language()
	} }
	
	dynamic var currentStep: QBEStep? {
		didSet {
			self.editingMode = .notEditing
			if let s = currentStep {
				self.previewStep = nil				
				delegate?.chainView(self, configureStep: s, necessary: false, delegate: self)
			}
			else {
				delegate?.chainView(self, configureStep: nil, necessary: false, delegate: self)
				self.presentDataset(nil)
			}
			
			self.stepsViewController?.currentStep = currentStep
			self.stepsChanged()
		}
	}

	public var fulltextSearchQuery: String {
		get {
			if let c = currentStep as? QBESearchStep {
				return c.query
			}
			return ""
		}

		set {
			if let c = currentStep as? QBESearchStep {
				if newValue.isEmpty {
					self.removeStep(self)
				}
				else {
					if c.query != newValue {
						c.query = newValue
						calculate()
					}
				}
			}
			else {
				if !newValue.isEmpty {
					let fs = QBESearchStep()
					fs.query = newValue
					self.pushStep(fs)
					calculate()
				}
			}
		}
	}

	private var viewFilters: [Column:FilterSet]  {
		get {
			if let c = currentStep as? QBEFilterSetStep {
				return c.filterSet
			}
			return [:]
		}

		set {
			if let c = currentStep as? QBEFilterSetStep {
				if newValue.isEmpty {
					self.removeStep(self)
				}
				else {
					c.filterSet = newValue
				}
			}
			else {
				if !newValue.isEmpty {
					let fs = QBEFilterSetStep()
					fs.filterSet = newValue
					self.pushStep(fs)
				}
			}
		}
	}
	
	var previewStep: QBEStep? {
		didSet {
			self.editingMode = .notEditing
			if previewStep != currentStep?.previous {
				previewStep?.previous = currentStep?.previous
			}
		}
	}
	
	var chain: QBEChain? {
		didSet {
			self.currentStep = chain?.head
		}
	}

	var selected: Bool = false { didSet {
		self.stepsViewController?.active = selected
		if selected {
			delegate?.chainView(self, configureStep: currentStep, necessary: false, delegate: self)
		}
	} }

	override func viewDidLoad() {
		super.viewDidLoad()
		(self.view as! QBEChainView).delegate = self
		outletView!.delegate = self
		outletDropView = QBEOutletDropView(frame: self.view.bounds)
		outletDropView.translatesAutoresizingMaskIntoConstraints = false
		outletDropView.delegate = self
		self.view.addSubview(self.outletDropView, positioned: NSWindowOrderingMode.above, relativeTo: nil)
		self.view.addConstraints([
			NSLayoutConstraint(item: outletDropView, attribute: NSLayoutAttribute.top, relatedBy: NSLayoutRelation.equal, toItem: self.view, attribute: NSLayoutAttribute.top, multiplier: 1.0, constant: 0.0),
			NSLayoutConstraint(item: outletDropView, attribute: NSLayoutAttribute.bottom, relatedBy: NSLayoutRelation.equal, toItem: self.view, attribute: NSLayoutAttribute.bottom, multiplier: 1.0, constant: 0.0),
			NSLayoutConstraint(item: outletDropView, attribute: NSLayoutAttribute.left, relatedBy: NSLayoutRelation.equal, toItem: self.view, attribute: NSLayoutAttribute.left, multiplier: 1.0, constant: 0.0),
			NSLayoutConstraint(item: outletDropView, attribute: NSLayoutAttribute.right, relatedBy: NSLayoutRelation.equal, toItem: self.view, attribute: NSLayoutAttribute.right, multiplier: 1.0, constant: 0.0)
		])
	}
	
	func receiveDropFromOutlet(_ draggedObject: AnyObject?) {
		// Present a drop down menu and add steps depending on the option selected by the user.
		class QBEDropChainAction: NSObject {
			let view: QBEChainViewController
			let otherChain: QBEChain

			init(view: QBEChainViewController, chain: QBEChain) {
				self.otherChain = chain
				self.view = view
			}

			@objc func unionChains(_ sender: AnyObject) {
				self.view.suggestSteps([QBEMergeStep(previous: nil, with: self.otherChain)])
			}


			@objc func uploadDataset(_ sender: AnyObject) {
				if let sourceStep = self.otherChain.head, let destStep = self.view.currentStep, let destMutable = destStep.mutableDataset, destMutable.canPerformMutation(.import(data: RasterDataset(), withMapping: [:])) {
					let uploadView = self.view.storyboard?.instantiateController(withIdentifier: "uploadDataset") as! QBEUploadViewController
					uploadView.sourceStep = sourceStep
					uploadView.targetStep = destStep
					uploadView.afterSuccessfulUpload = {
						asyncMain {
							self.view.calculate()
						}
					}
					self.view.presentViewControllerAsSheet(uploadView)
				}
			}

			/** Add a tablet to the document containing a raster table containing training data for a classifier on the source
			data set. */
			@objc private func joinWithClassifier(_ sender: NSObject) {
				asyncMain {
					let classifyStep = QBEClassifierStep(previous: nil)
					classifyStep.right = self.otherChain
					self.view.suggestSteps([classifyStep])
				}
			}

			@objc func joinChains(_ sender: AnyObject) {
				let job = Job(.userInitiated)
				// Generate sensible join options
				self.view.calculator.currentRaster?.get(job) { (r) -> () in
					r.maybe { (raster) -> () in
						let myColumns = raster.columns

						self.otherChain.head?.fullDataset(job) { (otherDatasetFallible) -> () in
							otherDatasetFallible.maybe { (otherDataset) -> () in
								otherDataset.columns(job) { (otherColumnsFallible) -> () in
									otherColumnsFallible.maybe { (otherColumns) -> () in
										let mySet = Set(myColumns)
										let otherSet = Set(otherColumns)

										asyncMain {
											var configureStep: QBEStep? = nil
											var joinSteps: [QBEStep] = []

											// If the other data set contains exactly the same columns as we do, or one is a subset of the other, propose a merge
											if !mySet.isDisjoint(with: otherSet) {
												let overlappingColumns = mySet.intersection(otherSet)

												// Create a join step for each column name that appears both left and right
												for overlappingColumn in overlappingColumns {
													let joinStep = QBEJoinStep(previous: nil)
													joinStep.right = self.otherChain
													joinStep.condition = Comparison(first: Sibling(overlappingColumn), second: Foreign(overlappingColumn), type: Binary.equal)
													joinSteps.append(joinStep)
												}
											}
											else {
												if joinSteps.isEmpty {
													let js = QBEJoinStep(previous: nil)
													js.right = self.otherChain
													js.condition = Literal(Value(false))
													joinSteps.append(js)
													configureStep = js
												}
											}

											self.view.suggestSteps(joinSteps)

											if let cs = configureStep {
												self.view.delegate?.chainView(self.view, configureStep: cs, necessary: true, delegate: self.view)
											}
										}
									}
								}
							}
						}
					}
				}
			}

			func presentMenu() {
				let dropMenu = NSMenu()
				dropMenu.autoenablesItems = false
				let joinItem = NSMenuItem(title: NSLocalizedString("Join data set to this data set", comment: ""), action: #selector(QBEDropChainAction.joinChains(_:)), keyEquivalent: "")
				joinItem.target = self
				dropMenu.addItem(joinItem)

				let classifyItem = NSMenuItem(title: "Add data using AI".localized, action: #selector(QBEDropChainAction.joinWithClassifier(_:)), keyEquivalent: "")
				classifyItem.target = self
				dropMenu.addItem(classifyItem)

				let unionItem = NSMenuItem(title: NSLocalizedString("Append data set to this data set", comment: ""), action: #selector(QBEDropChainAction.unionChains(_:)), keyEquivalent: "")
				unionItem.target = self
				dropMenu.addItem(unionItem)

				if let destStep = self.view.currentStep, let destMutable = destStep.mutableDataset, destMutable.canPerformMutation(.import(data: RasterDataset(), withMapping: [:])) {
					dropMenu.addItem(NSMenuItem.separator())
					let createItem = NSMenuItem(title: destStep.sentence(self.view.locale, variant: .write).stringValue + "...", action: #selector(QBEDropChainAction.uploadDataset(_:)), keyEquivalent: "")
					createItem.target = self
					dropMenu.addItem(createItem)
				}

				NSMenu.popUpContextMenu(dropMenu, with: NSApplication.shared().currentEvent!, for: self.view.view)
			}
		}

		if let myChain = chain {
			if let otherChain = draggedObject as? QBEChain {
				if otherChain == myChain {
					// Drop on self, just ignore
				}
				else if Array(otherChain.recursiveDependencies).map({$0.dependsOn}).contains(myChain) {
					// This would introduce a loop, don't do anything.
					NSAlert.showSimpleAlert("The data set cannot be linked to this data set".localized, infoText: "Linking the data set to this data set would introduce a loop where the outcome of a calculation would depend on itself.".localized, style: .critical, window: self.view.window)
				}
				else {
					let ca = QBEDropChainAction(view: self, chain: otherChain)
					ca.presentMenu()
				}
			}
		}
	}

	func outletViewWasClicked(_ view: QBEOutletView) {
		if let c = self.chain {
			self.delegate?.chainView(self, exportChain: c)
		}
		view.draggedObject = nil
	}
	
	func outletViewDidEndDragging(_ view: QBEOutletView) {
		view.draggedObject = nil
	}

	private func exportToFile(_ url: URL, callback: @escaping (Error?) -> ()) {
		let writerType: QBEFileWriter.Type
		let ext = url.pathExtension
		writerType = QBEFactory.sharedInstance.fileWriterForType(ext) ?? QBECSVWriter.self

		let title = self.chain?.tablet?.displayName ?? NSLocalizedString("Warp data", comment: "")
		let s = QBEExportStep(previous: currentStep, writer: writerType.init(locale: self.locale, title: title), file: QBEFileReference.absolute(url))

		if let editorController = self.storyboard?.instantiateController(withIdentifier: "exportEditor") as? QBEExportViewController {
			editorController.step = s
			editorController.delegate = self
			editorController.completionCallback = callback
			editorController.locale = self.locale
			self.presentViewControllerAsSheet(editorController)
		}
	}

	func exportView(_ view: QBEExportViewController, didAddStep step: QBEExportStep) {
		chain?.insertStep(step, afterStep: self.currentStep)
		self.currentStep = step
		stepsChanged()
	}

	func outletView(_ view: QBEOutletView, didDropAtURL url: URL, callback: @escaping (Error?) -> ()) {
		if url.isDirectory {
			// Ask for a file rather than a directory
			var exts: [String: String] = [:]
			for ext in QBEFactory.sharedInstance.fileExtensionsForWriting {
				let writer = QBEFactory.sharedInstance.fileWriterForType(ext)!
				exts[ext] = writer.explain(ext, locale: self.locale)
			}

			let no = QBEFilePanel(allowedFileTypes: exts)
			no.askForSaveFile(self.view.window!) { (fileFallible) in
				fileFallible.maybe { (url) in
					self.exportToFile(url, callback: callback)
				}
			}
		}
		else {
			self.exportToFile(url, callback: callback)
		}
	}

	func outletViewWillStartDragging(_ view: QBEOutletView) {
		view.draggedObject = self.chain
	}
	
	@IBAction func clearAllFilters(_ sender: NSObject) {
		self.viewFilters.removeAll()
		calculate()
	}
	
	@IBAction func makeAllFiltersPermanent(_ sender: NSObject) {
		var args: [Expression] = []
		
		for (column, filterSet) in self.viewFilters {
			args.append(filterSet.expression.expressionReplacingIdentityReferencesWith(Sibling(column)))
		}
		
		self.viewFilters.removeAll()
		if args.count > 0 {
			suggestSteps([QBEFilterStep(previous: currentStep, condition: args.count > 1 ? Call(arguments: args, type: Function.And) : args[0])])
		}
	}
	
	func filterView(_ view: QBEFilterViewController, didChangeFilter filter: FilterSet?) {
		assertMainThread()
		
		if let c = view.column {
			// If filter is nil, the filter is removed from the set of view filters
			self.viewFilters[c] = filter
			delegate?.chainView(self, configureStep: currentStep, necessary: false, delegate: self)
			calculate()
		}
	}
	
	/** Present the given data set in the data grid. This is called by currentStep.didSet as well as previewStep.didSet.
	The data from the previewed step takes precedence. */
	private func presentDataset(_ data: Dataset?) {
		assertMainThread()
		
		if let d = data {
			if self.dataViewController != nil {
				let job = Job(.userInitiated)
				
				job.async {
					d.raster(job, callback: { (raster) -> () in
						asyncMain {
							self.presentRaster(raster)
						}
					})
				}
			}
		}
		else {
			presentRaster(nil)
		}
	}

	private func presentRaster(_ fallibleRaster: Fallible<Raster>) {
		assertMainThread()
		
		switch fallibleRaster {
			case .success(let raster):
				self.presentRaster(raster)
			
			case .failure(let errorMessage):
				self.presentRaster(nil)
				self.dataViewController?.errorMessage = errorMessage
		}

		self.useFullDataset = false
		self.updateView()
	}
	
	private func presentRaster(_ raster: Raster?) {
		if let dataView = self.dataViewController {
			dataView.raster = raster
			hasFullDataset = (raster != nil && useFullDataset)

			// Fade any changes in smoothly
			if raster == nil {
				let tr = CATransition()
				tr.duration = 0.3
				tr.type = kCATransitionFade
				tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
				self.outletView.layer?.add(tr, forKey: kCATransition)
				self.dataViewController?.errorMessage = nil
			}

			self.updateView()
			
			if raster != nil && raster!.rowCount > 0 && !useFullDataset {
				if let toolbar = self.view.window?.toolbar {
					toolbar.validateVisibleItems()
					self.view.window?.update()
					QBESettings.sharedInstance.showTip("workingSetTip") {
						for item in toolbar.items {
							if item.action == #selector(QBEChainViewController.toggleFullDataset(_:)) {
								if let vw = item.view {
									self.showTip(NSLocalizedString("By default, Warp shows you a small part of the data. Using this button, you can calculate the full result.",comment: "Working set selector tip"), atView: vw)
								}
							}
						}
					}
				}
			}
		}
	}
	
	func calculate() {
		assertMainThread()

		let job = Job(.userInitiated)
		job.addObserver(self)

		if let ch = chain {
			if ch.isPartOfDependencyLoop {
				if let w = self.view.window {
					// TODO: make this message more helpful (maybe even indicate the offending step)
					let a = NSAlert()
					a.messageText = NSLocalizedString("The calculation steps for this data set form a loop, and therefore no data can be calculated.", comment: "")
					a.alertStyle = NSAlertStyle.warning
					a.beginSheetModal(for: w, completionHandler: nil)
				}
				calculator.cancel()
				refreshDataset(incremental: false)
				self.updateView()
			}
			else {
				if let s = currentStep {
					var parameters = calculator.parameters
					parameters.desiredExampleRows = QBESettings.sharedInstance.exampleMaximumRows
					parameters.maximumExampleTime = QBESettings.sharedInstance.exampleMaximumTime
					calculator.parameters = parameters
					
					let sourceStep = previewStep ?? s
					
					// Start calculation
					if useFullDataset {
						self.presentDataset(nil)
						calculator.calculate(sourceStep, fullDataset: useFullDataset, maximumTime: nil, job: job, callback: throttle(interval: 1.0, queue: DispatchQueue.main) { streamStatus in
							asyncMain {
								self.refreshDataset(incremental: true)
								self.updateView()

								if streamStatus == .finished {
									self.useFullDataset = false
								}
							}
						})
					}
					else {
						calculator.calculateExample(sourceStep, maximumTime: nil, job: job, callback: throttle(interval: 0.5, queue: DispatchQueue.main) {
							asyncMain {
								self.refreshDataset(incremental: true)
								self.updateView()
							}
						})
						self.refreshDataset(incremental: false)
					}
				}
				else {
					calculator.cancel()
					refreshDataset(incremental: false)
					self.updateView()
				}
			}
		}

		self.updateView()
		self.view.window?.update() // So that the 'cancel calculation' toolbar button autovalidates
	}
	
	@IBAction func cancelCalculation(_ sender: NSObject) {
		assertMainThread()
		if calculator.calculating {
			calculator.cancel()
			self.presentRaster(.failure(NSLocalizedString("The calculation was cancelled.", comment: "")))
		}
		self.useFullDataset = false
		self.view.window?.update()
		self.view.window?.toolbar?.validateVisibleItems()
	}
	
	private func refreshDataset(incremental: Bool) {
		if !incremental {
			self.presentDataset(nil)
		}
		
		calculator.currentRaster?.get(Job(.userInitiated)) { (fallibleRaster) -> () in
			asyncMain {
				self.presentRaster(fallibleRaster)
				self.view.window?.toolbar?.validateVisibleItems()
				self.view.window?.update()
			}
		}
		self.view.window?.toolbar?.validateVisibleItems()
		self.view.window?.update() // So that the 'cancel calculation' toolbar button autovalidates
	}
	
	@objc func job(_ job: AnyObject, didProgress: Double) {
		asyncMain {
			self.updateView()
		}
	}
	
	func stepsController(_ vc: QBEStepsViewController, didSelectStep step: QBEStep) {
		if currentStep != step {
			currentStep = step
			stepsChanged()
			updateView()
			calculate()
		}
	}
	
	func stepsController(_ vc: QBEStepsViewController, didRemoveStep step: QBEStep) {
		if step == currentStep {
			popStep()
		}
		remove(step)
		stepsChanged()
		updateView()
		calculate()
		
		(undo?.prepare(withInvocationTarget: self) as? QBEChainViewController)?.addStep(step)
		undo?.setActionName(NSLocalizedString("Remove step", comment: ""))

		if let c = chain {
			QBEChangeNotification.broadcastChange(c)
		}
	}
	
	func stepsController(_ vc: QBEStepsViewController, didMoveStep: QBEStep, afterStep: QBEStep?) {
		if didMoveStep == currentStep {
			popStep()
		}
		
		// Pull the step from its current location
		var after = afterStep
		
		// If we are inserting after nil, this means inserting as first
		if after == nil {
			remove(didMoveStep)
			
			// Insert at beginning
			if let head = chain?.head {
				after = head
				while after!.previous != nil {
					after = after!.previous
				}
			}
			
			if after == nil {
				// this is the only step
				chain?.head = didMoveStep
			}
			else {
				// insert at beginning
				after!.previous = didMoveStep
			}
		}
		else {
			if after != didMoveStep {
				remove(didMoveStep)
				didMoveStep.next = after?.next
				after?.next?.previous = didMoveStep
				didMoveStep.previous = after
				
				if let h = chain?.head, after == h {
					chain?.head = didMoveStep
				}
			}
		}

		stepsChanged()
		updateView()
		calculate()

		if let c = chain {
			QBEChangeNotification.broadcastChange(c)
		}
	}
	
	func stepsController(_ vc: QBEStepsViewController, didInsertStep step: QBEStep, afterStep: QBEStep?) {
		chain?.insertStep(step, afterStep: afterStep)
		stepsChanged()

		if let c = chain {
			QBEChangeNotification.broadcastChange(c)
		}
	}
	
	// Used for undo for remove step
	@objc func addStep(_ step: QBEStep) {
		chain?.insertStep(step, afterStep: nil)
		stepsChanged()

		if let c = chain {
			QBEChangeNotification.broadcastChange(c)
		}
	}

	func chainView(_ cv: QBEChainView, shouldInterceptEvent event: NSEvent, forView view: NSView) -> Bool {
		if event.type == .leftMouseDown {
			if let s = self.stepsViewController?.view, view == s || view.isDescendant(of: s) {
				asyncMain {
					self.delegate?.chainView(self, configureStep: self.currentStep, necessary: false, delegate: self)
				}
			}
		}
		return false
	}

	func dataViewDidDeselectValue(_ view: QBEDatasetViewController) {
		if let s = currentStep {
			delegate?.chainView(self, configureStep: s, necessary: false, delegate: self)
		}
	}
	
	func dataView(_ view: QBEDatasetViewController, didSelectValue value: Value, changeable: Bool) {
		var lastValueReceived = value
		self.delegate?.chainView(self, editValue: value, changeable: changeable, callback: { (newValue) in
			if newValue != lastValueReceived {
				lastValueReceived = newValue
				self.dataViewController?.changeSelectedValue(newValue)
			}
		})
	}
	
	func dataView(_ view: QBEDatasetViewController, didOrderColumns columns: OrderedSet<Column>, toIndex: Int) -> Bool {
		// Construct a new column ordering
		if let r = view.raster, toIndex >= 0 && toIndex < r.columns.count {
			/* If the current step is already a sort columns step, do not create another one; instead create a new sort
			step that combines both sorts. This cannot be implemented as QBESortColumnStep.mergeWith, because from there
			the full list of columns is not available. */
			if let sortStep = self.currentStep as? QBESortColumnsStep {
				let previous = sortStep.previous
				self.remove(sortStep)
				self.currentStep = previous

				var allColumns = r.columns
				let beforeColumn = allColumns[toIndex]
				columns.forEach { allColumns.remove($0) }
				if let beforeIndex = allColumns.index(of: beforeColumn) {
					allColumns.insert(contentsOf: columns, at: beforeIndex)
				}
				pushStep(QBESortColumnsStep(previous: previous, sortColumns: allColumns, before: nil))
			}
			else {
				if toIndex < r.columns.count {
					pushStep(QBESortColumnsStep(previous: self.currentStep, sortColumns: columns, before: r.columns[toIndex]))
				}
				else {
					pushStep(QBESortColumnsStep(previous: self.currentStep, sortColumns: columns, before: nil))
				}
			}
			calculate()
			return true
		}
		return false
	}

	/** This delegate method is called by the data view whenever a value is added using the template new row/column. */
	func dataView(_ view: QBEDatasetViewController, addValue value: Value, inRow: Int?, column: Int?, callback: @escaping (Bool) -> ()) {
		var value = value
		suggestions?.cancel()
		let job = Job(.userInitiated)

		switch self.editingMode {
		case .notEditing:
			if let row = inRow {
				// If we are not editing the source data, the only thing that can be done is calculate a new column
				calculator.currentRaster?.get(job) { (fallibleRaster) -> () in
					fallibleRaster.maybe { (raster) -> () in
						let targetColumn = Column.defaultNameForNewColumn(raster.columns)

						self.suggestions = Future<[QBEStep]>({(job, callback) -> () in
							job.async {
								let expressions = QBECalculateStep.suggest(change: nil, toValue: value, inRaster: raster, row: row, column: nil, locale: self.locale, job: job)
								callback(expressions.map({QBECalculateStep(previous: self.currentStep, targetColumn: targetColumn, function: $0)}))
							}
						}, timeLimit: 5.0)

						self.suggestions!.get(job) {(steps) -> () in
							asyncMain {
								self.suggestSteps(steps)
							}
						}
					}
				}
			}

		case .editing(identifiers: _, editingRaster: let editingRaster):
			// If a formula was typed in, calculate the result first
			if let f = Formula(formula: value.stringValue ?? "", locale: locale), !(f.root is Literal) && !(f.root is Identity) {
				let row = inRow == nil ? Row() : editingRaster[inRow!]
				value = f.root.apply(row, foreign: nil, inputValue: nil)
			}

			// If we are in editing mode, the new value will actually be added to the source data set.
			if let md = self.currentStep?.mutableDataset {
				/* Check to see if we are adding a new column. Note that we're using the editing raster here. Previously,
				the mutable data set would be queried for its columns here. This however provides isues with databases 
				that do not have fixed column sets (e.g. NoSQL databases): after adding a column, the set of columns would
				still be empty, and cause another 'add column' mutation to be performed, resulting in an infinite loop. */
				if let cn = column, cn >= 0 && cn < editingRaster.columns.count {
					// Column exists, just insert a row
					let columnName = editingRaster.columns[cn]
					let row = Row([value], columns: [columnName])
					let mutation = DatasetMutation.insert(row: row)
					md.performMutation(mutation, job: job) { result in
						switch result {
						case .success:
							/* The mutation has been performed on the source data, now perform it on our own
							temporary raster as well. We could also call self.calculate() here, but that takes
							a while, and we would lose our current scrolling position, etc. */
							RasterMutableDataset(raster: editingRaster).performMutation(mutation, job: job) { result in
								QBEChangeNotification.broadcastChange(self.chain!)
								asyncMain {
									self.presentRaster(editingRaster)
									self.dataViewController?.sizeColumnToFit(columnName)
									callback(true)
								}
							}
							break

						case .failure(let e):
							asyncMain {
								callback(false)
								NSAlert.showSimpleAlert(NSLocalizedString("Cannot create new row.", comment: ""), infoText: e, style: .critical, window: self.view.window)
							}
						}
					}
				}
				else {
					// need to add a new column first
					var columns = editingRaster.columns
					let newColumnName = Column.defaultNameForNewColumn(columns)
					columns.append(newColumnName)
					let mutation = DatasetMutation.alter(DatasetDefinition(columns: columns))
					md.performMutation(mutation, job: job, callback: once { result in
						switch result {
						case .success:
							/* The mutation has been performed on the source data, now perform it on our own
							temporary raster as well. We could also call self.calculate() here, but that takes
							a while, and we would lose our current scrolling position, etc. */
							RasterMutableDataset(raster: editingRaster).performMutation(mutation, job: job) { result in
								QBEChangeNotification.broadcastChange(self.chain!)

								asyncMain {
									self.presentRaster(editingRaster)

									if let rn = inRow {
										self.dataView(view, didChangeValue: Value.empty, toValue: value, inRow: rn, column: columns.count-1)
										self.dataViewController?.sizeColumnToFit(newColumnName)
										callback(true)
									}
									else {
										// We're also adding a new row
										self.dataView(view, addValue: value, inRow: nil, column: columns.count-1) { b in
											asyncMain {
												self.dataViewController?.sizeColumnToFit(newColumnName)
												callback(b)
											}
										}
									}
								}
							}

						case .failure(let e):
							asyncMain {
								callback(false)
								NSAlert.showSimpleAlert(NSLocalizedString("Cannot create new column.", comment: ""), infoText: e, style: .critical, window: self.view.window)
							}
						}
					})
				}
			}

		default:
			return
		}
	}

	private func removeRowsPermanently(_ rows: [Int]) {
		let errorMessage = rows.count > 1 ? "Cannot remove these rows".localized : "Cannot remove this row".localized

		// In editing mode, we perform the edit on the mutable data set
		if let md = self.currentStep?.mutableDataset, case .editing(identifiers: let identifiers, editingRaster: let editingRaster) = self.editingMode {
			let job = Job(.userInitiated)
			md.data(job) { result in
				// Does the data set support deleting by row number, or do we edit by key?
				let removeMutation = DatasetMutation.remove(rows: rows)
				if md.canPerformMutation(removeMutation) {
					job.async {
						md.performMutation(removeMutation, job: job) { result in
							switch result {
							case .success:
								/* The mutation has been performed on the source data, now perform it on our own
								temporary raster as well. We could also call self.calculate() here, but that takes
								a while, and we would lose our current scrolling position, etc. */
								RasterMutableDataset(raster: editingRaster).performMutation(removeMutation, job: job) { result in
									QBEChangeNotification.broadcastChange(self.chain!)
									asyncMain {
										self.presentRaster(editingRaster)
									}
								}
								break

							case .failure(let e):
								asyncMain {
									NSAlert.showSimpleAlert(errorMessage, infoText: e, style: .critical, window: self.view.window)
								}
							}
						}
					}
				}
				else {
					if let ids = identifiers {
						var keys: [[Column: Value]] = []
						for rowNumber in rows {
							// Create key
							let row = editingRaster[rowNumber]
							var key: [Column: Value] = [:]
							for identifyingColumn in ids {
								key[identifyingColumn] = row[identifyingColumn]
							}
							keys.append(key)
						}

						let deleteMutation = DatasetMutation.delete(keys: keys)

						job.async {
							md.performMutation(deleteMutation, job: job) { result in
								switch result {
								case .success():
									/* The mutation has been performed on the source data, now perform it on our own
									temporary raster as well. We could also call self.calculate() here, but that takes
									a while, and we would lose our current scrolling position, etc. */
									RasterMutableDataset(raster: editingRaster).performMutation(deleteMutation, job: job) { result in
										QBEChangeNotification.broadcastChange(self.chain!)
										asyncMain {
											self.presentRaster(editingRaster)
										}
									}
									break

								case .failure(let e):
									asyncMain {
										NSAlert.showSimpleAlert(errorMessage, infoText: e, style: .critical, window: self.view.window)
									}
								}
							}
						}
					}
					else {
						// We cannot change the data because we cannot do it by row number and we don't have a sure primary key
						// TODO: ask the user what key to use ("what property makes each row unique?")
						asyncMain {
							NSAlert.showSimpleAlert(errorMessage, infoText: "There is not enough information to be able to distinguish rows.".localized, style: .critical, window: self.view.window)
						}
					}
				}
			}
		}
	}

	private func editValue(_ oldValue: Value, toValue: Value, inRow: Int, column: Int, identifiers: Set<Column>?) {
		var toValue = toValue
		let errorMessage = String(format: NSLocalizedString("Cannot change '%@' to '%@'", comment: ""), oldValue.stringValue ?? "", toValue.stringValue ?? "")

		// In editing mode, we perform the edit on the mutable data set
		if let md = self.currentStep?.mutableDataset, case .editing(identifiers:_, editingRaster: let editingRaster) = self.editingMode {
			// If a formula was typed in, calculate the result first
			if let f = Formula(formula: toValue.stringValue ?? "", locale: locale), !(f.root is Literal) && !(f.root is Identity) {
				toValue = f.root.apply(editingRaster[inRow], foreign: nil, inputValue: oldValue)
			}

			let job = Job(.userInitiated)
			md.data(job) { result in
				switch result {
				case .success(let data):
					data.columns(job) { result in
						switch result {
						case .success(let columns):
							// Does the data set support editing by row number, or do we edit by key?
							let editMutation = DatasetMutation.edit(row: inRow, column: columns[column], old: oldValue, new: toValue)
							if md.canPerformMutation(editMutation) {
								job.async {
									md.performMutation(editMutation, job: job) { result in
										switch result {
										case .success:
											/* The mutation has been performed on the source data, now perform it on our own
											temporary raster as well. We could also call self.calculate() here, but that takes
											a while, and we would lose our current scrolling position, etc. */
												RasterMutableDataset(raster: editingRaster).performMutation(editMutation, job: job) { result in
													QBEChangeNotification.broadcastChange(self.chain!)

													asyncMain {
														self.presentRaster(editingRaster)
													}
												}
											break

										case .failure(let e):
											asyncMain {
												NSAlert.showSimpleAlert(errorMessage, infoText: e, style: .critical, window: self.view.window)
											}
										}
									}
								}
							}
							else {
								if let ids = identifiers {
									// Create key
									let row = editingRaster[inRow]
									var key: [Column: Value] = [:]
									for identifyingColumn in ids {
										key[identifyingColumn] = row[identifyingColumn]
									}

									let mutation = DatasetMutation.update(key: key, column: editingRaster.columns[column], old: oldValue, new: toValue)
									job.async {
										md.performMutation(mutation, job: job) { result in
											switch result {
											case .success():
												/* The mutation has been performed on the source data, now perform it on our own
												temporary raster as well. We could also call self.calculate() here, but that takes
												a while, and we would lose our current scrolling position, etc. */
												RasterMutableDataset(raster: editingRaster).performMutation(editMutation, job: job) { result in
													QBEChangeNotification.broadcastChange(self.chain!)

													asyncMain {
														self.presentRaster(editingRaster)
													}
												}
												break

											case .failure(let e):
												asyncMain {
													NSAlert.showSimpleAlert(errorMessage, infoText: e, style: .critical, window: self.view.window)
												}
											}
										}
									}
								}
								else {
									// We cannot change the data because we cannot do it by row number and we don't have a sure primary key
									// TODO: ask the user what key to use ("what property makes each row unique?")
									asyncMain {
										NSAlert.showSimpleAlert(errorMessage, infoText: NSLocalizedString("There is not enough information to be able to distinguish rows.", comment: ""), style: .critical, window: self.view.window)
									}
								}
							}

						case .failure(let e):
							asyncMain {
								NSAlert.showSimpleAlert(errorMessage, infoText: e, style: .critical, window: self.view.window)
							}
						}
					}

				case .failure(let e):
					asyncMain {
						NSAlert.showSimpleAlert(errorMessage, infoText: e, style: .critical, window: self.view.window)
					}
				}

			}
		}
	}

	func dataView(_ view: QBEDatasetViewController, didRenameColumn column: Column, to: Column) {
		self.renameColumn(column, to: to)
	}

	private func renameColumn(_ column: Column, to: Column) {
		switch self.editingMode {
		case .notEditing:
			// Make a suggestion
			suggestSteps([
				QBERenameStep(previous: self.currentStep, renames: [column: to])
				])
			break

		case .editing(_):
			// Actually edit
			let errorText = String(format: NSLocalizedString("Could not rename column '%@' to '%@'", comment: ""), column.name, to.name)
			if let md = self.currentStep?.mutableDataset {
				let mutation = DatasetMutation.rename([column: to])
				let job = Job(.userInitiated)
				if md.canPerformMutation(mutation) {
					md.performMutation(mutation, job: job, callback: { result in
						switch result {
						case .success(_):
							asyncMain {
								self.calculate()
							}

						case .failure(let e):
							asyncMain {
								NSAlert.showSimpleAlert(errorText, infoText: e, style: .critical, window: self.view.window)
							}
						}
					})
				}
				else {
					NSAlert.showSimpleAlert(errorText, infoText: NSLocalizedString("The columns of this data set cannot be renamed.", comment: ""), style: .critical, window: self.view.window)
				}
			}
			break

		case .enablingEditing:
			break
		}
	}

	@discardableResult func dataView(_ view: QBEDatasetViewController, didChangeValue oldValue: Value, toValue: Value, inRow: Int, column: Int) -> Bool {
		suggestions?.cancel()
		let job = Job(.userInitiated)

		switch self.editingMode {
		case .notEditing:
			// In non-editing mode, we make a suggestion for a calculation
			calculator.currentRaster?.get(job) { (fallibleRaster) -> () in
				fallibleRaster.maybe { (raster) -> () in
					self.suggestions = Future<[QBEStep]>({(job, callback) -> () in
						job.async {
							let expressions = QBECalculateStep.suggest(change: oldValue, toValue: toValue, inRaster: raster, row: inRow, column: column, locale: self.locale, job: job)
							callback(expressions.map({QBECalculateStep(previous: self.currentStep, targetColumn: raster.columns[column], function: $0)}))
						}
					}, timeLimit: 5.0)

					self.suggestions!.get(job) { steps in
						asyncMain {
							self.suggestSteps(steps, afterChanging: oldValue, to: toValue, inColumn: column, inRow: inRow)
						}
					}
				}
			}

		case .editing(identifiers: let identifiers, editingRaster: _):
			self.editValue(oldValue, toValue: toValue, inRow: inRow, column: column, identifiers: identifiers)
			return true

		case .enablingEditing:
			return false

		}
		return false
	}

	func dataView(_ view: QBEDatasetViewController, viewControllerForColumn column: Column, info: Bool, callback: @escaping (NSViewController) -> ()) {
		let job = Job(.userInitiated)

		if info {
			if let popover = self.storyboard?.instantiateController(withIdentifier: "columnPopup") as? QBEColumnViewController {
				self.calculator.currentDataset?.get(job) { result in
					result.maybe { data in
						asyncMain {
							popover.column = column
							popover.data = data
							popover.isFullDataset = self.hasFullDataset
							popover.delegate = self
							callback(popover)
						}
					}
				}
			}
		}
		else {
			filterControllerJob?.cancel()
			filterControllerJob = job
			let sourceStep = (currentStep is QBEFilterSetStep) ? currentStep?.previous : currentStep

			sourceStep?.fullDataset(job) { result in
				result.maybe { fullDataset in
					let params = self.calculator.parameters

					sourceStep?.exampleDataset(job, maxInputRows: params.maximumExampleInputRows, maxOutputRows: params.desiredExampleRows) { result in
						result.maybe { exampleDataset in
							asyncMain {
								if let filterViewController = self.storyboard?.instantiateController(withIdentifier: "filterView") as? QBEFilterViewController {
									filterViewController.data = exampleDataset
									filterViewController.searchDataset = fullDataset
									filterViewController.column = column
									filterViewController.delegate = self

									if let filterSet = self.viewFilters[column] {
										filterViewController.filter = filterSet
									}
									callback(filterViewController)
								}
							}
						}
					}
				}
			}
		}
	}

	func dataView(_ view: QBEDatasetViewController, hasFilterForColumn column: Column) -> Bool {
		return self.viewFilters[column] != nil
	}
	
	func stepsChanged() {
		assertMainThread()
		self.editingMode = .notEditing
		self.stepsViewController?.steps = chain?.steps
		self.stepsViewController?.currentStep = currentStep
		updateView()
		self.delegate?.chainViewDidChangeChain(self)
	}
	
	internal var undo: UndoManager? { get { return chain?.tablet?.document?.undoManager } }
	
	private func pushStep(_ step: QBEStep) {
		var step = step
		assertMainThread()
		
		let isHead = chain?.head == nil || currentStep == chain?.head
		
		// Check if this step can (or should) be merged with the step it will be appended after
		if let cs = currentStep {
			switch step.mergeWith(cs) {
				case .impossible:
					break;
				
				case .possible:
					break;
				
				case .advised(let merged):
					popStep()
					remove(cs)
					step = merged
					step.previous = nil
					
					if let v = self.stepsViewController?.view {
						QBESettings.sharedInstance.showTip("mergeAdvised") {
							self.showTip(NSLocalizedString("Warp has automatically combined your changes with the previous step.", comment: ""), atView: v)
							return
						}
					}
					
					break;
				
				case .cancels:
					currentStep = cs.previous
					remove(cs)
					if let v = self.stepsViewController?.view {
						QBESettings.sharedInstance.showTip("mergeCancelOut") {
							self.showTip(NSLocalizedString("Your changes undo the previous step. Warp has therefore automatically removed the previous step.", comment: ""), atView: v)
							return
						}
					}
					return
			}
		}

		if let cn = currentStep?.next, cn != step {
			cn.previous = step
		}
		currentStep?.next = step
		step.previous = currentStep

		if isHead {
			chain?.head = step
		}

		currentStep = step
		updateView()
		stepsChanged()

		if let c = self.chain {
			QBEChangeNotification.broadcastChange(c)
		}
	}
	
	private func popStep() {
		currentStep = currentStep?.previous
	}
	
	@IBAction func transposeData(_ sender: NSObject) {
		if let cs = currentStep {
			suggestSteps([QBETransposeStep(previous: cs)])
		}
	}
	
	func suggestionsView(_ view: NSViewController, didSelectStep step: QBEStep) {
		previewStep = nil
		pushStep(step)
		stepsChanged()
		updateView()
		calculate()
	}
	
	func suggestionsView(_ view: NSViewController, didSelectAlternativeStep step: QBEStep) {
		selectAlternativeStep(step)
	}
	
	private func selectAlternativeStep(_ step: QBEStep) {
		previewStep = nil
		
		// Swap out alternatives
		if var oldAlternatives = currentStep?.alternatives {
			oldAlternatives.remove(step)
			oldAlternatives.append(currentStep!)
			step.alternatives = oldAlternatives
		}
		
		// Swap out step
		let next = currentStep?.next
		let previous = currentStep?.previous
		step.previous = previous
		currentStep = step
		
		if next == nil {
			chain?.head = step
		}
		else {
			next!.previous = step
			step.next = next
		}
		stepsChanged()
		calculate()

		if let c = self.chain {
			QBEChangeNotification.broadcastChange(c)
		}
	}
	
	func suggestionsView(_ view: NSViewController, previewStep step: QBEStep?) {
		if step == currentStep || step == nil {
			previewStep = nil
		}
		else {
			previewStep = step
		}
		updateView()
		calculate()
	}
	
	private func updateView() {
		assertMainThread()

		// Update calculation status
		let hasRaster = dataViewController?.raster != nil
		let hasError = self.dataViewController?.errorMessage != nil
		let calculationProgress = hasError ? 1.0 : (self.calculator.currentCalculation?.job.progress ?? 1.0)
		self.outletView?.enabled = hasRaster
		self.outletView?.progress = calculationProgress
		self.outletView?.animating = self.calculator.calculating && calculationProgress < 1.0
		self.dataViewController?.showFooters = !self.calculator.calculating && hasRaster

		// Update editing status
		switch self.editingMode {
		case .editing(identifiers: _):
			// In editing mode, rows and columns can be added
			self.dataViewController?.showNewRow = true
			self.dataViewController?.showNewColumn = true

		case .notEditing:
			// In non-editing mode, only new calculated columns can be added
			self.dataViewController?.showNewRow = false
			self.dataViewController?.showNewColumn = true

		default:
			self.dataViewController?.showNewRow = false
			self.dataViewController?.showNewColumn = false
		}

		self.view.window?.update()
		self.view.window?.toolbar?.validateVisibleItems()
	}

	private func suggestSteps(_ steps: [QBEStep], afterChanging from: Value, to: Value, inColumn: Int, inRow: Int) {
		assertMainThread()

		let supportsEditing = self.currentStep?.mutableDataset != nil && self.supportsEditing

		if supportsEditing {
			let alert = NSAlert()
			alert.alertStyle = NSAlertStyle.informational
			alert.messageText = String(format: "Changing '%@' to '%@'".localized, self.locale.localStringFor(to), self.locale.localStringFor(from))
			alert.informativeText = "Warp can either change the value permanently in the source data set, or add a step that performs the change for all values in the column similarly.".localized
			alert.addButton(withTitle: "Add step".localized)
			alert.addButton(withTitle: "Change source data".localized)
			alert.addButton(withTitle: "Cancel".localized)
			alert.showsSuppressionButton = false

			alert.beginSheetModal(for: self.view.window!, completionHandler: { res in
				switch res {
				case NSAlertFirstButtonReturn:
					self.suggestSteps(steps)

				case NSAlertSecondButtonReturn:
					self.enterEditingMode {
						switch self.editingMode {
						case .editing(identifiers: let ids, editingRaster: _):
							self.editValue(from, toValue: to, inRow: inRow, column: inColumn, identifiers: ids)

						case .notEditing, .enablingEditing:
							let message = String(format: "Cannot change '%@' to '%@'".localized, self.locale.localStringFor(to), self.locale.localStringFor(from))
							NSAlert.showSimpleAlert(message, infoText: "The data set cannot be edited".localized, style: .critical, window: self.view.window)
						}
					}

				case NSAlertThirdButtonReturn:
					// Cancel
					break

				default:
					break
				}
			})
		}
		else {
			self.suggestSteps(steps)
		}
	}

	func suggestSteps(_ steps: [QBEStep]) {
		assertMainThread()
		
		if steps.isEmpty {
			// Alert
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("I have no idea what you did.", comment: "")
			alert.beginSheetModal(for: self.view.window!, completionHandler: { (a: NSModalResponse) -> Void in
			})
		}
		else {
			let step = steps.first!
			step.alternatives = Array(steps.dropFirst())
			pushStep(step)
			updateView()
			calculate()

			if steps.count > 1 {
				self.showSuggestionsForStep(step, atView: self.stepsViewController!.view)
			}
		}
	}

	func sentenceView(_ view: QBESentenceViewController, didChangeConfigurable configurable: QBEConfigurable) {
		updateView()
		calculate()
		if let c = self.chain {
			QBEChangeNotification.broadcastChange(c)
		}
	}
	
	func stepsController(_ vc: QBEStepsViewController, showSuggestionsForStep step: QBEStep, atView: NSView?) {
		self.showSuggestionsForStep(step, atView: atView ?? self.stepsViewController?.view ?? self.view)
	}
	
	private func showSuggestionsForStep(_ step: QBEStep, atView: NSView) {
		assertMainThread()
		
		if let alternatives = step.alternatives, alternatives.count > 0 {
			if let sv = self.storyboard?.instantiateController(withIdentifier: "suggestionsList") as? QBESuggestionsListViewController {
				sv.delegate = self
				sv.suggestions = Array(alternatives)
				self.presentViewController(sv, asPopoverRelativeTo: atView.bounds, of: atView, preferredEdge: NSRectEdge.maxX, behavior: NSPopoverBehavior.semitransient)
			}
		}
	}
	
	@IBAction func showSuggestions(_ sender: NSObject) {
		if let s = currentStep {
			let view: NSView
			if let toolbarView = sender as? NSView {
				view = toolbarView
			}
			else {
				view = self.stepsViewController?.view ?? self.view
			}

			showSuggestionsForStep(s, atView: view)
		}
	}
	
	@IBAction func chooseFirstAlternativeStep(_ sender: NSObject) {
		if let s = currentStep?.alternatives, s.count > 0 {
			selectAlternativeStep(s.first!)
		}
	}
	
	@IBAction func setFullWorkingSet(_ sender: NSObject) {
		useFullDataset = true
	}
	
	@IBAction func setSelectionWorkingSet(_ sender: NSObject) {
		useFullDataset = false
	}
	
	@IBAction func renameColumn(_ sender: NSObject) {
		suggestSteps([QBERenameStep(previous: nil)])

		// Force the configuration pop-up to show by calling configureStep with necessary=true
		delegate?.chainView(self, configureStep: self.currentStep, necessary: true, delegate: self)
	}
	
	private func addColumnBeforeAfterCurrent(_ before: Bool) {
		let job = Job(.userInitiated)

		calculator.currentDataset?.get(job) { (d) -> () in
			d.maybe { (data) -> () in
				data.columns(job) { (columnNamesFallible) -> () in
					columnNamesFallible.maybe { (cols) -> () in
						if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
							let name = Column.defaultNameForNewColumn(cols)
							if before {
								if let firstSelectedColumn = selectedColumns.first {
									let insertRelative = cols[firstSelectedColumn]
									let step = QBECalculateStep(previous: self.currentStep, targetColumn: name, function: Literal(Value.empty), insertRelativeTo: insertRelative, insertBefore: true)
									
									asyncMain {
										self.pushStep(step)
										self.calculate()
									}
								}
								else {
									return
								}
							}
							else {
								if let lastSelectedColumn = selectedColumns.last, lastSelectedColumn < cols.count {
									let insertAfter = cols[lastSelectedColumn]
									let step = QBECalculateStep(previous: self.currentStep, targetColumn: name, function: Literal(Value.empty), insertRelativeTo: insertAfter, insertBefore: false)

									asyncMain {
										self.pushStep(step)
										self.calculate()
									}
								}
								else {
									return
								}
							}
						}
					}
				}
			}
		}
	}
	
	@IBAction func addColumnToRight(_ sender: NSObject) {
		assertMainThread()
		addColumnBeforeAfterCurrent(false)
	}
	
	@IBAction func addColumnToLeft(_ sender: NSObject) {
		assertMainThread()
		addColumnBeforeAfterCurrent(true)
	}
	
	@IBAction func addColumnAtEnd(_ sender: NSObject) {
		assertMainThread()
		let job = Job(.userInitiated)
		
		calculator.currentDataset?.get(job) {(data) in
			data.maybe {$0.columns(job) {(columnsFallible) in
				columnsFallible.maybe { (cols) -> () in
					asyncMain {
						let name = Column.defaultNameForNewColumn(cols)
						let step = QBECalculateStep(previous: self.currentStep, targetColumn: name, function: Literal(Value.empty), insertRelativeTo: nil, insertBefore: false)
						self.pushStep(step)
						self.calculate()
					}
				}
			}}
		}
	}
	
	@IBAction func addColumnAtBeginning(_ sender: NSObject) {
		assertMainThread()
		let job = Job(.userInitiated)
		
		calculator.currentDataset?.get(job) {(data) in
			data.maybe {$0.columns(job) {(columnsFallible) in
				columnsFallible.maybe { (cols) -> () in
					asyncMain {
						let name = Column.defaultNameForNewColumn(cols)
						let step = QBECalculateStep(previous: self.currentStep, targetColumn: name, function: Literal(Value.empty), insertRelativeTo: nil, insertBefore: true)
						self.pushStep(step)
						self.calculate()
					}
				}
			}}
		}
	}
	
	private func remove(_ stepToRemove: QBEStep) {
		assertMainThread()
		
		let previous = stepToRemove.previous
		previous?.next = stepToRemove.next
		
		if let next = stepToRemove.next {
			next.previous = previous
			stepToRemove.next = nil
		}
		
		if chain?.head == stepToRemove {
			chain?.head = stepToRemove.previous
		}
		
		stepToRemove.previous = nil
		stepsChanged()

		if let c = self.chain {
			QBEChangeNotification.broadcastChange(c)
		}
	}
	
	@IBAction func copy(_ sender: NSObject) {
		assertMainThread()
		
		if let s = currentStep {
			let pboard = NSPasteboard.general()
			pboard.clearContents()
			pboard.declareTypes([QBEStep.dragType], owner: nil)
			let data = NSKeyedArchiver.archivedData(withRootObject: s)
			pboard.setData(data, forType: QBEStep.dragType)
		}
	}
	
	@IBAction func removeStep(_ sender: NSObject) {
		if let stepToRemove = currentStep {
			popStep()
			remove(stepToRemove)
			calculate()
			
			(undo?.prepare(withInvocationTarget: self) as? QBEChainViewController)?.addStep(stepToRemove)
			undo?.setActionName(NSLocalizedString("Remove step", comment: ""))
		}
	}

	@IBAction func addCacheStep(_ sender: NSObject) {
		suggestSteps([QBECacheStep()])
	}
	
	@IBAction func addDebugStep(_ sender: NSObject) {
		suggestSteps([QBEDebugStep()])
	}
	
	private func sortRows(_ ascending: Bool) {
		assertMainThread()
		let job = Job(.userInitiated)

		if let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes, let firstSelectedColumn = selectedColumns.first {
			calculator.currentRaster?.get(job) {(r) -> () in
				r.maybe { (raster) -> () in
					if firstSelectedColumn < raster.columns.count {
						let columnName = raster.columns[firstSelectedColumn]
						self.sortRowsInColumn(columnName, ascending: ascending)
					}
				}
			}
		}
	}

	private func sortRowsInColumn(_ column: Column, ascending: Bool) {
		let expression = Sibling(column)
		let order = Order(expression: expression, ascending: ascending, numeric: true)

		asyncMain {
			self.suggestSteps([QBESortStep(previous: self.currentStep, orders: [order])])
		}
	}

	@IBAction func reverseSortRows(_ sender: NSObject) {
		sortRows(false)
	}
	
	@IBAction func sortRows(_ sender: NSObject) {
		sortRows(true)
	}

	@IBAction func createDummyColumns(_ sender: NSObject) {
		assertMainThread()
		let job = Job(.userInitiated)

		if let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes, let firstSelectedColumn = selectedColumns.first {
			calculator.currentRaster?.get(job) {(r) -> () in
				r.maybe { (raster) -> () in
					if firstSelectedColumn < raster.columns.count {
						let columnName = raster.columns[firstSelectedColumn]
						asyncMain {
							self.suggestSteps([QBEDummiesStep(previous: self.currentStep, sourceColumn: columnName)])
						}
					}
				}
			}
		}
	}

	@IBAction func explodeColumnVertically(_ sender: NSObject) {
		assertMainThread()
		let job = Job(.userInitiated)

		if let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes, let firstSelectedColumn = selectedColumns.first {
			calculator.currentRaster?.get(job) {(r) -> () in
				r.maybe { (raster) -> () in
					if firstSelectedColumn < raster.columns.count {
						let columnName = raster.columns[firstSelectedColumn]
						asyncMain {
							self.suggestSteps([QBEExplodeVerticallyStep(previous: self.currentStep, splitColumn: columnName)])
						}
					}
				}
			}
		}
	}

	@IBAction func explodeColumnVerticallyByLines(_ sender: NSObject) {
		assertMainThread()
		let job = Job(.userInitiated)

		if let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes, let firstSelectedColumn = selectedColumns.first {
			calculator.currentRaster?.get(job) {(r) -> () in
				r.maybe { (raster) -> () in
					if firstSelectedColumn < raster.columns.count {
						let columnName = raster.columns[firstSelectedColumn]
						asyncMain {
							let s = QBEExplodeVerticallyStep(previous: self.currentStep, splitColumn: columnName)
							s.mode = .unixNewLine
							self.suggestSteps([s])
						}
					}
				}
			}
		}
	}

	@IBAction func explodeColumnHorizontally(_ sender: NSObject) {
		assertMainThread()
		let job = Job(.userInitiated)

		if let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes, let firstSelectedColumn = selectedColumns.first {
			calculator.currentRaster?.get(job) {(r) -> () in
				r.maybe { (raster) -> () in
					if firstSelectedColumn < raster.columns.count {
						let columnName = raster.columns[firstSelectedColumn]
						asyncMain {
							self.suggestSteps([QBEExplodeHorizontallyStep(previous: self.currentStep, splitColumn: columnName)])
						}
					}
				}
			}
		}
	}
	
	
	@IBAction func selectColumns(_ sender: NSObject) {
		selectColumns(false)
	}
	
	@IBAction func removeColumns(_ sender: NSObject) {
		selectColumns(true)
	}
	
	private func selectColumns(_ remove: Bool) {
		let job = Job(.userInitiated)

		if let colsToRemove = dataViewController?.tableView?.selectedColumnIndexes {
			// Get the names of the columns to remove
			calculator.currentRaster?.get(job) { (raster) -> () in
				raster.maybe { (r) -> () in
					var namesToRemove: OrderedSet<Column> = []
					var namesToSelect: OrderedSet<Column> = []
					
					for i in 0..<r.columns.count {
						if colsToRemove.contains(i) {
							namesToRemove.append(r.columns[i])
						}
						else {
							namesToSelect.append(r.columns[i])
						}
					}

					asyncMain {
						var steps: [QBEStep] = []

						if namesToRemove.count > 0 && namesToRemove.count < r.columns.count {
							steps.append(QBEColumnsStep(previous: self.currentStep, columns: namesToRemove, select: !remove))
						}

						if namesToSelect.count > 0 && namesToSelect.count < r.columns.count {
							steps.append(QBEColumnsStep(previous: self.currentStep, columns: namesToSelect, select: remove))
						}

						self.suggestSteps(steps)
					}
				}
			}
		}
	}
	
	@IBAction func randomlySelectRows(_ sender: NSObject) {
		suggestSteps([QBERandomStep(previous: currentStep, numberOfRows: 1)])
	}
	
	@IBAction func limitRows(_ sender: NSObject) {
		suggestSteps([QBELimitStep(previous: currentStep, numberOfRows: 1)])
	}
	
	@IBAction func removeRows(_ sender: NSObject) {
		let job = Job(.userInitiated)

		switch self.editingMode {
		case .editing(identifiers: _, editingRaster: _):
			if let rowsToRemove = dataViewController?.tableView?.selectedRowIndexes {
				self.removeRowsPermanently(Array(rowsToRemove))
			}

		case .notEditing:
			if let rowsToRemove = dataViewController?.tableView?.selectedRowIndexes {
				if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
					calculator.currentRaster?.get(job) { (r) -> () in
						r.maybe { (raster) -> () in
							// Invert the selection
							let selectedToKeep = NSMutableIndexSet()
							let selectedToRemove = NSMutableIndexSet()
							for index in 0..<raster.rowCount {
								if !rowsToRemove.contains(index) {
									selectedToKeep.add(index)
								}
								else {
									selectedToRemove.add(index)
								}
							}

							var relevantColumns = Set<Column>()
							for columnIndex in 0..<raster.columns.count {
								if selectedColumns.contains(columnIndex) {
									relevantColumns.insert(raster.columns[columnIndex])
								}
							}

							// Find suggestions for keeping the other rows
							let keepSuggestions = QBERowsStep.suggest(selectedToKeep as IndexSet, columns: relevantColumns, inRaster: raster, fromStep: self.currentStep, select: true)
							var removeSuggestions = QBERowsStep.suggest(selectedToRemove as IndexSet, columns: relevantColumns, inRaster: raster, fromStep: self.currentStep, select: false)
							removeSuggestions.append(contentsOf: keepSuggestions)

							asyncMain {
								self.suggestSteps(removeSuggestions)
							}
						}
					}
				}
			}

		case .enablingEditing:
			return
		}
	}

	@IBAction func aggregateRowsByGroup(_ sender: NSObject) {
		if let selectedColumns = dataViewController?.tableView?.selectedColumnIndexes {
			let job = Job(.userInitiated)

			calculator.currentRaster?.get(job) { result in
				switch result {
				case .success(let raster):
					let step = QBEPivotStep()
					var selectedColumnNames: OrderedSet<Column> = []
					selectedColumns.forEach { idx in
						if raster.columns.count > idx {
							selectedColumnNames.append(raster.columns[idx])
						}
					}
					step.rows = selectedColumnNames
					step.aggregates.append(Aggregation(map: Literal(Value(1)), reduce: Function.CountAll, targetColumn: Column("Count".localized)))
					asyncMain {
						self.suggestSteps([step])
					}

				case .failure(let e):
					asyncMain {
						NSAlert.showSimpleAlert("The selection cannot be aggregated".localized, infoText: e, style: .critical, window: self.view.window)
					}
				}
			}
		}
	}
	
	@IBAction func aggregateRowsByCells(_ sender: NSObject) {
		let job = Job(.userInitiated)
		if let selectedRows = dataViewController?.tableView?.selectedRowIndexes {
			if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
				calculator.currentRaster?.get(job) { (fallibleRaster) -> ()in
					fallibleRaster.maybe { (raster) -> () in
						var relevantColumns = Set<Column>()
						for columnIndex in 0..<raster.columns.count {
							if selectedColumns.contains(columnIndex) {
								relevantColumns.insert(raster.columns[columnIndex])
							}
						}
						
						let suggestions = QBEPivotStep.suggest(selectedRows, columns: relevantColumns, inRaster: raster, fromStep: self.currentStep)
						
						asyncMain {
							self.suggestSteps(suggestions)
						}
					}
				}
			}
		}
	}
	
	@IBAction func selectRows(_ sender: NSObject) {
		let job = Job(.userInitiated)

		if let selectedRows = dataViewController?.tableView?.selectedRowIndexes {
			if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
				calculator.currentRaster?.get(job) { (fallibleRaster) -> () in
					fallibleRaster.maybe { (raster) -> () in
						var relevantColumns = Set<Column>()
						for columnIndex in 0..<raster.columns.count {
							if selectedColumns.contains(columnIndex) {
								relevantColumns.insert(raster.columns[columnIndex])
							}
						}
						
						let suggestions = QBERowsStep.suggest(selectedRows, columns: relevantColumns, inRaster: raster, fromStep: self.currentStep, select: true)
						
						asyncMain {
							self.suggestSteps(suggestions)
						}
					}
				}
			}
		}
	}

	private func performMutation(_ mutation: DatasetMutation, callback: (() -> ())? = nil) {
		assertMainThread()

		switch self.editingMode {
		case .notEditing:
			// Need to start editing first
			self.enterEditingMode {
				asyncMain {
					self.performMutation(mutation) {
						// stop editing here again
						self.leaveEditingMode()
						callback?()
					}
				}
			}
			return

		case .enablingEditing:
			// Not now, another action in progress
			let a = NSAlert()
			a.messageText = "The selected action cannot be performed on this data set right now.".localized
			a.alertStyle = NSAlertStyle.warning
			if let w = self.view.window {
				a.beginSheetModal(for: w, completionHandler: nil)
			}
			callback?()
			return

		case .editing(identifiers: _, editingRaster: _):
			guard let cs = currentStep, let store = cs.mutableDataset, store.canPerformMutation(mutation) else {
				let a = NSAlert()
				a.messageText = "The selected action cannot be performed on this data set.".localized
				a.alertStyle = NSAlertStyle.warning
				if let w = self.view.window {
					a.beginSheetModal(for: w, completionHandler: nil)
				}
				callback?()
				return
			}

			let confirmationAlert = NSAlert()

			switch mutation {
			case .truncate:
				confirmationAlert.messageText = NSLocalizedString("Are you sure you want to remove all rows in the source data set?", comment: "")

			case .drop:
				confirmationAlert.messageText = NSLocalizedString("Are you sure you want to completely remove the source data set?", comment: "")

			default: fatalError("Mutation not supported here")
			}

			confirmationAlert.informativeText = NSLocalizedString("This will modify the original data, and cannot be undone.", comment: "")
			confirmationAlert.alertStyle = NSAlertStyle.informational
			let yesButton = confirmationAlert.addButton(withTitle: NSLocalizedString("Perform modifications", comment: ""))
			let noButton = confirmationAlert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
			yesButton.tag = 1
			noButton.tag = 2
			confirmationAlert.beginSheetModal(for: self.view.window!) { (response) -> Void in
				if response == 1 {
					// Confirmed
					let job = Job(.userInitiated)

					// Register this job with the background job manager
					let name: String
					switch mutation {
					case .truncate: name = NSLocalizedString("Truncate data set", comment: "")
					case .drop: name = NSLocalizedString("Remove data set", comment: "")
					default: fatalError("Mutation not supported here")
					}

					QBEAppDelegate.sharedInstance.jobsManager.addJob(job, description: name)

					// Start the mutation
					store.performMutation(mutation, job: job) { result in
						asyncMain {
							switch result {
							case .success:
								//NSAlert.showSimpleAlert(NSLocalizedString("Command completed successfully", comment: ""), style: NSAlertStyle.InformationalAlertStyle, window: self.view.window!)
								self.useFullDataset = false
								self.calculate()

							case .failure(let e):
								NSAlert.showSimpleAlert(NSLocalizedString("The selected action cannot be performed on this data set.",comment: ""), infoText: e, style: .warning, window: self.view.window!)

							}
							callback?()
							return
						}
					}
				}
				else {
					callback?()
					return
				}
			}
		}
	}

	@IBAction func alterStore(_ sender: NSObject) {
		if let md = self.currentStep?.mutableDataset, md.canPerformMutation(.alter(DatasetDefinition(columns: []))) {
			let alterViewController = QBEAlterTableViewController()
			alterViewController.mutableDataset = md
			alterViewController.warehouse = md.warehouse
			alterViewController.delegate = self

			// Get current column names
			let job = Job(.userInitiated)
			md.data(job) { result in
				switch result {
				case .success(let data):
					data.columns(job) { result in
						switch result {
							case .success(let columns):
								asyncMain {
									alterViewController.definition = DatasetDefinition(columns: columns)
									self.presentViewControllerAsSheet(alterViewController)
								}

							case .failure(let e):
								asyncMain {
									NSAlert.showSimpleAlert(NSLocalizedString("Could not modify table", comment: ""), infoText: e, style: .critical, window: self.view.window)
								}
						}
					}

				case .failure(let e):
					asyncMain {
						NSAlert.showSimpleAlert(NSLocalizedString("Could not modify table", comment: ""), infoText: e, style: .critical, window: self.view.window)
					}
				}
			}
		}
	}

	@IBAction func truncateStore(_ sender: NSObject) {
		self.performMutation(.truncate)
	}

	@IBAction func dropStore(_ sender: NSObject) {
		self.performMutation(.drop)
	}

	@IBAction func startEditing(_ sender: NSObject) {
		self.enterEditingMode()
	}

	private func enterEditingMode(callback: (() -> ())? = nil) {
		let forceCustomKeySelection = self.view.window?.currentEvent?.modifierFlags.contains(.option) ?? false

		if let md = self.currentStep?.mutableDataset, self.supportsEditing {
			self.editingMode = .enablingEditing
			let job = Job(.userInitiated)
			md.identifier(job) { result in
				asyncMain {
					switch self.editingMode {
					case .enablingEditing:
						if case .success(let ids) = result, ids != nil && !forceCustomKeySelection {
							self.startEditingWithIdentifier(ids!, callback: callback)
						}
						else if !forceCustomKeySelection && md.canPerformMutation(DatasetMutation.edit(row: 0, column: Column("a"), old: Value.invalid, new: Value.invalid)) {
							// This data set does not have key columns, but this isn't an issue, as it can be edited by row number
							self.startEditingWithIdentifier([], callback: callback)
						}
						else {
							// Cannot start editing right now
							self.editingMode = .notEditing

							md.columns(job) { columnsResult in
								switch columnsResult {
								case .success(let columns):
									asyncMain {
										let ctr = self.storyboard?.instantiateController(withIdentifier: "keyViewController") as! QBEKeySelectionViewController
										ctr.columns = columns

										if case .success(let ids) = result, ids != nil {
											ctr.keyColumns = ids!
										}

										ctr.callback = { keys in
											asyncMain {
												self.startEditingWithIdentifier(keys, callback: callback)
											}
										}

										self.presentViewControllerAsSheet(ctr)
									}

								case .failure(let e):
									NSAlert.showSimpleAlert(NSLocalizedString("This data set cannot be edited.", comment: ""), infoText: e, style: .warning, window: self.view.window)
								}
							}
						}

					default:
						// Editing request was apparently cancelled, do not switch to editing mode
						break
					}

					self.view.window?.update()
				}
			}
		}
		self.view.window?.update()
	}

	/** Start editing using the given set of identifier keys. If the set is empty, the data set must support line-based
	editing (DatasetMutation.edit). */
	private func startEditingWithIdentifier(_ ids: Set<Column>, callback: (() -> ())? = nil) {
		let job = Job(.userInitiated)

		asyncMain {
			switch self.editingMode {
			case .enablingEditing, .notEditing:
				self.calculator.currentRaster?.get(job) { result in
					switch result {
					case .success(let editingRaster):
						asyncMain {
							self.editingMode = .editing(identifiers: ids, editingRaster: editingRaster.clone(false))
							self.view.window?.update()
							callback?()
						}

					case .failure(let e):
						asyncMain {
							NSAlert.showSimpleAlert(NSLocalizedString("This data set cannot be edited.", comment: ""), infoText: e, style: .warning, window: self.view.window)
							self.editingMode = .notEditing
							callback?()
						}
					}
				}

			case .editing(identifiers: _, editingRaster: _):
				// Already editing
				callback?()
				break
			}
			self.view.window?.update()
		}
	}

	@IBAction func stopEditing(_ sender: NSObject) {
		self.leaveEditingMode()
	}

	private func leaveEditingMode() {
		self.editingMode = .notEditing

		asyncMain {
			self.calculate()
			self.view.window?.update()
		}
	}

	@IBAction func toggleEditing(_ sender: NSObject) {
		switch editingMode {
		case .enablingEditing, .editing(identifiers: _):
			self.stopEditing(sender)

		case .notEditing:
			self.startEditing(sender)
		}
	}

	@IBAction func toggleFullDataset(_ sender: NSObject) {
		useFullDataset = !(useFullDataset || hasFullDataset)
		hasFullDataset = false
		self.view.window?.update()
	}

	@IBAction func refreshDataset(_ sender: NSObject) {
		if !useFullDataset && hasFullDataset {
			useFullDataset = true
		}
		else {
			self.calculate()
		}
	}

	@objc override func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
		return self.validate(item)
	}

	@IBAction func quickFixTrimSpaces(_ sender: NSObject) {
		self.quickFixColumn(expression: Call(arguments: [Identity()], type: .Trim))
	}

	@IBAction func quickFixUppercase(_ sender: NSObject) {
		self.quickFixColumn(expression: Call(arguments: [Identity()], type: .Uppercase))
	}

	@IBAction func quickFixLowercase(_ sender: NSObject) {
		self.quickFixColumn(expression: Call(arguments: [Identity()], type: .Lowercase))
	}

	@IBAction func quickFixCapitalize(_ sender: NSObject) {
		self.quickFixColumn(expression: Call(arguments: [Identity()], type: .Capitalize))
	}

	@IBAction func quickFixReadNumberDecimalPoint(_ sender: NSObject) {
		self.quickFixColumn(expression: Call(arguments: [Identity(), Literal(.string(".")), Literal(.string(","))], type: .ParseNumber))
	}

	@IBAction func quickFixReadNumberDecimalComma(_ sender: NSObject) {
		self.quickFixColumn(expression: Call(arguments: [Identity(), Literal(.string(",")), Literal(.string("."))], type: .ParseNumber))
	}

	@IBAction func quickFixJSON(_ sender: NSObject) {
		self.quickFixColumn(expression: Call(arguments: [Identity()], type: .JSONDecode))
	}

	private func quickFixColumn(expression: Expression) {
		if let ci = dataViewController?.tableView?.selectedColumnIndexes {
			let job = Job(.userInitiated)
			calculator.currentRaster?.get(job) { result in
				switch result {
				case .success(let raster):
					for columnIndex in ci {
						let columnName = raster.columns[columnIndex]
						let step = QBECalculateStep(previous: nil, targetColumn: columnName, function: expression)

						asyncMain {
							self.suggestSteps([step])
						}
					}

				case .failure(let e):
					trace("Error quick fixing: \(e)")
				}
			}

		}
	}

	func validate(_ item: NSToolbarItem) -> Bool {
		if item.action == #selector(QBEChainViewController.toggleFullDataset(_:)) {
			if let c = item.view as? NSButton {
				c.state = (currentStep != nil && (hasFullDataset || useFullDataset)) ? NSOnState: NSOffState
			}
		}
		else if item.action == #selector(QBEChainViewController.toggleEditing(_:)) {
			if let c = item.view as? NSButton {
				switch self.editingMode {
				case .editing(_):
					c.state = NSOnState

				case .enablingEditing:
					c.state = NSMixedState

				case .notEditing:
					c.state = NSOffState
				}
			}
		}

		return validateSelector(item.action!)
	}

	func jsonViewController(_ vc: QBEJSONViewController, requestExtraction of: Expression, to toColumn: Column) {
		if let column = self.dataViewController?.firstSelectedColumn {
			let source = Call(arguments: [Sibling(column)], type: .JSONDecode)
			let expression = of.expressionReplacingIdentityReferencesWith(source)
			let step = QBECalculateStep(previous: nil, targetColumn: toColumn, function: expression)
			self.suggestSteps([step])
		}
	}

	@IBAction func extractJSON(_ sender: NSObject) {
		if let value = self.dataViewController?.firstSelectedValue {
			if let json = value.stringValue {
				do {
					let jsonObject = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!, options: [])
					let ctr = QBEJSONViewController(nibName: "QBEJSONViewController", bundle: nil)!
					ctr.data = jsonObject as? NSObject
					ctr.delegate = self
					self.presentViewControllerAsSheet(ctr)
				}
				catch(_) {
						// @@ ERROR invalid JSON
				}
			}
			else {
				// @@@ ERROR selected is not not JSON
			}
		}
		else {
			// @@@ Error nothing selected
		}
	}

	@objc func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		return validateSelector(item.action!)
	}

	private func validateSelector(_ selector: Selector) -> Bool {
		if selector == #selector(QBEChainViewController.transposeData(_:)) {
			return currentStep != nil
		}
		else if selector == #selector(QBEChainViewController.truncateStore(_:))  {
			if let cs = self.currentStep?.mutableDataset, cs.canPerformMutation(.truncate) {
				return true
			}
			return false
		}
		else if selector == #selector(QBEChainViewController.dropStore(_:))  {
			if let cs = self.currentStep?.mutableDataset, cs.canPerformMutation(.drop) {
				return true
			}
			return false
		}
		else if selector == #selector(QBEChainViewController.alterStore(_:))  {
			if let cs = self.currentStep?.mutableDataset, cs.canPerformMutation(.alter(DatasetDefinition(columns: []))) {
				return true
			}
			return false
		}
		else if selector==#selector(QBEChainViewController.clearAllFilters(_:)) {
			return self.viewFilters.count > 0
		}
		else if selector==#selector(QBEChainViewController.makeAllFiltersPermanent(_:)) {
			return self.viewFilters.count > 0
		}
		else if selector==#selector(QBEChainViewController.crawl(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.addDebugStep(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.addCacheStep(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.aggregateRowsByCells(_:)) {
			if let rowsToAggregate = dataViewController?.tableView?.selectedRowIndexes {
				return rowsToAggregate.count > 0  && currentStep != nil
			}
			return false
		}
		else if selector==#selector(QBEChainViewController.aggregateRowsByGroup(_:)) {
			if let colsToAggregate = dataViewController?.tableView?.selectedColumnIndexes {
				return colsToAggregate.count > 0  && currentStep != nil
			}
			return false
		}
		else if selector==#selector(QBEChainViewController.removeRows(_:)) {
			if let rowsToRemove = dataViewController?.tableView?.selectedRowIndexes {
				return rowsToRemove.count > 0  && currentStep != nil
			}
			return false
		}
		else if selector==#selector(QBEChainViewController.removeColumns(_:)) {
			if let colsToRemove = dataViewController?.tableView?.selectedColumnIndexes {
				return colsToRemove.count > 0 && currentStep != nil
			}
			return false
		}
		else if selector==#selector(QBEChainViewController.renameColumn(_:)) {
			if let colsToRemove = dataViewController?.tableView?.selectedColumnIndexes {
				return colsToRemove.count > 0 && currentStep != nil
			}
			return false
		}
		// Quick fix actions
		else if selector==#selector(QBEChainViewController.quickFixLowercase(_:)) ||
			selector==#selector(QBEChainViewController.quickFixUppercase(_:)) ||
			selector==#selector(QBEChainViewController.quickFixCapitalize(_:)) ||
			selector==#selector(QBEChainViewController.quickFixJSON(_:)) ||
			selector==#selector(QBEChainViewController.quickFixReadNumberDecimalComma(_:)) ||
			selector==#selector(QBEChainViewController.quickFixReadNumberDecimalPoint(_:)) ||
			selector==#selector(QBEChainViewController.quickFixTrimSpaces(_:)) {
			if let colsToRemove = dataViewController?.tableView?.selectedColumnIndexes {
				return colsToRemove.count > 0 && currentStep != nil
			}
			return false
		}
		else if selector==#selector(QBEChainViewController.selectColumns(_:) as (QBEChainViewController) -> (NSObject) -> ()) {
			if let colsToRemove = dataViewController?.tableView?.selectedColumnIndexes {
				return colsToRemove.count > 0 && currentStep != nil
			}
			return false
		}
		else if selector==#selector(QBEChainViewController.addColumnAtEnd(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.addColumnAtBeginning(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.addColumnToLeft(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.addColumnToRight(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.exportFile(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.goBack(_:)) {
			return currentStep?.previous != nil
		}
		else if selector==#selector(QBEChainViewController.goForward(_:)) {
			return currentStep?.next != nil
		}
		else if selector==#selector(QBEChainViewController.randomlySelectRows(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.limitRows(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.pivot(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.flatten(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.removeStep(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.removeDuplicateRows(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.selectRows(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.showSuggestions(_:)) {
			return currentStep?.alternatives != nil && currentStep!.alternatives!.count > 0
		}
		else if selector==#selector(QBEChainViewController.chooseFirstAlternativeStep(_:)) {
			return currentStep?.alternatives != nil && currentStep!.alternatives!.count > 0
		}
		else if selector==#selector(QBEChainViewController.setFullWorkingSet(_:)) {
			return currentStep != nil && !useFullDataset
		}
		else if selector==#selector(QBEChainViewController.toggleFullDataset(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.toggleEditing(_:)) {
			return currentStep != nil && supportsEditing
		}
		else if selector==#selector(QBEChainViewController.startEditing(_:)) {
			switch self.editingMode {
			case .editing(identifiers: _), .enablingEditing:
				return false
			case .notEditing:
				return currentStep != nil && supportsEditing
			}
		}
		else if selector==#selector(QBEChainViewController.stopEditing(_:)) {
			switch self.editingMode {
			case .editing(identifiers: _), .enablingEditing:
				return true
			case .notEditing:
				return false
			}
		}
		else if selector==#selector(QBEChainViewController.setSelectionWorkingSet(_:)) {
			return currentStep != nil && useFullDataset
		}
		else if selector==#selector(QBEChainViewController.sortRows(_:) as (QBEChainViewController) -> (NSObject) -> ()) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.explodeColumnHorizontally(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.explodeColumnVertically(_:)) || selector == #selector(QBEChainViewController.explodeColumnVerticallyByLines(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.createDummyColumns(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.extractJSON(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.reverseSortRows(_:)) {
			return currentStep != nil
		}
		else if selector == #selector(QBEChainViewController.removeTablet(_:)) {
			return true
		}
		else if selector == #selector(QBEChainViewController.delete(_:)) {
			return true
		}
		else if selector==#selector(QBEChainViewController.paste(_:)) {
			let pboard = NSPasteboard.general()
			if pboard.data(forType: QBEStep.dragType) != nil {
				return true
			}
			return false
		}
		else if selector == #selector(QBEChainViewController.copy(_:)) {
			return currentStep != nil
		}
		else if selector == #selector(QBEChainViewController.cancelCalculation(_:)) {
			return self.calculator.calculating
		}
		else if selector == #selector(QBEChainViewController.refreshDataset(_:)) {
			return !self.calculator.calculating
		}
		else {
			return false
		}
	}
	
	@IBAction func removeTablet(_ sender: AnyObject?) {
		if let d = self.delegate, d.chainViewDidClose(self) {
			self.chain = nil
			self.dataViewController = nil
			self.delegate = nil
		}
	}

	@IBAction func delete(_ sender: AnyObject?) {
		self.removeTablet(sender)
	}
	
	@IBAction func removeDuplicateRows(_ sender: NSObject) {
		let step = QBEDistinctStep()
		step.previous = self.currentStep
		suggestSteps([step])
	}
	
	@IBAction func goBack(_ sender: NSObject) {
		// Prevent popping the last step (popStep allows it but goBack doesn't)
		if let p = currentStep?.previous {
			currentStep = p
			updateView()
			calculate()
		}
	}
	
	@IBAction func goForward(_ sender: NSObject) {
		if let n = currentStep?.next {
			currentStep = n
			updateView()
			calculate()
		}
	}
	
	@IBAction func flatten(_ sender: NSObject) {
		suggestSteps([QBEFlattenStep()])
	}
	
	@IBAction func crawl(_ sender: NSObject) {
		let job = Job(.userInitiated)

		calculator.currentRaster?.get(job) {(r) -> () in
			r.maybe { (raster) -> () in
				asyncMain {
					var suggestions: [QBEStep] = []

					// If a column is selected, use that as the column with the source URL
					if let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes, let firstSelectedColumn = selectedColumns.first {
						if firstSelectedColumn < raster.columns.count {
							let columnName = raster.columns[firstSelectedColumn]

							let cs = QBECrawlStep()
							cs.crawler.urlExpression = Sibling(columnName)
							cs.crawler.targetBodyColumn = Column("Content".localized)
							suggestions.append(cs)
						}
					}

					// Is there a column named 'URL' or 'Link'? Then use that
					let candidates = ["URL", "Link", "Page", "URI", "Address"].map { Column($0.localized) }
					for col in candidates {
						if raster.columns.contains(col) {
							let cs = QBECrawlStep()
							cs.crawler.urlExpression = Sibling(col)
							cs.crawler.targetBodyColumn = Column("Content".localized)
							suggestions.append(cs)
						}
					}

					// Suggest a generic crawl step
					if suggestions.isEmpty {
						suggestions.append(QBECrawlStep())
					}

					self.suggestSteps(suggestions)
				}
			}
		}
	}
	
	@IBAction func pivot(_ sender: NSObject) {
		suggestSteps([QBEPivotStep()])
	}
	
	@IBAction func exportFile(_ sender: NSObject) {
		var exts: [String: String] = [:]
		for ext in QBEFactory.sharedInstance.fileExtensionsForWriting {
			let writer = QBEFactory.sharedInstance.fileWriterForType(ext)!
			exts[ext] = writer.explain(ext, locale: self.locale)
		}

		let ns = QBEFilePanel(allowedFileTypes: exts)
		ns.askForSaveFile(self.view.window!) { (urlFallible) -> () in
			urlFallible.maybe { (url) in
				self.exportToFile(url) { err in
					if let e = err {
						Swift.print("Export failed: \(e)")
					}
				}
			}
		}
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		stepsChanged()
		calculate()
		let name = Notification.Name(rawValue: QBEChangeNotification.name)
		NotificationCenter.default.addObserver(self, selector: #selector(QBEChainViewController.changeNotificationReceived(_:)), name: name, object: nil)
	}

	@objc private func changeNotificationReceived(_ notification: Notification) {
		assertMainThread()

		if let changeNotification = notification.object as? QBEChangeNotification {
			// Check if this notification came from ourselves
			if changeNotification.chain == self.chain {
				return
			}

			if let deps = self.chain?.recursiveDependencies {
				for d in deps {
					if d.dependsOn == changeNotification.chain {
						// We depend on the newly calculated data
						self.calculate()
						return
					}
				}
			}
		}
	}

	override func viewWillDisappear() {
		NotificationCenter.default.removeObserver(self)
	}

	override func viewDidAppear() {
		if let sv = self.stepsViewController?.view {
			QBESettings.sharedInstance.showTip("chainView.stepView") {
				self.showTip(NSLocalizedString("In this area, all processing steps that are applied to the data are shown.", comment: ""), atView: sv)
			}
		}

		QBESettings.sharedInstance.showTip("chainView.outlet") {
			self.showTip(NSLocalizedString("See this little circle? Drag it around to copy or move data, or to link data together.", comment: ""), atView: self.outletView)
		}
	}
	
	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		if segue.identifier=="grid" {
			dataViewController = segue.destinationController as? QBEDatasetViewController
			dataViewController?.delegate = self
			dataViewController?.locale = locale
			calculate()
		}
		else if segue.identifier=="steps" {
			stepsViewController = segue.destinationController as? QBEStepsViewController
			stepsViewController?.delegate = self
			stepsChanged()
		}
		super.prepare(for: segue, sender: sender)
	}
	
	@IBAction func paste(_ sender: NSObject) {
		let pboard = NSPasteboard.general()
		
		if let data = pboard.data(forType: QBEStep.dragType) {
			if let step = NSKeyedUnarchiver.unarchiveObject(with: data) as? QBEStep {
				step.previous = nil
				pushStep(step)
			}
		}
	}

	func alterTableView(_ view: QBEAlterTableViewController, didAlterTable: MutableDataset?) {
		assertMainThread()
		self.calculate()
	}

	func columnViewControllerDidRemove(_ controller: QBEColumnViewController, column: Column) {
		self.suggestSteps([
			QBEColumnsStep(previous: nil, columns: [column], select: false)
		])
	}

	func columnViewControllerDidRename(_ controller: QBEColumnViewController, column: Column, to: Column) {
		renameColumn(column, to: to)
	}

	func columnViewControllerDidAutosize(_ controller: QBEColumnViewController, column: Column) {
		self.dataViewController?.sizeColumnToFit(column)
	}

	func columnViewControllerDidSort(_ controller: QBEColumnViewController, column: Column, ascending: Bool) {
		self.sortRowsInColumn(column, ascending: ascending)
	}

	func columnViewControllerSetFullData(_ controller: QBEColumnViewController, fullDataset: Bool) {
		let job = Job(.userInitiated)

		if fullDataset {
			self.currentStep?.fullDataset(job) { result in
				result.maybe { data in
					asyncMain {
						controller.data = data
						controller.isFullDataset = true
						controller.updateDescriptives()
					}
				}
			}
		}
		else {
			self.calculator.currentDataset?.get(job) { result in
				result.maybe { data in
					asyncMain {
						controller.isFullDataset = self.hasFullDataset
						controller.data = data
						controller.updateDescriptives()
					}
				}
			}
		}
	}
}

class QBETipViewController: NSViewController {
	@IBOutlet var messageLabel: NSTextField? = nil
	
	var message: String = "" { didSet {
		messageLabel?.stringValue = message
	} }
	
	override func viewWillAppear() {
		self.messageLabel?.stringValue = message
	}
}

extension URL {
	var isDirectory: Bool { get {
		let p = self.path
		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(atPath: p, isDirectory: &isDirectory) {
			return isDirectory.boolValue
		}
		return false
	} }
}
