import Cocoa

protocol QBESuggestionsViewDelegate: NSObjectProtocol {
	func suggestionsView(view: NSViewController, didSelectStep: QBEStep)
	func suggestionsView(view: NSViewController, previewStep: QBEStep?)
	func suggestionsViewDidCancel(view: NSViewController)
	var currentStep: QBEStep? { get }
	var locale: QBELocale { get }
}

class QBEViewController: NSViewController, QBESuggestionsViewDelegate, QBEDataViewDelegate {
	let locale: QBELocale = QBEDefaultLocale()
	var dataViewController: QBEDataViewController?
	var suggestions: [QBEStep]?
	weak var windowController: QBEWindowController?
	@IBOutlet var descriptionField: NSTextField?
	@IBOutlet var configuratorView: NSView?
	@IBOutlet var titleLabel: NSTextField?
	
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
				let configurator = QBEConfigurators[className]?(step: s, delegate: self)
				self.configuratorViewController = configurator
				self.titleLabel?.attributedStringValue = NSAttributedString(string: s.explain(locale))
				
				s.exampleData({ (data: QBEData?) -> () in
					QBEAsyncMain {
						self.presentData(data)
					}
				})
			}
			else {
				self.configuratorViewController = nil
				self.titleLabel?.attributedStringValue = NSAttributedString(string: "")
				self.presentData(nil)
			}
			self.view.window?.update()
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
				dataView.calculating = true
				
				QBEAsyncBackground {
					d.raster({ (raster) -> () in
						QBEAsyncMain {
							dataView.raster = raster
						}
					})
				}
			}
		}
		else {
			self.dataViewController?.raster = nil
		}
	}
	
	var previewStep: QBEStep? {
		didSet {
			if previewStep == nil {
				currentStep?.exampleData({ (d) -> () in
					self.presentData(d)
				})
			}
			else {
				previewStep?.exampleData({ (d) -> () in
					self.presentData(d)
				})
			}
		}
	}
	
	var document: QBEDocument? {
		didSet {
			self.currentStep = document?.head
		}
	}

	func dataView(view: QBEDataViewController, didChangeValue: QBEValue, toValue: QBEValue, inRow: Int, column: Int) -> Bool {
		self.currentStep?.exampleData({ (data: QBEData?) -> () in
			if data != nil {
				data!.raster({ (r: QBERaster) -> () in
					QBEAsyncBackground {
						let expressions = QBECalculateStep.suggest(change: didChangeValue, toValue: toValue, inRaster: r, row: inRow, column: column, locale: self.locale)
						let steps = expressions.map({QBECalculateStep(previous: self.currentStep, targetColumn: r.columnNames[column], function: $0)})
						
						QBEAsyncMain {
							self.suggestSteps(steps)
						}
					}
				})
			}
		})
		return false
	}
	
	private func pushStep(step: QBEStep) {
		assert(step.previous==currentStep)
		currentStep?.next = step
		if document?.head == nil || currentStep == document?.head {
			document?.head = step
		}
		currentStep = step
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
	}
	
	func suggestionsView(view: NSViewController, previewStep step: QBEStep?) {
		previewStep = step
	}
	
	func suggestionsViewDidCancel(view: NSViewController) {
		previewStep = nil
		
		// Close any configuration sheets that may be open
		if let s = self.view.window?.attachedSheet {
			self.view.window?.endSheet(s, returnCode: NSModalResponseOK)
		}
	}
	
	private func suggestSteps(steps: [QBEStep]) {
		if steps.count == 0 {
			// Alert
			let alert = NSAlert()
			alert.messageText = "I have no idea what you did."
			alert.beginSheetModalForWindow(self.view.window!, completionHandler: { (a: NSModalResponse) -> Void in
			})
		}
		else if steps.count == 1 {
			pushStep(steps.first!)
		}
		else {
			suggestions = steps
			self.performSegueWithIdentifier("suggestions", sender: self)
		}
	}
	
	@IBAction func addColumn(sender: NSObject) {
		self.performSegueWithIdentifier("addColumn", sender: sender)
	}
	
	@IBAction func addEmptyColumn(sender: NSObject) {
		currentStep?.exampleData({ (data: QBEData?) -> () in
			if let d = data {
				d.columnNames({(cols) in
					let step = QBECalculateStep(previous: self.currentStep, targetColumn: QBEColumn.defaultColumnForIndex(cols.count), function: QBELiteralExpression(QBEValue.EmptyValue))
					self.pushStep(step)
				})
			}
		})
	}
	
	@IBAction func removeStep(sender: NSObject) {
		popStep()
		currentStep?.next = nil
	}
	
	@IBAction func removeColumns(sender: NSObject) {
		if let colsToRemove = dataViewController?.tableView?.selectedColumnIndexes {
			// Get the names of the columns to remove
			currentStep?.exampleData({ (data: QBEData?) -> () in
				var namesToRemove: [QBEColumn] = []
				var namesToSelect: [QBEColumn] = []
				
				data?.columnNames({ (columnNames) -> () in
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
							QBEColumnsStep(previous: self.currentStep, columnNames: namesToRemove, select: false),
							QBEColumnsStep(previous: self.currentStep, columnNames: namesToSelect, select: true)
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
				currentStep?.exampleData({ (data: QBEData?) -> () in
					if data != nil {
						data!.raster({ (raster: QBERaster) -> () in
							// Invert the selection
							let selected = NSMutableIndexSet()
							for index in 0..<raster.rowCount {
								if !rowsToRemove.containsIndex(index) {
									selected.addIndex(index)
								}
							}
							
							var relevantColumns = Set<QBEColumn>()
							for columnIndex in 0..<raster.columnCount {
								if selectedColumns.containsIndex(columnIndex) {
									relevantColumns.add(raster.columnNames[columnIndex])
								}
							}

							let suggestions = QBERowsStep.suggest(selected, columns: relevantColumns, inRaster: raster, fromStep: self.currentStep)
							
							QBEAsyncMain {
								self.suggestSteps(suggestions)
							}
						})
					}
				})
			}
		}
	}
	
	@IBAction func selectRows(sender: NSObject) {
		if let selectedRows = dataViewController?.tableView?.selectedRowIndexes {
			if  let selectedColumns = self.dataViewController?.tableView?.selectedColumnIndexes {
				currentStep?.exampleData({ (data: QBEData?) -> () in
					if data != nil {
						data!.raster({ (raster: QBERaster) -> () in
							var relevantColumns = Set<QBEColumn>()
							for columnIndex in 0..<raster.columnCount {
								if selectedColumns.containsIndex(columnIndex) {
									relevantColumns.add(raster.columnNames[columnIndex])
								}
							}
							
							let suggestions = QBERowsStep.suggest(selectedRows, columns: relevantColumns, inRaster: raster, fromStep: self.currentStep)
							
							QBEAsyncMain {
								self.suggestSteps(suggestions)
							}
						})
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
		else if item.action()==Selector("addColumn:") {
			return currentStep != nil
		}
		else if item.action()==Selector("addEmptyColumn:") {
			return currentStep != nil
		}
		else if item.action()==Selector("importFile:") {
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
		else if item.action()==Selector("removeStep:") {
			return currentStep != nil
		}
		else if item.action()==Selector("removeDuplicateRows:") {
			return currentStep != nil
		}
		else if item.action()==Selector("selectRows:") {
			return currentStep != nil
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
		if currentStep?.previous != nil {
			popStep()
		}
	}
	
	@IBAction func goForward(sender: NSObject) {
		if currentStep?.next != nil {
			pushStep(currentStep!.next!)
		}
	}
	
	@IBAction func importFile(sender: NSObject) {
		let no = NSOpenPanel()
		no.canChooseFiles = true
		no.allowedFileTypes = ["public.comma-separated-values-text", "org.sqlite.v3"]
		
		no.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
			if result==NSFileHandlingPanelOKButton {
				if let url = no.URLs[0] as? NSURL {
					QBEAsyncBackground {
						var error: NSError?
						if let type = NSWorkspace.sharedWorkspace().typeOfFile(url.path!, error: &error) {
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
									self.currentStep = nil
									self.pushStep(sourceStep!)
									//self.dataViewController?.data = self.currentStep!.exampleData
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
	
	@IBAction func pivot(sender: NSObject) {
		suggestSteps([QBEPivotStep(previous: currentStep)])
	}
	
	@IBAction func calculate(sender: NSObject) {
		if let step = currentStep {
			// Create a result view
			let resultView = self.storyboard?.instantiateControllerWithIdentifier("resultViewController") as? QBEResultViewController;
			resultView?.locale = self.locale
			if let rv = resultView {
				self.presentViewControllerAsSheet(rv)
			}
			
			let startTime = CFAbsoluteTimeGetCurrent()
			windowController?.startTask(NSLocalizedString("Calculate full result", comment: ""))
			
			QBEAsyncBackground {
				step.fullData({ (data: QBEData?) -> () in
					println("Got data: \(data)")
					
					if data != nil {
						data!.raster({ (raster) -> () in
							// End
							let endTime = CFAbsoluteTimeGetCurrent()
							let duration = (endTime - startTime)
							let speed =  Double(raster.rowCount) / duration
							self.windowController?.stopTask()
							println("Calculation took \(duration)s, \(raster.rowCount) rows, \(speed) rows/s")
							
							QBEAsyncMain({
								resultView?.raster = raster; return;
							})
						})
					}
				})
			}
		}
	}
	
	@IBAction func exportFile(sender: NSObject) {
		let ns = NSSavePanel()
		
		ns.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
			if result == NSFileHandlingPanelOKButton {
				QBEAsyncBackground {
					if let cs = self.currentStep {
						cs.fullData({(data: QBEData?) -> () in
							if data != nil {
								let wr = QBECSVWriter(data: data!, locale: self.locale)
								if let url = ns.URL {
									wr.writeToFile(url)
								}
							}
						})
					}
				}
			}
		})
	}
	
	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier=="grid" {
			dataViewController = segue.destinationController as? QBEDataViewController
			dataViewController?.delegate = self
			dataViewController?.locale = locale
			
			currentStep?.exampleData({ (data: QBEData?) -> () in
				QBEAsyncMain {
					if data != nil {
						data!.raster({(r: QBERaster) -> () in
							self.dataViewController!.raster = r
						})
					}
				}
			})
		}
		else if segue.identifier=="suggestions" {
			let sv = segue.destinationController as? QBESuggestionsViewController
			sv?.delegate = self
			sv?.suggestions = self.suggestions
			self.suggestions = nil
		}
		else if segue.identifier=="addColumn" {
			let sv = segue.destinationController as? QBEAddColumnViewController
			sv?.delegate = self
		}
		super.prepareForSegue(segue, sender: sender)
	}
}

