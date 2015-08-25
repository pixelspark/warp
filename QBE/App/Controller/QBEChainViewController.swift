import Cocoa

protocol QBESuggestionsViewDelegate: NSObjectProtocol {
	func suggestionsView(view: NSViewController, didSelectStep: QBEStep)
	func suggestionsView(view: NSViewController, didSelectAlternativeStep: QBEStep)
	func suggestionsView(view: NSViewController, previewStep: QBEStep?)
	func suggestionsViewDidCancel(view: NSViewController)
	var currentStep: QBEStep? { get }
	var locale: QBELocale { get }
	var undo: NSUndoManager? { get }
}

class QBEChainView: NSView {
	override var acceptsFirstResponder: Bool { get { return true } }
}

protocol QBEChainViewDelegate: NSObjectProtocol {
	/** Called when the chain view wants the delegate to present a configurator for a step. */
	func chainView(view: QBEChainViewController, configureStep: QBEStep?, delegate: QBESuggestionsViewDelegate)
	
	/** Called when the chain view has a value it wants to present for editing (e.g. in a formula bar). The callback
	 can be called (possibly multiple times) to change the value. If the callback is nil, the value is not changeable. */
	func chainView(view: QBEChainViewController, editValue: QBEValue, callback: ((QBEValue) -> ())?)
	
	/** Called when the user closes a chain view */
	func chainViewDidClose(view: QBEChainViewController)
	
	/** Called when the chain has changed */
	func chainViewDidChangeChain(view: QBEChainViewController)
}

internal extension NSViewController {
	internal func showTip(message: String, atView: NSView) {
		QBEAssertMainThread()
		
		if let vc = self.storyboard?.instantiateControllerWithIdentifier("tipController") as? QBETipViewController {
			vc.message = message
			self.presentViewController(vc, asPopoverRelativeToRect: atView.bounds, ofView: atView, preferredEdge: NSRectEdge.MaxY, behavior: NSPopoverBehavior.Transient)
		}
	}
}

@objc class QBEChainViewController: NSViewController, QBESuggestionsViewDelegate, QBEDataViewDelegate, QBEStepsControllerDelegate, QBEJobDelegate, QBEOutletViewDelegate, QBEOutletDropTarget, QBEFilterViewDelegate {
	private var suggestions: QBEFuture<[QBEStep]>?
	private let calculator: QBECalculator = QBECalculator()
	private var dataViewController: QBEDataViewController?
	private var stepsViewController: QBEStepsViewController?
	private var outletDropView: QBEOutletDropView!
	private var viewFilters: [QBEColumn:QBEFilterSet] = [:]
	
	var outletView: QBEOutletView!
	weak var delegate: QBEChainViewDelegate?
	
	@IBOutlet var addStepMenu: NSMenu?
	
	internal var useFullData: Bool = false {
		didSet {
			if useFullData {
				calculate()
			}
			// TODO: Visually indicate what kind of selection is used
		}
	}
	
	internal var locale: QBELocale { get {
		return QBEAppDelegate.sharedInstance.locale ?? QBELocale()
	} }
	
	dynamic var currentStep: QBEStep? {
		didSet {
			if let s = currentStep {
				self.previewStep = nil				
				delegate?.chainView(self, configureStep: s, delegate: self)
			}
			else {
				delegate?.chainView(self, configureStep: nil, delegate: self)
				self.presentData(nil)
			}
			
			self.stepsViewController?.currentStep = currentStep
			self.stepsChanged()
		}
	}
	
	var previewStep: QBEStep? {
		didSet {
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
	
	override func viewDidLoad() {
		super.viewDidLoad()
		outletView.delegate = self
		outletDropView = QBEOutletDropView(frame: self.view.bounds)
		outletDropView.translatesAutoresizingMaskIntoConstraints = false
		outletDropView.delegate = self
		self.view.addSubview(self.outletDropView, positioned: NSWindowOrderingMode.Above, relativeTo: nil)
		self.view.addConstraints([
			NSLayoutConstraint(item: outletDropView, attribute: NSLayoutAttribute.Top, relatedBy: NSLayoutRelation.Equal, toItem: self.view, attribute: NSLayoutAttribute.Top, multiplier: 1.0, constant: 0.0),
			NSLayoutConstraint(item: outletDropView, attribute: NSLayoutAttribute.Bottom, relatedBy: NSLayoutRelation.Equal, toItem: self.view, attribute: NSLayoutAttribute.Bottom, multiplier: 1.0, constant: 0.0),
			NSLayoutConstraint(item: outletDropView, attribute: NSLayoutAttribute.Left, relatedBy: NSLayoutRelation.Equal, toItem: self.view, attribute: NSLayoutAttribute.Left, multiplier: 1.0, constant: 0.0),
			NSLayoutConstraint(item: outletDropView, attribute: NSLayoutAttribute.Right, relatedBy: NSLayoutRelation.Equal, toItem: self.view, attribute: NSLayoutAttribute.Right, multiplier: 1.0, constant: 0.0)
		])
	}
	
	func receiveDropFromOutlet(draggedObject: AnyObject?) {
		if let myChain = chain {
			if let otherChain = draggedObject as? QBEChain {
				if otherChain == myChain || Array(otherChain.dependencies).map({$0.dependsOn}).contains(myChain) {
					// This would introduce a loop, don't do anything.
				}
				else {
					// Generate sensible joins
					calculator.currentRaster?.get { (r) -> () in
						r.maybe { (raster) -> () in
							let myColumns = raster.columnNames
							
							let job = QBEJob(.UserInitiated)
							otherChain.head?.fullData(job) { (otherDataFallible) -> () in
								otherDataFallible.maybe { (otherData) -> () in
									otherData.columnNames(job) { (otherColumnsFallible) -> () in
										otherColumnsFallible.maybe { (otherColumns) -> () in
											let mySet = Set(myColumns)
											let otherSet = Set(otherColumns)
											
											QBEAsyncMain {
												var joinSteps: [QBEStep] = []
												
												// If the other data set contains exactly the same columns as we do, or one is a subset of the other, propose a merge
												if !mySet.isDisjointWith(otherSet) {
													let overlappingColumns = mySet.intersect(otherSet)
													
													// Create a join step for each column name that appears both left and right
													for overlappingColumn in overlappingColumns {
														let joinStep = QBEJoinStep(previous: nil)
														joinStep.right = otherChain
														joinStep.condition = QBEBinaryExpression(first: QBESiblingExpression(columnName: overlappingColumn), second: QBEForeignExpression(columnName: overlappingColumn), type: QBEBinary.Equal)
														joinSteps.append(joinStep)
													}
													
													joinSteps.append(QBEMergeStep(previous: nil, with: otherChain))
												}
												else {
													if joinSteps.count == 0 {
														let js = QBEJoinStep(previous: nil)
														js.right = otherChain
														js.condition = QBELiteralExpression(QBEValue(false))
														joinSteps.append(js)
													}
												}

												self.suggestSteps(joinSteps)
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
	
	func outletViewDidEndDragging(view: QBEOutletView) {
		view.draggedObject = nil
	}
	
	func outletViewWillStartDragging(view: QBEOutletView) {
		view.draggedObject = self.chain
	}
	
	@IBAction func clearAllFilters(sender: NSObject) {
		self.viewFilters.removeAll()
		calculate()
	}
	
	@IBAction func makeAllFiltersPermanent(sender: NSObject) {
		var args: [QBEExpression] = []
		
		for (column, filterSet) in self.viewFilters {
			args.append(filterSet.expression.expressionReplacingIdentityReferencesWith(QBESiblingExpression(columnName: column)))
		}
		
		self.viewFilters.removeAll()
		if args.count > 0 {
			suggestSteps([QBEFilterStep(previous: currentStep, condition: args.count > 1 ? QBEFunctionExpression(arguments: args, type: QBEFunction.And) : args[0])])
		}
	}
	
	func filterView(view: QBEFilterViewController, applyFilter filter: QBEFilterSet?, permanent: Bool) {
		QBEAssertMainThread()
		
		if let c = view.column {
			if permanent {
				if let realFilter = filter?.expression.expressionReplacingIdentityReferencesWith(QBESiblingExpression(columnName: c)) {
					self.suggestSteps([QBEFilterStep(previous: currentStep, condition: realFilter)])
				}
			}
			else {
				// If filter is nil, the filter is removed from the set of view filters
				self.viewFilters[c] = filter
				calculate()
			}
		}
	}
	
	/** Present the given data set in the data grid. This is called by currentStep.didSet as well as previewStep.didSet.
	The data from the previewed step takes precedence. */
	private func presentData(data: QBEData?) {
		QBEAssertMainThread()
		
		if let d = data {
			if self.dataViewController != nil {
				let job = QBEJob(.UserInitiated)
				
				job.async {
					d.raster(job, callback: { (raster) -> () in
						QBEAsyncMain {
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
	
	func tabletWasSelected() {
		delegate?.chainView(self, configureStep: currentStep, delegate: self)
	}
	
	private func presentRaster(fallibleRaster: QBEFallible<QBERaster>) {
		QBEAssertMainThread()
		
		switch fallibleRaster {
			case .Success(let raster):
				self.presentRaster(raster)
				self.useFullData = false
			
			case .Failure(let errorMessage):
				self.presentRaster(nil)
				self.useFullData = false
				self.dataViewController?.calculating = false
				self.dataViewController?.errorMessage = errorMessage
		}
	}
	
	private func presentRaster(raster: QBERaster?) {
		if let dataView = self.dataViewController {
			dataView.raster = raster
			dataView.hasFullData = (raster != nil && useFullData)
			
			if raster != nil && raster!.rowCount > 0 && !useFullData {
				QBESettings.sharedInstance.showTip("workingSetTip") {
					if let toolbar = self.view.window?.toolbar {
						for item in toolbar.items {
							if item.action == Selector("setFullWorkingSet:") {
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
		QBEAssertMainThread()
		
		if let ch = chain {
			if ch.isPartOfDependencyLoop {
				if let w = self.view.window {
					// TODO: make this message more helpful (maybe even indicate the offending step)
					let a = NSAlert()
					a.messageText = NSLocalizedString("The calculation steps for this data set form a loop, and therefore no data can be calculated.", comment: "")
					a.alertStyle = NSAlertStyle.WarningAlertStyle
					a.beginSheetModalForWindow(w, completionHandler: nil)
				}
				calculator.cancel()
				refreshData()
			}
			else {
				if let s = currentStep {
					calculator.desiredExampleRows = QBESettings.sharedInstance.exampleMaximumRows
					calculator.maximumExampleTime = QBESettings.sharedInstance.exampleMaximumTime
					
					let sourceStep = previewStep ?? s
					
					// Start calculation
					if useFullData {
						calculator.calculate(sourceStep, fullData: useFullData, maximumTime: nil, columnFilters: self.viewFilters)
						refreshData()
					}
					else {
						calculator.calculateExample(sourceStep, maximumTime: nil, columnFilters: self.viewFilters) {
							QBEAsyncMain {
								self.refreshData()
							}
						}
						self.refreshData()
					}
				}
				else {
					calculator.cancel()
					refreshData()
				}
			}
		}
		
		self.view.window?.update() // So that the 'cancel calculation' toolbar button autovalidates
	}
	
	@IBAction func cancelCalculation(sender: NSObject) {
		QBEAssertMainThread()
		calculator.cancel()
		self.view.window?.update()
	}
	
	private func refreshData() {
		self.presentData(nil)
		dataViewController?.calculating = calculator.calculating
		
		let job = calculator.currentRaster?.get { (fallibleRaster) -> () in
			QBEAsyncMain {
				self.presentRaster(fallibleRaster)
				self.useFullData = false
			}
		}
		job?.addObserver(self)
		self.view.window?.update() // So that the 'cancel calculation' toolbar button autovalidates
	}
	
	@objc func job(job: AnyObject, didProgress: Double) {
		self.dataViewController?.progress = didProgress
	}
	
	func stepsController(vc: QBEStepsViewController, didSelectStep step: QBEStep) {
		if currentStep != step {
			currentStep = step
			stepsChanged()
			updateView()
			calculate()
		}
	}
	
	func stepsController(vc: QBEStepsViewController, didRemoveStep step: QBEStep) {
		if step == currentStep {
			popStep()
		}
		remove(step)
		stepsChanged()
		updateView()
		calculate()
		
		undo?.prepareWithInvocationTarget(self).addStep(step)
		undo?.setActionName(NSLocalizedString("Remove step", comment: ""))
	}
	
	func stepsController(vc: QBEStepsViewController, didMoveStep: QBEStep, afterStep: QBEStep?) {
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
				
				if let h = chain?.head where after == h {
					chain?.head = didMoveStep
				}
			}
		}

		stepsChanged()
		updateView()
		calculate()
	}
	
	func stepsController(vc: QBEStepsViewController, didInsertStep step: QBEStep, afterStep: QBEStep?) {
		chain?.insertStep(step, afterStep: afterStep)
		stepsChanged()
	}
	
	// Used for undo for remove step
	@objc func addStep(step: QBEStep) {
		chain?.insertStep(step, afterStep: nil)
		stepsChanged()
	}
	
	func dataView(view: QBEDataViewController, didSelectValue: QBEValue, changeable: Bool) {
		delegate?.chainView(self, editValue: didSelectValue, callback: changeable ? { [weak self] (v) -> () in
			QBEAssertMainThread()
			self?.dataViewController?.changeSelectedValue(v)
		} : nil)
	}
	
	func dataView(view: QBEDataViewController, didOrderColumns columns: [QBEColumn], toIndex: Int) -> Bool {
		// Construct a new column ordering
		if let r = view.raster {
			var allColumns = r.columnNames
			if toIndex < allColumns.count {
				pushStep(QBESortColumnsStep(previous: self.currentStep, sortColumns: columns, before: allColumns[toIndex]))
			}
			else {
				pushStep(QBESortColumnsStep(previous: self.currentStep, sortColumns: columns, before: nil))
			}
			calculate()
			return true
		}
		return false
	}

	func dataView(view: QBEDataViewController, didChangeValue: QBEValue, toValue: QBEValue, inRow: Int, column: Int) -> Bool {
		suggestions?.cancel()
		
		calculator.currentRaster?.get { (fallibleRaster) -> () in
			fallibleRaster.maybe { (raster) -> () in
				self.suggestions = QBEFuture<[QBEStep]>({(job, callback) -> () in
					job.async {
						let expressions = QBECalculateStep.suggest(change: didChangeValue, toValue: toValue, inRaster: raster, row: inRow, column: column, locale: self.locale, job: job)
						callback(expressions.map({QBECalculateStep(previous: self.currentStep, targetColumn: raster.columnNames[column], function: $0)}))
					}
				}, timeLimit: 5.0)
				
				self.suggestions!.get {(steps) -> () in
					QBEAsyncMain {
						self.suggestSteps(steps)
					}
				}
			}
		}
		return false
	}
	
	func dataView(view: QBEDataViewController, hasFilterForColumn column: QBEColumn) -> Bool {
		return self.viewFilters[column] != nil
	}
	
	func dataView(view: QBEDataViewController, filterControllerForColumn column: QBEColumn, callback: (NSViewController) -> ()) {
		if let filterViewController = self.storyboard?.instantiateControllerWithIdentifier("filterView") as? QBEFilterViewController {
			self.calculator.currentData?.get { (data) -> () in
				data.maybe { (d) in
					QBEAsyncMain {
						filterViewController.data = d
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
	
	private func stepsChanged() {
		QBEAssertMainThread()
		self.stepsViewController?.steps = chain?.steps
		self.stepsViewController?.currentStep = currentStep
		updateView()
		self.delegate?.chainViewDidChangeChain(self)
	}
	
	internal var undo: NSUndoManager? { get { return chain?.tablet?.document?.undoManager } }
	
	private func pushStep(var step: QBEStep) {
		QBEAssertMainThread()
		
		let isHead = chain?.head == nil || currentStep == chain?.head
		
		// Check if this step can (or should) be merged with the step it will be appended after
		if let cs = currentStep {
			switch step.mergeWith(cs) {
				case .Impossible:
					break;
				
				case .Possible:
					break;
				
				case .Advised(let merged):
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
				
				case .Cancels:
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
		
		currentStep?.next?.previous = step
		currentStep?.next = step
		step.previous = currentStep
		currentStep = step

		if isHead {
			chain?.head = step
		}
		
		updateView()
		stepsChanged()
	}
	
	private func popStep() {
		currentStep = currentStep?.previous
	}
	
	@IBAction func transposeData(sender: NSObject) {
		if let cs = currentStep {
			suggestSteps([QBETransposeStep(previous: cs)])
		}
	}
	
	func suggestionsView(view: NSViewController, didSelectStep step: QBEStep) {
		previewStep = nil
		pushStep(step)
		stepsChanged()
		updateView()
		calculate()
	}
	
	func suggestionsView(view: NSViewController, didSelectAlternativeStep step: QBEStep) {
		selectAlternativeStep(step)
	}
	
	private func selectAlternativeStep(step: QBEStep) {
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
	}
	
	func suggestionsView(view: NSViewController, previewStep step: QBEStep?) {
		if step == currentStep || step == nil {
			previewStep = nil
		}
		else {
			previewStep = step
		}
		updateView()
		calculate()
	}
	
	func suggestionsViewDidCancel(view: NSViewController) {
		previewStep = nil
		
		// Close any configuration sheets that may be open
		if let s = self.view.window?.attachedSheet {
			self.view.window?.endSheet(s, returnCode: NSModalResponseOK)
		}
		updateView()
		calculate()
	}
	
	private func updateView() {
		QBEAssertMainThread()
		self.view.window?.update()
	}
	
	private func suggestSteps(var steps: Array<QBEStep>) {
		QBEAssertMainThread()
		
		if steps.count == 0 {
			// Alert
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("I have no idea what you did.", comment: "")
			alert.beginSheetModalForWindow(self.view.window!, completionHandler: { (a: NSModalResponse) -> Void in
			})
		}
		else {
			let step = steps.first!
			pushStep(step)
			steps.remove(step)
			step.alternatives = steps
			updateView()
			calculate()
			
			// Show a tip if there are alternatives
			if steps.count > 1 {
				QBESettings.sharedInstance.showTip("suggestionsTip") {
					self.showTip(NSLocalizedString("Warp created a step based on your edits. To select an alternative step, click on the newly added step.", comment: "Tip for suggestions button"), atView: self.stepsViewController!.view)
				}
			}
		}
	}
	
	func stepsController(vc: QBEStepsViewController, showSuggestionsForStep step: QBEStep, atView: NSView?) {
		self.showSuggestionsForStep(step, atView: atView ?? self.stepsViewController?.view ?? self.view)
	}
	
	private func showSuggestionsForStep(step: QBEStep, atView: NSView) {
		QBEAssertMainThread()
		
		if let alternatives = step.alternatives where alternatives.count > 0 {
			if let sv = self.storyboard?.instantiateControllerWithIdentifier("suggestions") as? QBESuggestionsViewController {
				sv.delegate = self
				sv.suggestions = Array(alternatives)
				self.presentViewController(sv, asPopoverRelativeToRect: atView.bounds, ofView: atView, preferredEdge: NSRectEdge.MinY, behavior: NSPopoverBehavior.Semitransient)
			}
		}
	}
	
	@IBAction func showSuggestions(sender: NSObject) {
		if let s = currentStep {
			showSuggestionsForStep(s, atView: self.stepsViewController?.view ?? self.view)
		}
	}
	
	@IBAction func chooseFirstAlternativeStep(sender: NSObject) {
		if let s = currentStep?.alternatives where s.count > 0 {
			selectAlternativeStep(s.first!)
		}
	}
	
	@IBAction func setFullWorkingSet(sender: NSObject) {
		useFullData = true
	}
	
	@IBAction func setSelectionWorkingSet(sender: NSObject) {
		useFullData = false
	}
	
	@IBAction func renameColumn(sender: NSObject) {
		suggestSteps([QBERenameStep(previous: nil)])
	}
	
	private func addColumnBeforeAfterCurrent(before: Bool) {
		calculator.currentData?.get { (d) -> () in
			d.maybe { (data) -> () in
				let job = QBEJob(.UserInitiated)
				
				data.columnNames(job) { (columnNamesFallible) -> () in
					columnNamesFallible.maybe { (cols) -> () in
						if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
							let name = QBEColumn.defaultColumnForIndex(cols.count)
							if before {
								let firstSelectedColumn = selectedColumns.firstIndex
								if firstSelectedColumn != NSNotFound {
									let insertRelative = cols[firstSelectedColumn]
									let step = QBECalculateStep(previous: self.currentStep, targetColumn: name, function: QBELiteralExpression(QBEValue.EmptyValue), insertRelativeTo: insertRelative, insertBefore: true)
									
									QBEAsyncMain {
										self.pushStep(step)
										self.calculate()
									}
								}
								else {
									return
								}
							}
							else {
								let lastSelectedColumn = selectedColumns.lastIndex
								if lastSelectedColumn != NSNotFound && lastSelectedColumn < cols.count {
									let insertAfter = cols[lastSelectedColumn]
									let step = QBECalculateStep(previous: self.currentStep, targetColumn: name, function: QBELiteralExpression(QBEValue.EmptyValue), insertRelativeTo: insertAfter, insertBefore: false)

									QBEAsyncMain {
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
	
	@IBAction func addColumnToRight(sender: NSObject) {
		QBEAssertMainThread()
		addColumnBeforeAfterCurrent(false)
	}
	
	@IBAction func addColumnToLeft(sender: NSObject) {
		QBEAssertMainThread()
		addColumnBeforeAfterCurrent(true)
	}
	
	@IBAction func addColumnAtEnd(sender: NSObject) {
		QBEAssertMainThread()
		
		calculator.currentData?.get {(data) in
			let job = QBEJob(.UserInitiated)
			
			data.maybe {$0.columnNames(job) {(columnsFallible) in
				columnsFallible.maybe { (cols) -> () in
					QBEAsyncMain {
						let name = QBEColumn.defaultColumnForIndex(cols.count)
						let step = QBECalculateStep(previous: self.currentStep, targetColumn: name, function: QBELiteralExpression(QBEValue.EmptyValue), insertRelativeTo: nil, insertBefore: false)
						self.pushStep(step)
						self.calculate()
					}
				}
			}}
		}
	}
	
	@IBAction func addColumnAtBeginning(sender: NSObject) {
		QBEAssertMainThread()
		
		calculator.currentData?.get {(data) in
			let job = QBEJob(.UserInitiated)
			
			data.maybe {$0.columnNames(job) {(columnsFallible) in
				columnsFallible.maybe { (cols) -> () in
					QBEAsyncMain {
						let name = QBEColumn.defaultColumnForIndex(cols.count)
						let step = QBECalculateStep(previous: self.currentStep, targetColumn: name, function: QBELiteralExpression(QBEValue.EmptyValue), insertRelativeTo: nil, insertBefore: true)
						self.pushStep(step)
						self.calculate()
					}
				}
			}}
		}
	}
	
	private func remove(stepToRemove: QBEStep) {
		QBEAssertMainThread()
		
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
	}
	
	@IBAction func copy(sender: NSObject) {
		QBEAssertMainThread()
		
		if let s = currentStep {
			let pboard = NSPasteboard.generalPasteboard()
			pboard.clearContents()
			pboard.declareTypes([QBEStep.dragType], owner: nil)
			let data = NSKeyedArchiver.archivedDataWithRootObject(s)
			pboard.setData(data, forType: QBEStep.dragType)
		}
	}
	
	@IBAction func removeStep(sender: NSObject) {
		if let stepToRemove = currentStep {
			popStep()
			remove(stepToRemove)
			calculate()
			
			undo?.prepareWithInvocationTarget(self).addStep(stepToRemove)
			undo?.setActionName(NSLocalizedString("Remove step", comment: ""))
		}
	}
	
	@IBAction func addDebugStep(sender: NSObject) {
		suggestSteps([QBEDebugStep(previous: self.currentStep)])
	}
	
	private func sortRows(ascending: Bool) {
		if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
			let firstSelectedColumn = selectedColumns.firstIndex
			if firstSelectedColumn != NSNotFound {
				calculator.currentRaster?.get {(r) -> () in
					r.maybe { (raster) -> () in
						let columnName = raster.columnNames[firstSelectedColumn]
						let expression = QBESiblingExpression(columnName: columnName)
						let order = QBEOrder(expression: expression, ascending: ascending, numeric: true)
						
						QBEAsyncMain {
							self.suggestSteps([QBESortStep(previous: self.currentStep, orders: [order])])
						}
					}
				}
			}
		}
	}
	
	@IBAction func reverseSortRows(sender: NSObject) {
		sortRows(false)
	}
	
	@IBAction func sortRows(sender: NSObject) {
		sortRows(true)
	}
	
	@IBAction func selectColumns(sender: NSObject) {
		selectColumns(false)
	}
	
	@IBAction func removeColumns(sender: NSObject) {
		selectColumns(true)
	}
	
	private func selectColumns(remove: Bool) {
		if let colsToRemove = dataViewController?.tableView?.selectedColumnIndexes {
			// Get the names of the columns to remove
			calculator.currentRaster?.get { (raster) -> () in
				raster.maybe { (r) -> () in
					var namesToRemove: [QBEColumn] = []
					var namesToSelect: [QBEColumn] = []
					
					for i in 0..<r.columnNames.count {
						if colsToRemove.containsIndex(i) {
							namesToRemove.append(r.columnNames[i])
						}
						else {
							namesToSelect.append(r.columnNames[i])
						}
					}
					
					QBEAsyncMain {
						self.suggestSteps([
							QBEColumnsStep(previous: self.currentStep, columnNames: namesToRemove, select: !remove),
							QBEColumnsStep(previous: self.currentStep, columnNames: namesToSelect, select: remove)
						])
					}
				}
			}
		}
	}
	
	@IBAction func randomlySelectRows(sender: NSObject) {
		suggestSteps([QBERandomStep(previous: currentStep, numberOfRows: 1)])
	}
	
	@IBAction func limitRows(sender: NSObject) {
		suggestSteps([QBELimitStep(previous: currentStep, numberOfRows: 1)])
	}
	
	@IBAction func removeRows(sender: NSObject) {
		if let rowsToRemove = dataViewController?.tableView?.selectedRowIndexes {
			if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
				calculator.currentRaster?.get { (r) -> () in
					r.maybe { (raster) -> () in
						// Invert the selection
						let selectedToKeep = NSMutableIndexSet()
						let selectedToRemove = NSMutableIndexSet()
						for index in 0..<raster.rowCount {
							if !rowsToRemove.containsIndex(index) {
								selectedToKeep.addIndex(index)
							}
							else {
								selectedToRemove.addIndex(index)
							}
						}
						
						var relevantColumns = Set<QBEColumn>()
						for columnIndex in 0..<raster.columnCount {
							if selectedColumns.containsIndex(columnIndex) {
								relevantColumns.insert(raster.columnNames[columnIndex])
							}
						}
						
						// Find suggestions for keeping the other rows
						let keepSuggestions = QBERowsStep.suggest(selectedToKeep, columns: relevantColumns, inRaster: raster, fromStep: self.currentStep, select: true)
						var removeSuggestions = QBERowsStep.suggest(selectedToRemove, columns: relevantColumns, inRaster: raster, fromStep: self.currentStep, select: false)
						removeSuggestions.appendContentsOf(keepSuggestions)
						
						QBEAsyncMain {
							self.suggestSteps(removeSuggestions)
						}
					}
				}
			}
		}
	}
	
	@IBAction func aggregateRowsByCells(sender: NSObject) {
		if let selectedRows = dataViewController?.tableView?.selectedRowIndexes {
			if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
				calculator.currentRaster?.get { (fallibleRaster) -> ()in
					fallibleRaster.maybe { (raster) -> () in
						var relevantColumns = Set<QBEColumn>()
						for columnIndex in 0..<raster.columnCount {
							if selectedColumns.containsIndex(columnIndex) {
								relevantColumns.insert(raster.columnNames[columnIndex])
							}
						}
						
						let suggestions = QBEPivotStep.suggest(selectedRows, columns: relevantColumns, inRaster: raster, fromStep: self.currentStep)
						
						QBEAsyncMain {
							self.suggestSteps(suggestions)
						}
					}
				}
			}
		}
	}
	
	@IBAction func selectRows(sender: NSObject) {
		if let selectedRows = dataViewController?.tableView?.selectedRowIndexes {
			if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
				calculator.currentRaster?.get { (fallibleRaster) -> () in
					fallibleRaster.maybe { (raster) -> () in
						var relevantColumns = Set<QBEColumn>()
						for columnIndex in 0..<raster.columnCount {
							if selectedColumns.containsIndex(columnIndex) {
								relevantColumns.insert(raster.columnNames[columnIndex])
							}
						}
						
						let suggestions = QBERowsStep.suggest(selectedRows, columns: relevantColumns, inRaster: raster, fromStep: self.currentStep, select: true)
						
						QBEAsyncMain {
							self.suggestSteps(suggestions)
						}
					}
				}
			}
		}
	}
	
	func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
		if item.action()==Selector("transposeData:") {
			return currentStep != nil
		}
		else if item.action()==Selector("clearAllFilters:") {
			return self.viewFilters.count > 0
		}
		else if item.action()==Selector("makeAllFiltersPermanent:") {
			return self.viewFilters.count > 0
		}
		else if item.action()==Selector("crawl:") {
			return currentStep != nil
		}
		else if item.action()==Selector("addDebugStep:") {
			return currentStep != nil
		}
		else if item.action()==Selector("aggregateRowsByCells:") {
			if let rowsToAggregate = dataViewController?.tableView?.selectedRowIndexes {
				return rowsToAggregate.count > 0  && currentStep != nil
			}
			return false
		}
		else if item.action()==Selector("removeRows:") {
			if let rowsToRemove = dataViewController?.tableView?.selectedRowIndexes {
				return rowsToRemove.count > 0  && currentStep != nil
			}
			return false
		}
		else if item.action()==Selector("removeColumns:") {
			if let colsToRemove = dataViewController?.tableView?.selectedColumnIndexes {
				return colsToRemove.count > 0 && currentStep != nil
			}
			return false
		}
		else if item.action()==Selector("renameColumn:") {
			if let colsToRemove = dataViewController?.tableView?.selectedColumnIndexes {
				return colsToRemove.count > 0 && currentStep != nil
			}
			return false
		}
		else if item.action()==Selector("selectColumns:") {
			if let colsToRemove = dataViewController?.tableView?.selectedColumnIndexes {
				return colsToRemove.count > 0 && currentStep != nil
			}
			return false
		}
		else if item.action()==Selector("addColumnAtEnd:") {
			return currentStep != nil
		}
		else if item.action()==Selector("addColumnAtBeginning:") {
			return currentStep != nil
		}
		else if item.action()==Selector("addColumnToLeft:") {
			return currentStep != nil
		}
		else if item.action()==Selector("addColumnToRight:") {
			return currentStep != nil
		}
		else if item.action()==Selector("exportFile:") {
			return currentStep != nil
		}
		else if item.action()==Selector("goBack:") {
			return currentStep?.previous != nil
		}
		else if item.action()==Selector("goForward:") {
			return currentStep?.next != nil
		}
		else if item.action()==Selector("calculate:") {
			return currentStep != nil
		}
		else if item.action()==Selector("randomlySelectRows:") {
			return currentStep != nil
		}
		else if item.action()==Selector("limitRows:") {
			return currentStep != nil
		}
		else if item.action()==Selector("pivot:") {
			return currentStep != nil
		}
		else if item.action()==Selector("flatten:") {
			return currentStep != nil
		}
		else if item.action()==Selector("removeStep:") {
			return currentStep != nil
		}
		else if item.action()==Selector("removeDuplicateRows:") {
			return currentStep != nil
		}
		else if item.action()==Selector("selectRows:") {
			return currentStep != nil
		}
		else if item.action()==Selector("showSuggestions:") {
			return currentStep?.alternatives != nil && currentStep!.alternatives!.count > 0
		}
		else if item.action()==Selector("chooseFirstAlternativeStep:") {
			return currentStep?.alternatives != nil && currentStep!.alternatives!.count > 0
		}
		else if item.action()==Selector("setFullWorkingSet:") {
			return currentStep != nil && !useFullData
		}
		else if item.action()==Selector("setSelectionWorkingSet:") {
			return currentStep != nil && useFullData
		}
		else if item.action()==Selector("sortRows:") {
			return currentStep != nil
		}
		else if item.action()==Selector("reverseSortRows:") {
			return currentStep != nil
		}
		else if item.action() == Selector("removeTablet:") {
			return true
		}
		else if item.action()==Selector("paste:") {
			let pboard = NSPasteboard.generalPasteboard()
			if pboard.dataForType(QBEStep.dragType) != nil {
				return true
			}
			return false
		}
		else if item.action() == Selector("copy:") {
			return currentStep != nil
		}
		else if item.action() == Selector("cancelCalculation:") {
			return self.calculator.calculating
		}
		else {
			return false
		}
	}
	
	@IBAction func removeTablet(sender: NSObject) {
		self.delegate?.chainViewDidClose(self)
		self.chain = nil
		self.dataViewController = nil
		self.delegate = nil
	}
	
	@IBAction func removeDuplicateRows(sender: NSObject) {
		suggestSteps([QBEDistinctStep(previous: self.currentStep)])
	}
	
	@IBAction func goBack(sender: NSObject) {
		// Prevent popping the last step (popStep allows it but goBack doesn't)
		if let p = currentStep?.previous {
			currentStep = p
			updateView()
			calculate()
		}
	}
	
	@IBAction func goForward(sender: NSObject) {
		if let n = currentStep?.next {
			currentStep = n
			updateView()
			calculate()
		}
	}
	
	@IBAction func flatten(sender: NSObject) {
		suggestSteps([QBEFlattenStep(previous: currentStep)])
	}
	
	@IBAction func crawl(sender: NSObject) {
		suggestSteps([QBECrawlStep(previous: currentStep)])
	}
	
	@IBAction func pivot(sender: NSObject) {
		suggestSteps([QBEPivotStep(previous: currentStep)])
	}
	
	@IBAction func exportFile(sender: NSObject) {
		let ns = NSSavePanel()
		ns.allowedFileTypes = QBEFactory.sharedInstance.fileExtensionsForWriting
		let title = chain?.tablet?.document?.displayName ?? NSLocalizedString("Warp data", comment: "")
		
		ns.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
			if result == NSFileHandlingPanelOKButton {
				let job = QBEJob(.UserInitiated)
				// What type of file are we exporting?
				job.async {
					if let cs = self.currentStep {
						cs.fullData(job) { (fallibleData: QBEFallible<QBEData>) -> () in
							switch fallibleData {
								case .Success(let data):
									if let url = ns.URL, let ext = url.pathExtension {
										// Get the file writer for this type
										if let writer = QBEFactory.sharedInstance.fileWriterForType(ext, locale: self.locale, title: title) {
											writer.writeData(data, toFile: url, job: job, callback: {(result) -> () in
												QBEAsyncMain {
													let alert = NSAlert()
													
													switch result {
														case .Success():
															alert.messageText = String(format: NSLocalizedString("The data has been successfully saved to '%@'.", comment: ""), url.absoluteString ?? "")
														
														case .Failure(let e):
															alert.messageText = String(format: NSLocalizedString("The data could not be saved to '%@': %@.", comment: ""), url.absoluteString ?? "", e)
													}
													
													alert.beginSheetModalForWindow(self.view.window!, completionHandler: nil)
												}
											})
										}
									}
								
								case .Failure(let errorMessage):
									QBEAsyncMain {
										let alert = NSAlert()
										alert.messageText = errorMessage
										alert.beginSheetModalForWindow(self.view.window!, completionHandler: nil)
									}
							}
						}
					}
				}
			}
		})
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		stepsChanged()
		calculate()
	}
	
	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier=="grid" {
			dataViewController = segue.destinationController as? QBEDataViewController
			dataViewController?.delegate = self
			dataViewController?.locale = locale
			calculate()
		}
		else if segue.identifier=="steps" {
			stepsViewController = segue.destinationController as? QBEStepsViewController
			stepsViewController?.delegate = self
			stepsChanged()
		}
		super.prepareForSegue(segue, sender: sender)
	}
	
	@IBAction func paste(sender: NSObject) {
		let pboard = NSPasteboard.generalPasteboard()
		
		if let data = pboard.dataForType(QBEStep.dragType) {
			if let step = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? QBEStep {
				step.previous = nil
				pushStep(step)
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