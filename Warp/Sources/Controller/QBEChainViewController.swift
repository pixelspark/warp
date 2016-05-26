import Cocoa
import WarpCore

class QBEChainView: NSView {
	override var acceptsFirstResponder: Bool { get { return true } }

	override func becomeFirstResponder() -> Bool {
		return true
	}

	override var allowsVibrancy: Bool { return true }
}

protocol QBEChainViewDelegate: NSObjectProtocol {
	/** Called when the chain view wants the delegate to present a configurator for a step. If 'necessary' is set to true,
	the step needs configuration right now in order to work. */
	func chainView(view: QBEChainViewController, configureStep: QBEStep?, necessary: Bool, delegate: QBESentenceViewDelegate)
	
	/** Called when the user closes a chain view. If it returns false, the removal is blocked. */
	func chainViewDidClose(view: QBEChainViewController) -> Bool
	
	/** Called when the chain has changed */
	func chainViewDidChangeChain(view: QBEChainViewController)

	/** Called when the chain view wants to export the chain (e.g. what would normally be accomplished by dragging out 
	the outlet to another place outside the tablet). */
	func chainView(view: QBEChainViewController, exportChain: QBEChain)
}

internal extension NSViewController {
	internal func showTip(message: String, atView: NSView) {
		assertMainThread()
		
		if let vc = self.storyboard?.instantiateControllerWithIdentifier("tipController") as? QBETipViewController {
			vc.message = message
			self.presentViewController(vc, asPopoverRelativeToRect: atView.bounds, ofView: atView, preferredEdge: NSRectEdge.MaxY, behavior: NSPopoverBehavior.Transient)
		}
	}
}

internal enum QBEEditingMode {
	case NotEditing
	case EnablingEditing
	case Editing(identifiers: Set<Column>?, editingRaster: Raster)
}

@objc class QBEChainViewController: NSViewController, QBESuggestionsViewDelegate, QBESentenceViewDelegate,
	QBEDataViewDelegate, QBEStepsControllerDelegate, JobDelegate, QBEOutletViewDelegate, QBEOutletDropTarget,
	QBEFilterViewDelegate, QBEExportViewDelegate, QBEAlterTableViewDelegate,
	QBEColumnViewDelegate {

	private var suggestions: Future<[QBEStep]>?
	private let calculator: QBECalculator = QBECalculator()
	private var dataViewController: QBEDataViewController?
	private var stepsViewController: QBEStepsViewController?
	private var outletDropView: QBEOutletDropView!
	private var hasFullData = false
	private var filterControllerJob: Job? = nil

	var outletView: QBEOutletView!
	weak var delegate: QBEChainViewDelegate?
	
	@IBOutlet var addStepMenu: NSMenu?
	
	internal var useFullData: Bool = false {
		didSet {
			if useFullData {
				calculate()
			}
		}
	}

	internal var editingMode: QBEEditingMode = .NotEditing {
		didSet {
			assertMainThread()
			self.updateView()
		}
	}

	internal var supportsEditing: Bool {
		if let r = self.calculator.currentRaster?.result {
			if case .Failure(_) = r {
				return false
			}

			if let _ = self.currentStep?.mutableData {
				return true
			}
		}
		return false
	}
	
	internal var locale: Locale { get {
		return QBEAppDelegate.sharedInstance.locale ?? Locale()
	} }
	
	dynamic var currentStep: QBEStep? {
		didSet {
			self.editingMode = .NotEditing
			if let s = currentStep {
				self.previewStep = nil				
				delegate?.chainView(self, configureStep: s, necessary: false, delegate: self)
			}
			else {
				delegate?.chainView(self, configureStep: nil, necessary: false, delegate: self)
				self.presentData(nil)
			}
			
			self.stepsViewController?.currentStep = currentStep
			self.stepsChanged()
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
			self.editingMode = .NotEditing
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
		// Present a drop down menu and add steps depending on the option selected by the user.
		class QBEDropChainAction: NSObject {
			let view: QBEChainViewController
			let otherChain: QBEChain

			init(view: QBEChainViewController, chain: QBEChain) {
				self.otherChain = chain
				self.view = view
			}

			@objc func unionChains(sender: AnyObject) {
				self.view.suggestSteps([QBEMergeStep(previous: nil, with: self.otherChain)])
			}


			@objc func uploadData(sender: AnyObject) {
				if let sourceStep = self.otherChain.head, let destStep = self.view.currentStep, let destMutable = destStep.mutableData where destMutable.canPerformMutation(.Import(data: RasterData(), withMapping: [:])) {
					let uploadView = self.view.storyboard?.instantiateControllerWithIdentifier("uploadData") as! QBEUploadViewController
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
			@objc private func joinWithClassifier(sender: NSObject) {
				asyncMain {
					let classifyStep = QBEClassifierStep(previous: nil)
					classifyStep.right = self.otherChain
					self.view.suggestSteps([classifyStep])
				}
			}

			@objc func joinChains(sender: AnyObject) {
				// Generate sensible join options
				self.view.calculator.currentRaster?.get { (r) -> () in
					r.maybe { (raster) -> () in
						let myColumns = raster.columns

						let job = Job(.UserInitiated)
						self.otherChain.head?.fullData(job) { (otherDataFallible) -> () in
							otherDataFallible.maybe { (otherData) -> () in
								otherData.columns(job) { (otherColumnsFallible) -> () in
									otherColumnsFallible.maybe { (otherColumns) -> () in
										let mySet = Set(myColumns)
										let otherSet = Set(otherColumns)

										asyncMain {
											var configureStep: QBEStep? = nil
											var joinSteps: [QBEStep] = []

											// If the other data set contains exactly the same columns as we do, or one is a subset of the other, propose a merge
											if !mySet.isDisjointWith(otherSet) {
												let overlappingColumns = mySet.intersect(otherSet)

												// Create a join step for each column name that appears both left and right
												for overlappingColumn in overlappingColumns {
													let joinStep = QBEJoinStep(previous: nil)
													joinStep.right = self.otherChain
													joinStep.condition = Comparison(first: Sibling(overlappingColumn), second: Foreign(overlappingColumn), type: Binary.Equal)
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

				if let destStep = self.view.currentStep, let destMutable = destStep.mutableData where destMutable.canPerformMutation(.Import(data: RasterData(), withMapping: [:])) {
					dropMenu.addItem(NSMenuItem.separatorItem())
					let createItem = NSMenuItem(title: destStep.sentence(self.view.locale, variant: .Write).stringValue + "...", action: #selector(QBEDropChainAction.uploadData(_:)), keyEquivalent: "")
					createItem.target = self
					dropMenu.addItem(createItem)
				}

				NSMenu.popUpContextMenu(dropMenu, withEvent: NSApplication.sharedApplication().currentEvent!, forView: self.view.view)
			}
		}

		if let myChain = chain {
			if let otherChain = draggedObject as? QBEChain {
				if otherChain == myChain {
					// Drop on self, just ignore
				}
				else if Array(otherChain.recursiveDependencies).map({$0.dependsOn}).contains(myChain) {
					// This would introduce a loop, don't do anything.
					NSAlert.showSimpleAlert("The data set cannot be linked to this data set".localized, infoText: "Linking the data set to this data set would introduce a loop where the outcome of a calculation would depend on itself.".localized, style: .CriticalAlertStyle, window: self.view.window)
				}
				else {
					let ca = QBEDropChainAction(view: self, chain: otherChain)
					ca.presentMenu()
				}
			}
		}
	}

	func outletViewWasClicked(view: QBEOutletView) {
		if let c = self.chain {
			self.delegate?.chainView(self, exportChain: c)
		}
		view.draggedObject = nil
	}
	
	func outletViewDidEndDragging(view: QBEOutletView) {
		view.draggedObject = nil
	}

	private func exportToFile(url: NSURL) {
		let writerType: QBEFileWriter.Type
		if let ext = url.pathExtension {
			writerType = QBEFactory.sharedInstance.fileWriterForType(ext) ?? QBECSVWriter.self
		}
		else {
			writerType = QBECSVWriter.self
		}

		let title = self.chain?.tablet?.displayName ?? NSLocalizedString("Warp data", comment: "")
		let s = QBEExportStep(previous: currentStep, writer: writerType.init(locale: self.locale, title: title), file: QBEFileReference.URL(url))

		if let editorController = self.storyboard?.instantiateControllerWithIdentifier("exportEditor") as? QBEExportViewController {
			editorController.step = s
			editorController.delegate = self
			editorController.locale = self.locale
			self.presentViewControllerAsSheet(editorController)
		}
	}

	func exportView(view: QBEExportViewController, didAddStep step: QBEExportStep) {
		chain?.insertStep(step, afterStep: self.currentStep)
		self.currentStep = step
		stepsChanged()
	}

	func outletView(view: QBEOutletView, didDropAtURL url: NSURL) {
		if let isd = url.isDirectory where isd {
			// Ask for a file rather than a directory
			var exts: [String: String] = [:]
			for ext in QBEFactory.sharedInstance.fileExtensionsForWriting {
				let writer = QBEFactory.sharedInstance.fileWriterForType(ext)!
				exts[ext] = writer.explain(ext, locale: self.locale)
			}

			let no = QBEFilePanel(allowedFileTypes: exts)
			no.askForSaveFile(self.view.window!) { (fileFallible) in
				fileFallible.maybe { (url) in
					self.exportToFile(url)
				}
			}
		}
		else {
			self.exportToFile(url)
		}
	}

	func outletViewWillStartDragging(view: QBEOutletView) {
		view.draggedObject = self.chain
	}
	
	@IBAction func clearAllFilters(sender: NSObject) {
		self.viewFilters.removeAll()
		calculate()
	}
	
	@IBAction func makeAllFiltersPermanent(sender: NSObject) {
		var args: [Expression] = []
		
		for (column, filterSet) in self.viewFilters {
			args.append(filterSet.expression.expressionReplacingIdentityReferencesWith(Sibling(column)))
		}
		
		self.viewFilters.removeAll()
		if args.count > 0 {
			suggestSteps([QBEFilterStep(previous: currentStep, condition: args.count > 1 ? Call(arguments: args, type: Function.And) : args[0])])
		}
	}
	
	func filterView(view: QBEFilterViewController, didChangeFilter filter: FilterSet?) {
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
	private func presentData(data: Data?) {
		assertMainThread()
		
		if let d = data {
			if self.dataViewController != nil {
				let job = Job(.UserInitiated)
				
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

	private func presentRaster(fallibleRaster: Fallible<Raster>) {
		assertMainThread()
		
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
	
	private func presentRaster(raster: Raster?) {
		if let dataView = self.dataViewController {
			dataView.raster = raster
			hasFullData = (raster != nil && useFullData)

			// Fade any changes in smoothly
			if raster == nil {
				let tr = CATransition()
				tr.duration = 0.3
				tr.type = kCATransitionFade
				tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
				self.outletView.layer?.addAnimation(tr, forKey: kCATransition)
			}
			self.outletView.enabled = raster != nil
			
			if raster != nil && raster!.rowCount > 0 && !useFullData {
				if let toolbar = self.view.window?.toolbar {
					toolbar.validateVisibleItems()
					self.view.window?.update()
					QBESettings.sharedInstance.showTip("workingSetTip") {
						for item in toolbar.items {
							if item.action == #selector(QBEChainViewController.toggleFullData(_:)) {
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
						calculator.calculate(sourceStep, fullData: useFullData, maximumTime: nil)
						refreshData()
					}
					else {
						calculator.calculateExample(sourceStep, maximumTime: nil) {
							asyncMain {
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
		assertMainThread()
		if calculator.calculating {
			calculator.cancel()
			self.presentRaster(.Failure(NSLocalizedString("The calculation was cancelled.", comment: "")))
		}
		self.useFullData = false
		self.view.window?.update()
		self.view.window?.toolbar?.validateVisibleItems()
	}
	
	private func refreshData() {
		self.presentData(nil)
		dataViewController?.calculating = calculator.calculating
		
		let job = calculator.currentRaster?.get { (fallibleRaster) -> () in
			asyncMain {
				self.presentRaster(fallibleRaster)
				self.useFullData = false
				self.view.window?.toolbar?.validateVisibleItems()
				self.view.window?.update()
			}
		}
		job?.addObserver(self)
		self.view.window?.toolbar?.validateVisibleItems()
		self.view.window?.update() // So that the 'cancel calculation' toolbar button autovalidates
	}
	
	@objc func job(job: AnyObject, didProgress: Double) {
		asyncMain {
			self.outletView.progress = didProgress
			self.dataViewController?.progress = didProgress
		}
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
		
		(undo?.prepareWithInvocationTarget(self) as? QBEChainViewController)?.addStep(step)
		undo?.setActionName(NSLocalizedString("Remove step", comment: ""))

		if let c = chain {
			QBEChangeNotification.broadcastChange(c)
		}
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

		if let c = chain {
			QBEChangeNotification.broadcastChange(c)
		}
	}
	
	func stepsController(vc: QBEStepsViewController, didInsertStep step: QBEStep, afterStep: QBEStep?) {
		chain?.insertStep(step, afterStep: afterStep)
		stepsChanged()

		if let c = chain {
			QBEChangeNotification.broadcastChange(c)
		}
	}
	
	// Used for undo for remove step
	@objc func addStep(step: QBEStep) {
		chain?.insertStep(step, afterStep: nil)
		stepsChanged()

		if let c = chain {
			QBEChangeNotification.broadcastChange(c)
		}
	}
	
	func dataView(view: QBEDataViewController, didSelectValue: Value, changeable: Bool) {
	}
	
	func dataView(view: QBEDataViewController, didOrderColumns columns: [Column], toIndex: Int) -> Bool {
		// Construct a new column ordering
		if let r = view.raster where toIndex >= 0 && toIndex < r.columns.count {
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
				if let beforeIndex = allColumns.indexOf(beforeColumn) {
					allColumns.insertContentsOf(columns, at: beforeIndex)
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
	func dataView(view: QBEDataViewController, addValue value: Value, inRow: Int?, column: Int?, callback: (Bool) -> ()) {
		var value = value

		suggestions?.cancel()

		switch self.editingMode {
		case .NotEditing:
			if let row = inRow {
				// If we are not editing the source data, the only thing that can be done is calculate a new column
				calculator.currentRaster?.get { (fallibleRaster) -> () in
					fallibleRaster.maybe { (raster) -> () in
						let targetColumn = Column.defaultNameForNewColumn(raster.columns)

						self.suggestions = Future<[QBEStep]>({(job, callback) -> () in
							job.async {
								let expressions = QBECalculateStep.suggest(change: nil, toValue: value, inRaster: raster, row: row, column: nil, locale: self.locale, job: job)
								callback(expressions.map({QBECalculateStep(previous: self.currentStep, targetColumn: targetColumn, function: $0)}))
							}
						}, timeLimit: 5.0)

						self.suggestions!.get {(steps) -> () in
							asyncMain {
								self.suggestSteps(steps)
							}
						}
					}
				}
			}

		case .Editing(identifiers: _, editingRaster: let editingRaster):
			// If a formula was typed in, calculate the result first
			if let f = Formula(formula: value.stringValue ?? "", locale: locale) where !(f.root is Literal) && !(f.root is Identity) {
				let row = inRow == nil ? Row() : editingRaster[inRow!]
				value = f.root.apply(row, foreign: nil, inputValue: nil)
			}

			// If we are in editing mode, the new value will actually be added to the source data set.
			if let md = self.currentStep?.mutableData {
				let job = Job(.UserInitiated)

				md.columns(job) { result in
					switch result {
					case .Success(let columns):
						if let cn = column {
							// The edit made was inside the range of current columns. No need to add a new column, just a new row
							if cn >= 0 && cn <= columns.count {
								let columnName = columns[cn]
								let row = Row([value], columns: [columnName])
								let mutation = DataMutation.Insert(row: row)
								md.performMutation(mutation, job: job) { result in
									switch result {
									case .Success:
										/* The mutation has been performed on the source data, now perform it on our own
										temporary raster as well. We could also call self.calculate() here, but that takes
										a while, and we would lose our current scrolling position, etc. */
										RasterMutableData(raster: editingRaster).performMutation(mutation, job: job) { result in
											QBEChangeNotification.broadcastChange(self.chain!)
											asyncMain {
												self.presentRaster(editingRaster)
												self.dataViewController?.sizeColumnToFit(columnName)
												callback(true)
											}
										}
										break

									case .Failure(let e):
										asyncMain {
											callback(false)
											NSAlert.showSimpleAlert(NSLocalizedString("Cannot create new row.", comment: ""), infoText: e, style: .CriticalAlertStyle, window: self.view.window)
										}
									}
								}
							}
						}
						else {
							// need to add a new column first
							var columns = columns
							let newColumnName = Column.defaultNameForNewColumn(columns)
							columns.append(newColumnName)
							let mutation = DataMutation.Alter(DataDefinition(columns: columns))
							md.performMutation(mutation, job: job) { result in
								switch result {
								case .Success:
									/* The mutation has been performed on the source data, now perform it on our own
									temporary raster as well. We could also call self.calculate() here, but that takes
									a while, and we would lose our current scrolling position, etc. */
									RasterMutableData(raster: editingRaster).performMutation(mutation, job: job) { result in
										QBEChangeNotification.broadcastChange(self.chain!)

										asyncMain {
											self.presentRaster(editingRaster)

											if let rn = inRow {
												self.dataView(view, didChangeValue: Value.EmptyValue, toValue: value, inRow: rn, column: columns.count-1)
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

								case .Failure(let e):
									asyncMain {
										callback(false)
										NSAlert.showSimpleAlert(NSLocalizedString("Cannot create new column.", comment: ""), infoText: e, style: .CriticalAlertStyle, window: self.view.window)
									}
								}
							}
						}
					case .Failure(let e):
						asyncMain {
							NSAlert.showSimpleAlert(NSLocalizedString("Cannot create new row.", comment: ""), infoText: e, style: .CriticalAlertStyle, window: self.view.window)
						}
					}
				}
			}

		default:
			return
		}
	}

	private func removeRowsPermanently(rows: [Int]) {
		let errorMessage = rows.count > 1 ? "Cannot remove these rows".localized : "Cannot remove this row".localized

		// In editing mode, we perform the edit on the mutable data set
		if let md = self.currentStep?.mutableData, case .Editing(identifiers: let identifiers, editingRaster: let editingRaster) = self.editingMode {
			let job = Job(.UserInitiated)
			md.data(job) { result in
				// Does the data set support deleting by row number, or do we edit by key?
				let removeMutation = DataMutation.Remove(rows: rows)
				if md.canPerformMutation(removeMutation) {
					job.async {
						md.performMutation(removeMutation, job: job) { result in
							switch result {
							case .Success:
								/* The mutation has been performed on the source data, now perform it on our own
								temporary raster as well. We could also call self.calculate() here, but that takes
								a while, and we would lose our current scrolling position, etc. */
								RasterMutableData(raster: editingRaster).performMutation(removeMutation, job: job) { result in
									QBEChangeNotification.broadcastChange(self.chain!)
									asyncMain {
										self.presentRaster(editingRaster)
									}
								}
								break

							case .Failure(let e):
								asyncMain {
									NSAlert.showSimpleAlert(errorMessage, infoText: e, style: .CriticalAlertStyle, window: self.view.window)
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

						let deleteMutation = DataMutation.Delete(keys: keys)

						job.async {
							md.performMutation(deleteMutation, job: job) { result in
								switch result {
								case .Success():
									/* The mutation has been performed on the source data, now perform it on our own
									temporary raster as well. We could also call self.calculate() here, but that takes
									a while, and we would lose our current scrolling position, etc. */
									RasterMutableData(raster: editingRaster).performMutation(deleteMutation, job: job) { result in
										QBEChangeNotification.broadcastChange(self.chain!)
										asyncMain {
											self.presentRaster(editingRaster)
										}
									}
									break

								case .Failure(let e):
									asyncMain {
										NSAlert.showSimpleAlert(errorMessage, infoText: e, style: .CriticalAlertStyle, window: self.view.window)
									}
								}
							}
						}
					}
					else {
						// We cannot change the data because we cannot do it by row number and we don't have a sure primary key
						// TODO: ask the user what key to use ("what property makes each row unique?")
						asyncMain {
							NSAlert.showSimpleAlert(errorMessage, infoText: "There is not enough information to be able to distinguish rows.".localized, style: .CriticalAlertStyle, window: self.view.window)
						}
					}
				}
			}
		}
	}

	private func editValue(oldValue: Value, toValue: Value, inRow: Int, column: Int, identifiers: Set<Column>?) {
		var toValue = toValue
		let errorMessage = String(format: NSLocalizedString("Cannot change '%@' to '%@'", comment: ""), oldValue.stringValue ?? "", toValue.stringValue ?? "")

		// In editing mode, we perform the edit on the mutable data set
		if let md = self.currentStep?.mutableData, case .Editing(identifiers:_, editingRaster: let editingRaster) = self.editingMode {
			// If a formula was typed in, calculate the result first
			if let f = Formula(formula: toValue.stringValue ?? "", locale: locale) where !(f.root is Literal) && !(f.root is Identity) {
				toValue = f.root.apply(editingRaster[inRow], foreign: nil, inputValue: oldValue)
			}

			let job = Job(.UserInitiated)
			md.data(job) { result in
				switch result {
				case .Success(let data):
					data.columns(job) { result in
						switch result {
						case .Success(let columns):
							// Does the data set support editing by row number, or do we edit by key?
							let editMutation = DataMutation.Edit(row: inRow, column: columns[column], old: oldValue, new: toValue)
							if md.canPerformMutation(editMutation) {
								job.async {
									md.performMutation(editMutation, job: job) { result in
										switch result {
										case .Success:
											/* The mutation has been performed on the source data, now perform it on our own
											temporary raster as well. We could also call self.calculate() here, but that takes
											a while, and we would lose our current scrolling position, etc. */
												RasterMutableData(raster: editingRaster).performMutation(editMutation, job: job) { result in
													QBEChangeNotification.broadcastChange(self.chain!)

													asyncMain {
														self.presentRaster(editingRaster)
													}
												}
											break

										case .Failure(let e):
											asyncMain {
												NSAlert.showSimpleAlert(errorMessage, infoText: e, style: .CriticalAlertStyle, window: self.view.window)
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

									let mutation = DataMutation.Update(key: key, column: editingRaster.columns[column], old: oldValue, new: toValue)
									job.async {
										md.performMutation(mutation, job: job) { result in
											switch result {
											case .Success():
												/* The mutation has been performed on the source data, now perform it on our own
												temporary raster as well. We could also call self.calculate() here, but that takes
												a while, and we would lose our current scrolling position, etc. */
												RasterMutableData(raster: editingRaster).performMutation(editMutation, job: job) { result in
													QBEChangeNotification.broadcastChange(self.chain!)

													asyncMain {
														self.presentRaster(editingRaster)
													}
												}
												break

											case .Failure(let e):
												asyncMain {
													NSAlert.showSimpleAlert(errorMessage, infoText: e, style: .CriticalAlertStyle, window: self.view.window)
												}
											}
										}
									}
								}
								else {
									// We cannot change the data because we cannot do it by row number and we don't have a sure primary key
									// TODO: ask the user what key to use ("what property makes each row unique?")
									asyncMain {
										NSAlert.showSimpleAlert(errorMessage, infoText: NSLocalizedString("There is not enough information to be able to distinguish rows.", comment: ""), style: .CriticalAlertStyle, window: self.view.window)
									}
								}
							}

						case .Failure(let e):
							asyncMain {
								NSAlert.showSimpleAlert(errorMessage, infoText: e, style: .CriticalAlertStyle, window: self.view.window)
							}
						}
					}

				case .Failure(let e):
					asyncMain {
						NSAlert.showSimpleAlert(errorMessage, infoText: e, style: .CriticalAlertStyle, window: self.view.window)
					}
				}

			}
		}
	}

	func dataView(view: QBEDataViewController, didRenameColumn column: Column, to: Column) {
		self.renameColumn(column, to: to)
	}

	private func renameColumn(column: Column, to: Column) {
		switch self.editingMode {
		case .NotEditing:
			// Make a suggestion
			suggestSteps([
				QBERenameStep(previous: self.currentStep, renames: [column: to])
				])
			break

		case .Editing(_):
			// Actually edit
			let errorText = String(format: NSLocalizedString("Could not rename column '%@' to '%@'", comment: ""), column.name, to.name)
			if let md = self.currentStep?.mutableData {
				let mutation = DataMutation.Rename([column: to])
				let job = Job(.UserInitiated)
				if md.canPerformMutation(mutation) {
					md.performMutation(mutation, job: job, callback: { result in
						switch result {
						case .Success(_):
							asyncMain {
								self.calculate()
							}

						case .Failure(let e):
							asyncMain {
								NSAlert.showSimpleAlert(errorText, infoText: e, style: .CriticalAlertStyle, window: self.view.window)
							}
						}
					})
				}
				else {
					NSAlert.showSimpleAlert(errorText, infoText: NSLocalizedString("The columns of this data set cannot be renamed.", comment: ""), style: .CriticalAlertStyle, window: self.view.window)
				}
			}
			break

		case .EnablingEditing:
			break
		}
	}

	func dataView(view: QBEDataViewController, didChangeValue oldValue: Value, toValue: Value, inRow: Int, column: Int) -> Bool {
		suggestions?.cancel()

		switch self.editingMode {
		case .NotEditing:
			// In non-editing mode, we make a suggestion for a calculation
			calculator.currentRaster?.get { (fallibleRaster) -> () in
				fallibleRaster.maybe { (raster) -> () in
					self.suggestions = Future<[QBEStep]>({(job, callback) -> () in
						job.async {
							let expressions = QBECalculateStep.suggest(change: oldValue, toValue: toValue, inRaster: raster, row: inRow, column: column, locale: self.locale, job: job)
							callback(expressions.map({QBECalculateStep(previous: self.currentStep, targetColumn: raster.columns[column], function: $0)}))
						}
					}, timeLimit: 5.0)

					self.suggestions!.get { steps in
						asyncMain {
							self.suggestSteps(steps, afterChanging: oldValue, to: toValue, inColumn: column, inRow: inRow)
						}
					}
				}
			}

		case .Editing(identifiers: let identifiers, editingRaster: _):
			self.editValue(oldValue, toValue: toValue, inRow: inRow, column: column, identifiers: identifiers)
			return true

		case .EnablingEditing:
			return false

		}
		return false
	}

	func dataView(view: QBEDataViewController, viewControllerForColumn column: Column, info: Bool, callback: (NSViewController) -> ()) {
		if info {
			if let popover = self.storyboard?.instantiateControllerWithIdentifier("columnPopup") as? QBEColumnViewController {
				self.calculator.currentData?.get { result in
					result.maybe { data in
						asyncMain {
							popover.column = column
							popover.data = data
							popover.isFullData = self.hasFullData
							popover.delegate = self
							callback(popover)
						}
					}
				}
			}
		}
		else {
			filterControllerJob?.cancel()
			let job = Job(.UserInitiated)
			filterControllerJob = job
			let sourceStep = (currentStep is QBEFilterSetStep) ? currentStep?.previous : currentStep

			sourceStep?.fullData(job) { result in
				result.maybe { fullData in
					sourceStep?.exampleData(job, maxInputRows: self.calculator.maximumExampleInputRows, maxOutputRows: self.calculator.desiredExampleRows) { result in
						result.maybe { exampleData in
							asyncMain {
								if let filterViewController = self.storyboard?.instantiateControllerWithIdentifier("filterView") as? QBEFilterViewController {
									filterViewController.data = exampleData
									filterViewController.searchData = fullData
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

	func dataView(view: QBEDataViewController, hasFilterForColumn column: Column) -> Bool {
		return self.viewFilters[column] != nil
	}
	
	private func stepsChanged() {
		assertMainThread()
		self.editingMode = .NotEditing
		self.stepsViewController?.steps = chain?.steps
		self.stepsViewController?.currentStep = currentStep
		updateView()
		self.delegate?.chainViewDidChangeChain(self)
	}
	
	internal var undo: NSUndoManager? { get { return chain?.tablet?.document?.undoManager } }
	
	private func pushStep(step: QBEStep) {
		var step = step
		assertMainThread()
		
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

		if let c = self.chain {
			QBEChangeNotification.broadcastChange(c)
		}
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

		if let c = self.chain {
			QBEChangeNotification.broadcastChange(c)
		}
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
	
	private func updateView() {
		assertMainThread()

		switch self.editingMode {
		case .Editing(identifiers: _):
			// In editing mode, rows and columns can be added
			self.dataViewController?.showNewRow = true
			self.dataViewController?.showNewColumn = true

		case .NotEditing:
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

	private func suggestSteps(steps: [QBEStep], afterChanging from: Value, to: Value, inColumn: Int, inRow: Int) {
		assertMainThread()

		let supportsEditing = self.currentStep?.mutableData != nil && self.supportsEditing

		if supportsEditing {
			let alert = NSAlert()
			alert.alertStyle = NSAlertStyle.InformationalAlertStyle
			alert.messageText = String(format: "Changing '%@' to '%@'".localized, self.locale.localStringFor(to), self.locale.localStringFor(from))
			alert.informativeText = "Warp can either change the value permanently in the source data set, or add a step that performs the change for all values in the column similarly.".localized
			alert.addButtonWithTitle("Add step".localized)
			alert.addButtonWithTitle("Change source data".localized)
			alert.addButtonWithTitle("Cancel".localized)
			alert.showsSuppressionButton = false

			alert.beginSheetModalForWindow(self.view.window!, completionHandler: { res in
				switch res {
				case NSAlertFirstButtonReturn:
					self.suggestSteps(steps)

				case NSAlertSecondButtonReturn:
					self.startEditingWithCallback {
						switch self.editingMode {
						case .Editing(identifiers: let ids, editingRaster: _):
							self.editValue(from, toValue: to, inRow: inRow, column: inColumn, identifiers: ids)

						case .NotEditing, .EnablingEditing:
							let message = String(format: "Cannot change '%@' to '%@'".localized, self.locale.localStringFor(to), self.locale.localStringFor(from))
							NSAlert.showSimpleAlert(message, infoText: "The data set cannot be edited".localized, style: .CriticalAlertStyle, window: self.view.window)
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

	private func suggestSteps(steps: [QBEStep]) {
		assertMainThread()
		
		if steps.isEmpty {
			// Alert
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("I have no idea what you did.", comment: "")
			alert.beginSheetModalForWindow(self.view.window!, completionHandler: { (a: NSModalResponse) -> Void in
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

	func sentenceView(view: QBESentenceViewController, didChangeConfigurable configurable: QBEConfigurable) {
		updateView()
		calculate()
		if let c = self.chain {
			QBEChangeNotification.broadcastChange(c)
		}
	}
	
	func stepsController(vc: QBEStepsViewController, showSuggestionsForStep step: QBEStep, atView: NSView?) {
		self.showSuggestionsForStep(step, atView: atView ?? self.stepsViewController?.view ?? self.view)
	}
	
	private func showSuggestionsForStep(step: QBEStep, atView: NSView) {
		assertMainThread()
		
		if let alternatives = step.alternatives where alternatives.count > 0 {
			if let sv = self.storyboard?.instantiateControllerWithIdentifier("suggestionsList") as? QBESuggestionsListViewController {
				sv.delegate = self
				sv.suggestions = Array(alternatives)
				self.presentViewController(sv, asPopoverRelativeToRect: atView.bounds, ofView: atView, preferredEdge: NSRectEdge.MaxX, behavior: NSPopoverBehavior.Semitransient)
			}
		}
	}
	
	@IBAction func showSuggestions(sender: NSObject) {
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
				let job = Job(.UserInitiated)
				
				data.columns(job) { (columnNamesFallible) -> () in
					columnNamesFallible.maybe { (cols) -> () in
						if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
							let name = Column.defaultNameForNewColumn(cols)
							if before {
								let firstSelectedColumn = selectedColumns.firstIndex
								if firstSelectedColumn != NSNotFound {
									let insertRelative = cols[firstSelectedColumn]
									let step = QBECalculateStep(previous: self.currentStep, targetColumn: name, function: Literal(Value.EmptyValue), insertRelativeTo: insertRelative, insertBefore: true)
									
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
								let lastSelectedColumn = selectedColumns.lastIndex
								if lastSelectedColumn != NSNotFound && lastSelectedColumn < cols.count {
									let insertAfter = cols[lastSelectedColumn]
									let step = QBECalculateStep(previous: self.currentStep, targetColumn: name, function: Literal(Value.EmptyValue), insertRelativeTo: insertAfter, insertBefore: false)

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
	
	@IBAction func addColumnToRight(sender: NSObject) {
		assertMainThread()
		addColumnBeforeAfterCurrent(false)
	}
	
	@IBAction func addColumnToLeft(sender: NSObject) {
		assertMainThread()
		addColumnBeforeAfterCurrent(true)
	}
	
	@IBAction func addColumnAtEnd(sender: NSObject) {
		assertMainThread()
		
		calculator.currentData?.get {(data) in
			let job = Job(.UserInitiated)
			
			data.maybe {$0.columns(job) {(columnsFallible) in
				columnsFallible.maybe { (cols) -> () in
					asyncMain {
						let name = Column.defaultNameForNewColumn(cols)
						let step = QBECalculateStep(previous: self.currentStep, targetColumn: name, function: Literal(Value.EmptyValue), insertRelativeTo: nil, insertBefore: false)
						self.pushStep(step)
						self.calculate()
					}
				}
			}}
		}
	}
	
	@IBAction func addColumnAtBeginning(sender: NSObject) {
		assertMainThread()
		
		calculator.currentData?.get {(data) in
			let job = Job(.UserInitiated)
			
			data.maybe {$0.columns(job) {(columnsFallible) in
				columnsFallible.maybe { (cols) -> () in
					asyncMain {
						let name = Column.defaultNameForNewColumn(cols)
						let step = QBECalculateStep(previous: self.currentStep, targetColumn: name, function: Literal(Value.EmptyValue), insertRelativeTo: nil, insertBefore: true)
						self.pushStep(step)
						self.calculate()
					}
				}
			}}
		}
	}
	
	private func remove(stepToRemove: QBEStep) {
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
	
	@IBAction func copy(sender: NSObject) {
		assertMainThread()
		
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
			
			(undo?.prepareWithInvocationTarget(self) as? QBEChainViewController)?.addStep(stepToRemove)
			undo?.setActionName(NSLocalizedString("Remove step", comment: ""))
		}
	}
	
	@IBAction func addDebugStep(sender: NSObject) {
		suggestSteps([QBEDebugStep()])
	}
	
	private func sortRows(ascending: Bool) {
		assertMainThread()

		if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
			let firstSelectedColumn = selectedColumns.firstIndex
			if firstSelectedColumn != NSNotFound {
				calculator.currentRaster?.get {(r) -> () in
					r.maybe { (raster) -> () in
						if firstSelectedColumn < raster.columns.count {
							let columnName = raster.columns[firstSelectedColumn]
							self.sortRowsInColumn(columnName, ascending: ascending)
						}
					}
				}
			}
		}
	}

	private func sortRowsInColumn(column: Column, ascending: Bool) {
		let expression = Sibling(column)
		let order = Order(expression: expression, ascending: ascending, numeric: true)

		asyncMain {
			self.suggestSteps([QBESortStep(previous: self.currentStep, orders: [order])])
		}
	}

	@IBAction func reverseSortRows(sender: NSObject) {
		sortRows(false)
	}
	
	@IBAction func sortRows(sender: NSObject) {
		sortRows(true)
	}

	@IBAction func explodeColumn(sender: NSObject) {
		assertMainThread()

		if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
			let firstSelectedColumn = selectedColumns.firstIndex
			if firstSelectedColumn != NSNotFound {
				calculator.currentRaster?.get {(r) -> () in
					r.maybe { (raster) -> () in
						if firstSelectedColumn < raster.columns.count {
							let columnName = raster.columns[firstSelectedColumn]
							asyncMain {
								self.suggestSteps([QBEExplodeStep(previous: self.currentStep, splitColumn: columnName)])
							}
						}
					}
				}
			}
		}
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
					var namesToRemove: [Column] = []
					var namesToSelect: [Column] = []
					
					for i in 0..<r.columns.count {
						if colsToRemove.containsIndex(i) {
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
	
	@IBAction func randomlySelectRows(sender: NSObject) {
		suggestSteps([QBERandomStep(previous: currentStep, numberOfRows: 1)])
	}
	
	@IBAction func limitRows(sender: NSObject) {
		suggestSteps([QBELimitStep(previous: currentStep, numberOfRows: 1)])
	}
	
	@IBAction func removeRows(sender: NSObject) {
		switch self.editingMode {
		case .Editing(identifiers: _, editingRaster: _):
			if let rowsToRemove = dataViewController?.tableView?.selectedRowIndexes {
				self.removeRowsPermanently(Array(rowsToRemove))
			}

		case .NotEditing:
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

							var relevantColumns = Set<Column>()
							for columnIndex in 0..<raster.columns.count {
								if selectedColumns.containsIndex(columnIndex) {
									relevantColumns.insert(raster.columns[columnIndex])
								}
							}

							// Find suggestions for keeping the other rows
							let keepSuggestions = QBERowsStep.suggest(selectedToKeep, columns: relevantColumns, inRaster: raster, fromStep: self.currentStep, select: true)
							var removeSuggestions = QBERowsStep.suggest(selectedToRemove, columns: relevantColumns, inRaster: raster, fromStep: self.currentStep, select: false)
							removeSuggestions.appendContentsOf(keepSuggestions)

							asyncMain {
								self.suggestSteps(removeSuggestions)
							}
						}
					}
				}
			}

		case .EnablingEditing:
			return
		}
	}

	@IBAction func aggregateRowsByGroup(sender: NSObject) {
		if let selectedColumns = dataViewController?.tableView?.selectedColumnIndexes {
			let job = Job(.UserInitiated)

			calculator.currentRaster?.get(job) { result in
				switch result {
				case .Success(let raster):
					let step = QBEPivotStep()
					var selectedColumnNames: [Column] = []
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

				case .Failure(let e):
					asyncMain {
						NSAlert.showSimpleAlert("The selection cannot be aggregated".localized, infoText: e, style: .CriticalAlertStyle, window: self.view.window)
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
						var relevantColumns = Set<Column>()
						for columnIndex in 0..<raster.columns.count {
							if selectedColumns.containsIndex(columnIndex) {
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
	
	@IBAction func selectRows(sender: NSObject) {
		if let selectedRows = dataViewController?.tableView?.selectedRowIndexes {
			if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
				calculator.currentRaster?.get { (fallibleRaster) -> () in
					fallibleRaster.maybe { (raster) -> () in
						var relevantColumns = Set<Column>()
						for columnIndex in 0..<raster.columns.count {
							if selectedColumns.containsIndex(columnIndex) {
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

	private func performMutation(mutation: DataMutation) {
		assertMainThread()
		guard let cs = currentStep, let store = cs.mutableData where store.canPerformMutation(mutation) else {
			let a = NSAlert()
			a.messageText = NSLocalizedString("The selected action cannot be performed on this data set.", comment: "")
			a.alertStyle = NSAlertStyle.WarningAlertStyle
			if let w = self.view.window {
				a.beginSheetModalForWindow(w, completionHandler: nil)
			}
			return
		}

		let confirmationAlert = NSAlert()

		switch mutation {
		case .Truncate:
			confirmationAlert.messageText = NSLocalizedString("Are you sure you want to remove all rows in the source data set?", comment: "")

		case .Drop:
			confirmationAlert.messageText = NSLocalizedString("Are you sure you want to completely remove the source data set?", comment: "")

		default: fatalError("Mutation not supported here")
		}

		confirmationAlert.informativeText = NSLocalizedString("This will modify the original data, and cannot be undone.", comment: "")
		confirmationAlert.alertStyle = NSAlertStyle.InformationalAlertStyle
		let yesButton = confirmationAlert.addButtonWithTitle(NSLocalizedString("Perform modifications", comment: ""))
		let noButton = confirmationAlert.addButtonWithTitle(NSLocalizedString("Cancel", comment: ""))
		yesButton.tag = 1
		noButton.tag = 2
		confirmationAlert.beginSheetModalForWindow(self.view.window!) { (response) -> Void in
			if response == 1 {
				// Confirmed
				let job = Job(.UserInitiated)

				// Register this job with the background job manager
				let name: String
				switch mutation {
				case .Truncate: name = NSLocalizedString("Truncate data set", comment: "")
				case .Drop: name = NSLocalizedString("Remove data set", comment: "")
				default: fatalError("Mutation not supported here")
				}
				QBEAppDelegate.sharedInstance.jobsManager.addJob(job, description: name)

				// Start the mutation
				store.performMutation(mutation, job: job) { result in
					asyncMain {
						switch result {
						case .Success:
							//NSAlert.showSimpleAlert(NSLocalizedString("Command completed successfully", comment: ""), style: NSAlertStyle.InformationalAlertStyle, window: self.view.window!)
							self.useFullData = false
							self.calculate()

						case .Failure(let e):
							NSAlert.showSimpleAlert(NSLocalizedString("The selected action cannot be performed on this data set.",comment: ""), infoText: e, style: NSAlertStyle.WarningAlertStyle, window: self.view.window!)

						}
					}
				}
			}
		}
	}

	@IBAction func alterStore(sender: NSObject) {
		if let md = self.currentStep?.mutableData where md.canPerformMutation(.Alter(DataDefinition(columns: []))) {
			let alterViewController = QBEAlterTableViewController()
			alterViewController.mutableData = md
			alterViewController.warehouse = md.warehouse
			alterViewController.delegate = self

			// Get current column names
			let job = Job(.UserInitiated)
			md.data(job) { result in
				switch result {
				case .Success(let data):
					data.columns(job) { result in
						switch result {
							case .Success(let columns):
								asyncMain {
									alterViewController.definition = DataDefinition(columns: columns)
									self.presentViewControllerAsSheet(alterViewController)
								}

							case .Failure(let e):
								asyncMain {
									NSAlert.showSimpleAlert(NSLocalizedString("Could not modify table", comment: ""), infoText: e, style: .CriticalAlertStyle, window: self.view.window)
								}
						}
					}

				case .Failure(let e):
					asyncMain {
						NSAlert.showSimpleAlert(NSLocalizedString("Could not modify table", comment: ""), infoText: e, style: .CriticalAlertStyle, window: self.view.window)
					}
				}
			}
		}
	}

	@IBAction func truncateStore(sender: NSObject) {
		self.performMutation(.Truncate)
	}

	@IBAction func dropStore(sender: NSObject) {
		self.performMutation(.Drop)
	}

	@IBAction func startEditing(sender: NSObject) {
		self.startEditingWithCallback()
	}

	private func startEditingWithCallback(callback: (() -> ())? = nil) {
		let forceCustomKeySelection = self.view.window?.currentEvent?.modifierFlags.contains(.AlternateKeyMask) ?? false

		if let md = self.currentStep?.mutableData where self.supportsEditing {
			self.editingMode = .EnablingEditing
			let job = Job(.UserInitiated)
			md.identifier(job) { result in
				asyncMain {
					switch self.editingMode {
					case .EnablingEditing:
						if case .Success(let ids) = result where ids != nil && !forceCustomKeySelection {
							self.startEditingWithIdentifier(ids!, callback: callback)
						}
						else if !forceCustomKeySelection && md.canPerformMutation(DataMutation.Edit(row: 0, column: Column("a"), old: Value.InvalidValue, new: Value.InvalidValue)) {
							// This data set does not have key columns, but this isn't an issue, as it can be edited by row number
							self.startEditingWithIdentifier([], callback: callback)
						}
						else {
							// Cannot start editing right now
							self.editingMode = .NotEditing

							md.columns(job) { columnsResult in
								switch columnsResult {
								case .Success(let columns):
									asyncMain {
										let ctr = self.storyboard?.instantiateControllerWithIdentifier("keyViewController") as! QBEKeySelectionViewController
										ctr.columns = columns

										if case .Success(let ids) = result where ids != nil {
											ctr.keyColumns = ids!
										}

										ctr.callback = { keys in
											asyncMain {
												self.startEditingWithIdentifier(keys, callback: callback)
											}
										}

										self.presentViewControllerAsSheet(ctr)
									}

								case .Failure(let e):
									NSAlert.showSimpleAlert(NSLocalizedString("This data set cannot be edited.", comment: ""), infoText: e, style: .WarningAlertStyle, window: self.view.window)
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
	editing (DataMutation.Edit). */
	private func startEditingWithIdentifier(ids: Set<Column>, callback: (() -> ())? = nil) {
		asyncMain {
			switch self.editingMode {
			case .EnablingEditing, .NotEditing:
				self.calculator.currentRaster?.get { result in
					switch result {
					case .Success(let editingRaster):
						asyncMain {
							self.editingMode = .Editing(identifiers: ids, editingRaster: editingRaster.clone(false))
							self.view.window?.update()
							callback?()
						}

					case .Failure(let e):
						asyncMain {
							NSAlert.showSimpleAlert(NSLocalizedString("This data set cannot be edited.", comment: ""), infoText: e, style: .WarningAlertStyle, window: self.view.window)
							self.editingMode = .NotEditing
							callback?()
						}
					}
				}

			case .Editing(identifiers: _, editingRaster: _):
				// Already editing
				callback?()
				break
			}
			self.view.window?.update()
		}
	}

	@IBAction func stopEditing(sender: NSObject) {
		self.editingMode = .NotEditing
		self.calculate()
		self.view.window?.update()
	}

	@IBAction func toggleEditing(sender: NSObject) {
		switch editingMode {
		case .EnablingEditing, .Editing(identifiers: _):
			self.stopEditing(sender)

		case .NotEditing:
			self.startEditing(sender)
		}
	}

	@IBAction func toggleFullData(sender: NSObject) {
		useFullData = !(useFullData || hasFullData)
		hasFullData = false
		self.view.window?.update()
	}

	@IBAction func refreshData(sender: NSObject) {
		if !useFullData && hasFullData {
			useFullData = true
		}
		else {
			self.calculate()
		}
	}

	override func validateToolbarItem(item: NSToolbarItem) -> Bool {
		if item.action == #selector(QBEChainViewController.toggleFullData(_:)) {
			if let c = item.view as? NSButton {
				c.state = (currentStep != nil && (hasFullData || useFullData)) ? NSOnState: NSOffState
			}
		}
		else if item.action == #selector(QBEChainViewController.toggleEditing(_:)) {
			if let c = item.view as? NSButton {
				switch self.editingMode {
				case .Editing(_):
					c.state = NSOnState

				case .EnablingEditing:
					c.state = NSMixedState

				case .NotEditing:
					c.state = NSOffState
				}
			}
		}

		return validateSelector(item.action)
	}
	
	func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
		return validateSelector(item.action())
	}

	private func validateSelector(selector: Selector) -> Bool {
		if selector == #selector(QBEChainViewController.transposeData(_:)) {
			return currentStep != nil
		}
		else if selector == #selector(QBEChainViewController.truncateStore(_:))  {
			switch editingMode {
			case .Editing:
				if let cs = self.currentStep?.mutableData where cs.canPerformMutation(.Truncate) {
					return true
				}
				return false

			default:
				return false
			}
		}
		else if selector == #selector(QBEChainViewController.dropStore(_:))  {
			switch editingMode {
			case .Editing:
				if let cs = self.currentStep?.mutableData where cs.canPerformMutation(.Drop) {
					return true
				}
				return false

			default:
				return false
			}
		}
		else if selector == #selector(QBEChainViewController.alterStore(_:))  {
			switch editingMode {
			case .Editing:
				if let cs = self.currentStep?.mutableData where cs.canPerformMutation(.Alter(DataDefinition(columns: []))) {
					return true
				}
				return false

			default:
				return false
			}
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
			return currentStep != nil && !useFullData
		}
		else if selector==#selector(QBEChainViewController.toggleFullData(_:)) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.toggleEditing(_:)) {
			return currentStep != nil && supportsEditing
		}
		else if selector==#selector(QBEChainViewController.startEditing(_:)) {
			switch self.editingMode {
			case .Editing(identifiers: _), .EnablingEditing:
				return false
			case .NotEditing:
				return currentStep != nil && supportsEditing
			}
		}
		else if selector==#selector(QBEChainViewController.stopEditing(_:)) {
			switch self.editingMode {
			case .Editing(identifiers: _), .EnablingEditing:
				return true
			case .NotEditing:
				return false
			}
		}
		else if selector==#selector(QBEChainViewController.setSelectionWorkingSet(_:)) {
			return currentStep != nil && useFullData
		}
		else if selector==#selector(QBEChainViewController.sortRows(_:) as (QBEChainViewController) -> (NSObject) -> ()) {
			return currentStep != nil
		}
		else if selector==#selector(QBEChainViewController.explodeColumn(_:)) {
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
			let pboard = NSPasteboard.generalPasteboard()
			if pboard.dataForType(QBEStep.dragType) != nil {
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
		else if selector == #selector(QBEChainViewController.refreshData(_:)) {
			return !self.calculator.calculating
		}
		else {
			return false
		}
	}
	
	@IBAction func removeTablet(sender: AnyObject?) {
		if let d = self.delegate where d.chainViewDidClose(self) {
			self.chain = nil
			self.dataViewController = nil
			self.delegate = nil
		}
	}

	@IBAction func delete(sender: AnyObject?) {
		self.removeTablet(sender)
	}
	
	@IBAction func removeDuplicateRows(sender: NSObject) {
		let step = QBEDistinctStep()
		step.previous = self.currentStep
		suggestSteps([step])
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
		suggestSteps([QBEFlattenStep()])
	}
	
	@IBAction func crawl(sender: NSObject) {
		suggestSteps([QBECrawlStep()])
	}
	
	@IBAction func pivot(sender: NSObject) {
		suggestSteps([QBEPivotStep()])
	}
	
	@IBAction func exportFile(sender: NSObject) {
		var exts: [String: String] = [:]
		for ext in QBEFactory.sharedInstance.fileExtensionsForWriting {
			let writer = QBEFactory.sharedInstance.fileWriterForType(ext)!
			exts[ext] = writer.explain(ext, locale: self.locale)
		}

		let ns = QBEFilePanel(allowedFileTypes: exts)
		ns.askForSaveFile(self.view.window!) { (urlFallible) -> () in
			urlFallible.maybe { (url) in
				self.exportToFile(url)
			}
		}
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		stepsChanged()
		calculate()
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(QBEChainViewController.changeNotificationReceived(_:)), name: QBEChangeNotification.name, object: nil)
	}

	@objc private func changeNotificationReceived(notification: NSNotification) {
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
		NSNotificationCenter.defaultCenter().removeObserver(self)
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

	func alterTableView(view: QBEAlterTableViewController, didAlterTable: MutableData?) {
		assertMainThread()
		self.calculate()
	}

	func columnViewControllerDidRemove(controller: QBEColumnViewController, column: Column) {
		self.suggestSteps([
			QBEColumnsStep(previous: nil, columns: [column], select: false)
		])
	}

	func columnViewControllerDidRename(controller: QBEColumnViewController, column: Column, to: Column) {
		renameColumn(column, to: to)
	}

	func columnViewControllerDidAutosize(controller: QBEColumnViewController, column: Column) {
		self.dataViewController?.sizeColumnToFit(column)
	}

	func columnViewControllerDidSort(controller: QBEColumnViewController, column: Column, ascending: Bool) {
		self.sortRowsInColumn(column, ascending: ascending)
	}

	func columnViewControllerSetFullData(controller: QBEColumnViewController, fullData: Bool) {
		let job = Job(.UserInitiated)

		if fullData {
			self.currentStep?.fullData(job) { result in
				result.maybe { data in
					asyncMain {
						controller.data = data
						controller.isFullData = true
						controller.updateDescriptives()
					}
				}
			}
		}
		else {
			self.calculator.currentData?.get(job) { result in
				result.maybe { data in
					asyncMain {
						controller.isFullData = self.hasFullData
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

extension NSURL {
	var isDirectory: Bool? { get {
		if let p = self.path {
			var isDirectory: ObjCBool = false
			if NSFileManager.defaultManager().fileExistsAtPath(p, isDirectory: &isDirectory) {
				return isDirectory.boolValue
			}
		}
		return nil
	} }
}