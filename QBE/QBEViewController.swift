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

class QBEViewController: NSViewController, QBESuggestionsViewDelegate, QBEDataViewDelegate, QBEStepsControllerDelegate, QBEJobDelegate {
	var dataViewController: QBEDataViewController?
	var stepsViewController: QBEStepsViewController?
	weak var windowController: QBEWindowController?
	
	@IBOutlet var descriptionField: NSTextField?
	@IBOutlet var configuratorView: NSView?
	@IBOutlet var titleLabel: NSTextField?
	@IBOutlet var addStepMenu: NSMenu?
	@IBOutlet var suggestionsButton: NSButton?
	
	internal var currentData: QBEFuture<QBEData>?
	internal var currentRaster: QBEFuture<QBERaster>?
	
	internal var useFullData: Bool = false {
		didSet {
			if useFullData != oldValue {
				calculate()
				dataViewController?.workingSetSelector?.selectedSegment = (useFullData ? 1 : 0)
			}
		}
	}
	
	internal var locale: QBELocale { get {
		return QBEAppDelegate.sharedInstance.locale ?? QBELocale()
	} }
	
	var configuratorViewController: NSViewController? {
		willSet(newValue) {
			if let s = configuratorViewController {
				s.removeFromParentViewController()
				s.view.removeFromSuperview()
			}
		}
		
		didSet {
			if let vc = configuratorViewController {
				if let cv = configuratorView {
					self.addChildViewController(vc)
					vc.view.translatesAutoresizingMaskIntoConstraints = false
					vc.view.frame = cv.bounds
					self.configuratorView?.addSubview(vc.view)
					
					cv.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:|[CTRL_VIEW]|", options: NSLayoutFormatOptions.allZeros, metrics: nil, views: ["CTRL_VIEW": vc.view]))
					
					cv.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|[CTRL_VIEW]|", options: NSLayoutFormatOptions.allZeros, metrics: nil, views: ["CTRL_VIEW": vc.view]))
				}
			}
		}
	}
	
	dynamic var currentStep: QBEStep? {
		didSet {
			if let s = currentStep {
				self.previewStep = nil
				let className = s.className
				let StepView = QBEStepViews[className]?(step: s, delegate: self)
				self.configuratorViewController = StepView
				calculate()
			}
			else {
				self.configuratorViewController = nil
				self.titleLabel?.attributedStringValue = NSAttributedString(string: "")
				self.presentData(nil)
			}
			
			self.stepsViewController?.currentStep = currentStep
			self.view.window?.update()
			updateView()
		}
	}
	
	var previewStep: QBEStep? {
		didSet {
			if previewStep != currentStep?.previous {
				previewStep?.previous = currentStep?.previous
			}
			
			if oldValue != nil && previewStep == nil {
				refreshData()
			}
			else {
				previewStep?.exampleData(nil, callback: { (d) -> () in
					self.presentData(d)
				})
			}
		}
	}
	
	var document: QBEDocument? {
		didSet {
			self.currentStep = document?.head
			stepsChanged()
		}
	}
	
	
	/** Present the given data set in the data grid. This is called by currentStep.didSet as well as previewStep.didSet.
	The data from the previewed step takes precedence. **/
	private func presentData(data: QBEData?) {
		/* TODO: when calculation takes long, it should be cancelled before a new calculation is started. Otherwise the
		contents of the first calculation may be displayed before the second. Perhaps work out a way to cancel
		calculations.*/
		if let d = data {
			if let dataView = self.dataViewController {
				QBEAsyncBackground {
					d.raster(nil, callback: { (raster) -> () in
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
	
	private func presentRaster(raster: QBERaster?) {
		if let dataView = self.dataViewController {
			dataView.raster = raster
			
			if raster != nil && raster!.rowCount > 0 {
				if let btn = self.dataViewController?.workingSetSelector {
					QBESettings.sharedInstance.once("workingSetTip") {
						self.showTip(NSLocalizedString("By default, Warp shows you a small part of the data. Using this button, you can toggle between the full data and the working selection.",comment: "Working set selector tip"), atView: btn)
					}
				}
			}
		}
	}
	
	func calculate() {
		if let s = currentStep {
			currentData?.cancel()
			currentRaster?.cancel()
			
			currentData = QBEFuture<QBEData>(useFullData ? s.fullData : s.exampleData)
			
			currentRaster = QBEFuture<QBERaster>({(job: QBEJob?, callback: QBEFuture<QBERaster>.Callback) in
				if let cd = self.currentData {
					cd.get({ (data: QBEData) -> () in
						data.raster(job, callback: callback)
					})
				}
			})
		}
		else {
			currentData = nil
			currentRaster = nil
		}
		
		refreshData()
	}
	
	private func refreshData() {
		self.presentData(nil)
		dataViewController?.calculating = (currentRaster != nil)
		
		let job = currentRaster?.get({(raster) in
			QBEAsyncMain {
				self.presentRaster(raster)
			}
		})
		job?.delegate = self
	}
	
	func job(job: QBEJob, didProgress: Double) {
		self.dataViewController?.progress = didProgress
	}
	
	func stepsController(vc: QBEStepsViewController, didSelectStep step: QBEStep) {
		if currentStep != step {
			currentStep = step
		}
	}
	
	func stepsController(vc: QBEStepsViewController, didRemoveStep step: QBEStep) {
		if step == currentStep {
			popStep()
		}
		remove(step)
	}

	func dataView(view: QBEDataViewController, didChangeValue: QBEValue, toValue: QBEValue, inRow: Int, column: Int) -> Bool {
		currentRaster?.get({(raster) in
			QBEAsyncBackground {
				let expressions = QBECalculateStep.suggest(change: didChangeValue, toValue: toValue, inRaster: raster, row: inRow, column: column, locale: self.locale)
				let steps = expressions.map({QBECalculateStep(previous: self.currentStep, targetColumn: raster.columnNames[column], function: $0)})
				
				QBEAsyncMain {
					self.suggestSteps(steps)
				}
			}
		})
		return false
	}
	
	private func stepsChanged() {
		self.stepsViewController?.steps = document?.steps
		self.stepsViewController?.currentStep = currentStep
		updateView()
	}
	
	internal var undo: NSUndoManager? { get { return document?.undoManager } }
	
	private func pushStep(step: QBEStep) {
		currentStep?.next?.previous = step
		currentStep?.next = step
		step.previous = currentStep
		
		if document?.head == nil || currentStep == document?.head {
			document?.head = step
		}
		currentStep = step
		stepsChanged()
		
		(undo?.prepareWithInvocationTarget(self) as? QBEViewController)?.removeStep(step)
		undo?.setActionName(String(format: NSLocalizedString("Add step '%@'", comment: ""), step.explain(locale, short: true)))
	}
	
	private func popStep() {
		currentStep = currentStep?.previous
		stepsChanged()
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
			document?.head = step
		}
		else {
			next!.previous = step
			step.next = next
		}
		stepsChanged()
	}
	
	func suggestionsView(view: NSViewController, previewStep step: QBEStep?) {
		if step == currentStep || step == nil {
			previewStep = nil
			calculate()
		}
		else {
			previewStep = step
		}
		updateView()
	}
	
	func suggestionsViewDidCancel(view: NSViewController) {
		previewStep = nil
		
		// Close any configuration sheets that may be open
		if let s = self.view.window?.attachedSheet {
			self.view.window?.endSheet(s, returnCode: NSModalResponseOK)
		}
		updateView()
	}
	
	private func updateView() {
		self.suggestionsButton?.hidden = currentStep == nil
		self.suggestionsButton?.enabled = currentStep?.alternatives != nil && currentStep!.alternatives!.count > 0
		
		if let s = currentStep {
			self.titleLabel?.attributedStringValue = NSAttributedString(string: s.explain(locale))
		}
		
		self.view.window?.update()
	}
	
	private func suggestSteps(var steps: Array<QBEStep>) {
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
			
			// Show a tip if there are alternatives
			if steps.count > 1 {
				QBESettings.sharedInstance.once("suggestionsTip") {
					self.showTip(NSLocalizedString("Warp created a step based on your edits. To select an alternative step, click here.", comment: "Tip for suggestions button"), atView: self.suggestionsButton!)
				}
			}
		}
	}
	
	private func showTip(message: String, atView: NSView) {
		if let vc = self.storyboard?.instantiateControllerWithIdentifier("tipController") as? QBETipViewController {
			vc.message = message
			let popover = NSPopover()
			popover.contentViewController = vc
			popover.behavior = NSPopoverBehavior.Transient
			popover.showRelativeToRect(atView.bounds, ofView: atView, preferredEdge: NSMaxYEdge)
		}
	}
	
	@IBAction func showSuggestions(sender: NSObject) {
		if let s = currentStep?.alternatives where s.count > 0 {
			self.performSegueWithIdentifier("suggestions", sender: sender)
		}
	}
	
	@IBAction func chooseFirstAlternativeStep(sender: NSObject) {
		if let s = currentStep?.alternatives where s.count > 0 {
			selectAlternativeStep(s.first!)
		}
	}
	
	@IBAction func addColumn(sender: NSObject) {
		self.performSegueWithIdentifier("addColumn", sender: sender)
	}
	
	@IBAction func setWorkingSet(sender: NSObject) {
		if let sc = sender as? NSSegmentedControl {
			useFullData = (sc.selectedSegment == 1);
		}
	}
	
	@IBAction func setFullWorkingSet(sender: NSObject) {
		useFullData = true
	}
	
	@IBAction func setSelectionWorkingSet(sender: NSObject) {
		useFullData = false
	}
	
	@IBAction func addEmptyColumn(sender: NSObject) {
		currentData?.get({(data) in
			data.columnNames({(cols) in
				let step = QBECalculateStep(previous: self.currentStep, targetColumn: QBEColumn.defaultColumnForIndex(cols.count), function: QBELiteralExpression(QBEValue.EmptyValue))
				self.pushStep(step)
			})
		})
	}
	
	private func remove(stepToRemove: QBEStep) {
		let previous = stepToRemove.previous
		previous?.next = stepToRemove.next
		
		if let next = stepToRemove.next {
			next.previous = previous
			stepToRemove.next = nil
		}
		
		if document?.head == stepToRemove {
			document?.head = stepToRemove.previous
		}
		
		stepToRemove.previous = nil
		stepsChanged()
	}
	
	@IBAction func removeStep(sender: NSObject) {
		if let stepToRemove = currentStep {
			popStep()
			removeStep(stepToRemove)
		}
	}
	
	private func sortRows(ascending: Bool) {
		if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
			let firstSelectedColumn = selectedColumns.firstIndex
			if firstSelectedColumn != NSNotFound {
				currentStep?.exampleData(nil, callback: { (data: QBEData) -> () in
					data.columnNames({(columnNames) -> () in
						let columnName = columnNames[firstSelectedColumn]
						let expression = QBESiblingExpression(columnName: columnName)
						let order = QBEOrder(expression: expression, ascending: ascending, numeric: true)
						self.pushStep(QBESortStep(previous: self.currentStep, orders: [order]))
					})
				})
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
			currentStep?.exampleData(nil, callback: { (data: QBEData) -> () in
				var namesToRemove: [QBEColumn] = []
				var namesToSelect: [QBEColumn] = []
				
				data.columnNames({ (columnNames) -> () in
					for i in 0..<columnNames.count {
						if colsToRemove.containsIndex(i) {
							namesToRemove.append(columnNames[i])
						}
						else {
							namesToSelect.append(columnNames[i])
						}
					}
					
					QBEAsyncMain {
						self.suggestSteps([
							QBEColumnsStep(previous: self.currentStep, columnNames: namesToRemove, select: !remove),
							QBEColumnsStep(previous: self.currentStep, columnNames: namesToSelect, select: remove)
						])
					}
				})
			})
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
				currentRaster?.get({(raster) in
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
					removeSuggestions.extend(keepSuggestions)
					
					QBEAsyncMain {
						self.suggestSteps(removeSuggestions)
					}
				})
			}
		}
	}
	
	@IBAction func selectRows(sender: NSObject) {
		if let selectedRows = dataViewController?.tableView?.selectedRowIndexes {
			if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
				currentRaster?.get({(raster) in
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
				})
			}
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		self.configuratorView?.translatesAutoresizingMaskIntoConstraints = false
	}
	
	func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
		if item.action()==Selector("transposeData:") {
			return currentStep != nil
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
		else if item.action()==Selector("selectColumns:") {
			if let colsToRemove = dataViewController?.tableView?.selectedColumnIndexes {
				return colsToRemove.count > 0 && currentStep != nil
			}
			return false
		}
		else if item.action()==Selector("addColumn:") {
			return currentStep != nil
		}
		else if item.action()==Selector("addEmptyColumn:") {
			return currentStep != nil
		}
		else if item.action()==Selector("importFile:") {
			return true
		}
		else if item.action()==Selector("connectDatabase:") {
			return true
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
		else if item.action()==Selector("paste:") {
			return true
		}
		else {
			return false
		}
	}
	
	@IBAction func removeDuplicateRows(sender: NSObject) {
		pushStep(QBEDistinctStep(previous: self.currentStep))
	}
	
	@IBAction func goBackForward(sender: NSObject) {
		if let segment = sender as? NSSegmentedControl {
			if segment.selectedSegment == 0 {
				self.goBack(sender)
			}
			else if segment.selectedSegment == 1 {
				self.goForward(sender)
			}
			segment.selectedSegment = -1
		}
	}
	
	@IBAction func goBack(sender: NSObject) {
		// Prevent popping the last step (popStep allows it but goBack doesn't)
		if let p = currentStep?.previous {
			currentStep = p
		}
	}
	
	@IBAction func goForward(sender: NSObject) {
		if let n = currentStep?.next {
			currentStep = n
		}
	}
	
	@IBAction func addStep(sender: NSView) {
		NSMenu.popUpContextMenu(self.addStepMenu!, withEvent: NSApplication.sharedApplication().currentEvent!, forView: sender)
	}
	
	@IBAction func connectDatabase(sender: NSObject) {
		self.pushStep(QBEPrestoSourceStep())
	}
	
	@IBAction func importFile(sender: NSObject) {
		let no = NSOpenPanel()
		no.canChooseFiles = true
		no.allowedFileTypes = ["public.comma-separated-values-text", "org.sqlite.v3"]
		
		no.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
			if result==NSFileHandlingPanelOKButton {
				if let url = no.URLs[0] as? NSURL {
					var error: NSError?
					if let type = NSWorkspace.sharedWorkspace().typeOfFile(url.path!, error: &error) {
						QBEAsyncBackground {
							var sourceStep: QBEStep?
							switch type {
								case "public.comma-separated-values-text":
									sourceStep = QBECSVSourceStep(url: url)
								
								case "org.sqlite.v3":
									sourceStep = QBESQLiteSourceStep(url: url)
								
								default:
									sourceStep = nil
							}
							
							QBEAsyncMain {
								if sourceStep != nil {
									// FIXME: in the future, we should propose data set joins here
									//self.currentStep = nil
									//self.document?.head = sourceStep!
									self.pushStep(sourceStep!)
								}
								else {
									let alert = NSAlert()
									alert.messageText = NSLocalizedString("Unknown file format: ", comment: "") + type
									alert.alertStyle = NSAlertStyle.WarningAlertStyle
									alert.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: NSModalResponse) -> Void in
										// Do nothing...
									})
								}
							}
						}
					}
				}
			}
		})
	}
	
	@IBAction func flatten(sender: NSObject) {
		suggestSteps([QBEFlattenStep(previous: currentStep)])
	}
	
	@IBAction func pivot(sender: NSObject) {
		suggestSteps([QBEPivotStep(previous: currentStep)])
	}
	
	@IBAction func exportFile(sender: NSObject) {
		let ns = NSSavePanel()
		ns.allowedFileTypes = ["csv","txt","tab"]
		
		ns.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
			if result == NSFileHandlingPanelOKButton {
				QBEAsyncBackground {
					if let cs = self.currentStep {
						cs.fullData(nil, callback: {(data: QBEData) -> () in
							let wr = QBECSVWriter(data: data, locale: self.locale)
							if let url = ns.URL {
								wr.writeToFile(url, callback: {
									QBEAsyncMain {
										let alert = NSAlert()
										alert.messageText = String(format: NSLocalizedString("The data has been successfully saved to '%@'.", comment: ""), url.absoluteString ?? "")
										alert.beginSheetModalForWindow(self.view.window!, completionHandler: { (response) -> Void in
										})
									}
								})
							}
						})
					}
				}
			}
		})
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		stepsChanged()
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
		if currentStep == nil {
			QBESettings.sharedInstance.once("welcomeTip") {
				if let btn = self.stepsViewController?.addButton {
					self.showTip(NSLocalizedString("Welcome to Warp! Click here to start and load some data.",comment: "Welcome tip"), atView: btn)
				}
			}
		}
	}
	
	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier=="grid" {
			dataViewController = segue.destinationController as? QBEDataViewController
			dataViewController?.delegate = self
			dataViewController?.locale = locale
			calculate()
		}
		else if segue.identifier=="suggestions" {
			let sv = segue.destinationController as? QBESuggestionsViewController
			sv?.delegate = self
			if let alts = currentStep?.alternatives {
				sv?.suggestions = Array(alts)
			}
		}
		else if segue.identifier=="addColumn" {
			let sv = segue.destinationController as? QBEAddColumnViewController
			sv?.delegate = self
		}
		else if segue.identifier=="steps" {
			stepsViewController = segue.destinationController as? QBEStepsViewController
			stepsViewController?.delegate = self
			stepsChanged()
		}
		super.prepareForSegue(segue, sender: sender)
	}
	
	@IBAction func paste(sender: NSObject) {
		var data = NSPasteboard.generalPasteboard().stringForType(NSPasteboardTypeString)
		if data == nil {
			data = NSPasteboard.generalPasteboard().stringForType(NSPasteboardTypeTabularText)
		}
		
		if let tsvString = data {
			var data: [QBERow] = []
			var headerRow: QBERow? = nil
			let rows = tsvString.componentsSeparatedByString("\r")
			for row in rows {
				var rowValues: [QBEValue] = []
				
				let cells = row.componentsSeparatedByString("\t")
				for cell in cells {
					rowValues.append(locale.valueForLocalString(cell))
				}
				
				if headerRow == nil {
					headerRow = rowValues
				}
				else {
					data.append(rowValues)
				}
			}
			
			if headerRow != nil {
				let raster = QBERaster(data: data, columnNames: headerRow!.map({return QBEColumn($0.stringValue!)}), readOnly: false)
				pushStep(QBERasterStep(raster: raster))
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