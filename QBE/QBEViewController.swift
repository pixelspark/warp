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
	@IBOutlet var descriptionField: NSTextField?
	@IBOutlet var configuratorView: NSView?
	
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
				let className = s.className
				let configurator = QBEConfigurators[className]?(step: s, delegate: self)
				self.configuratorViewController = configurator
			}
			
			presentData(self.currentStep?.exampleData)
		}
	}
	
	private func presentData(data: QBEData?) {
		let gq = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
		if let d = data {
			if let dataView = self.dataViewController {
				dispatch_async(gq) {
					d.raster()
					
					dispatch_async(dispatch_get_main_queue()) {
						dataView.data = d
					}
				}
			}
		}
		else {
			self.dataViewController?.data = nil
		}
	}
	
	var previewStep: QBEStep? {
		didSet {
			if previewStep == nil {
				presentData(currentStep?.exampleData)
			}
			else {
				presentData(previewStep?.exampleData)
			}
		}
	}
	
	var document: QBEDocument? {
		didSet {
			self.currentStep = document?.head
		}
	}

	func dataView(view: QBEDataViewController, didChangeValue: QBEValue, toValue: QBEValue, inRow: Int, column: Int) -> Bool {
		if let r = currentStep?.exampleData?.raster() {
			var suggestions: [QBEStep] = [];
			
			if didChangeValue != toValue {
				let targetColumn = r.columnNames[column]
				
				// Was a formula typed in?
				if let f = QBEFormula(formula: toValue.stringValue ?? "", locale: locale) {
					suggestions.append(QBECalculateStep(previous: self.currentStep, targetColumn: targetColumn, function: f.root))
					suggestSteps(suggestions)
				}
				else {
					// Suggest a text replace
					suggestions.append(QBEReplaceStep(previous: currentStep, replaceValue: didChangeValue, withValue: toValue, inColumn: r.columnNames[column]))
					
					// Try to find a formula
					let qs = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
					
					dispatch_async(qs) {
						var suggestedFormulas: [QBEExpression] = []
						QBEInferer.inferFunctions(nil, toValue: toValue, suggestions: &suggestedFormulas, level: 4, raster: r, row: inRow, column: column)
						for suggestedFormula in suggestedFormulas {
							let cs = QBECalculateStep(previous: self.currentStep, targetColumn: targetColumn, function: suggestedFormula)
							suggestions.append(cs)
						}
						
						dispatch_async(dispatch_get_main_queue()) {
							self.suggestSteps(suggestions)
						}
					}
				}
			}
		}
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
		if let data = currentStep?.exampleData {
			let step = QBECalculateStep(previous: currentStep, targetColumn: QBEColumn("\(data.columnNames.count)"), function: QBELiteralExpression(QBEValue.EmptyValue))
			pushStep(step)
		}
	}
	
	@IBAction func removeColumns(sender: NSObject) {
		if let colsToRemove = dataViewController?.tableView?.selectedColumnIndexes {
			// Get the names of the columns to remove
			
			if let data = currentStep?.exampleData? {
				var namesToRemove: [QBEColumn] = []
				var namesToSelect: [QBEColumn] = []
				
				for i in 0..<data.columnNames.count {
					if colsToRemove.containsIndex(i) {
						namesToRemove.append(data.columnNames[i])
					}
					else {
						namesToSelect.append(data.columnNames[i])
					}
				}
				
				suggestSteps([
					QBEColumnsStep(previous: self.currentStep, columnNames: namesToRemove, select: false),
					QBEColumnsStep(previous: self.currentStep, columnNames: namesToSelect, select: true)
				])
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
		var suggestions: [QBEStep] = []
		
		if let rowsToRemove = dataViewController?.tableView?.selectedRowIndexes {
			// Check if the row selection is contiguous from the bottom of the data set; if so, this is a limit operation
			if let data = currentStep?.exampleData? {
				var contiguousLimit = true
				for index in 1...rowsToRemove.count {
					if !rowsToRemove.containsIndex(data.raster().rowCount-index) {
						contiguousLimit = false
						break;
					}
				}
				
				let rowLimit = data.raster().rowCount - rowsToRemove.count
				if contiguousLimit {
					suggestions.append(QBELimitStep(previous: currentStep, numberOfRows: rowLimit))
				}
				else {
					suggestions.append(QBERandomStep(previous: currentStep, numberOfRows: rowLimit))
				}
			}
		}
		
		suggestSteps(suggestions)
	}
	
	@IBAction func selectRows(sender: NSObject) {
		// TODO: implement
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
		else {
			return false
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
					let gq = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
					dispatch_async(gq) {
					
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
							
							dispatch_async(dispatch_get_main_queue()) {
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
	
	@IBAction func calculate(sender: NSObject) {
		let gq = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
		if let step = currentStep {
			dispatch_async(gq) {
				if let fr = step.fullData?.raster() {
					println("All good: \(fr.columnCount)x\(fr.rowCount)")
					println("\(fr.description())")
				}
				else {
					println("No full result... this is bad")
				}
			}
		}
	}
	
	@IBAction func exportFile(sender: NSObject) {
		let ns = NSSavePanel()
		
		ns.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
			if result == NSFileHandlingPanelOKButton {
				let gq = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
				
				dispatch_async(gq) {
					if let fr = self.currentStep?.fullData {
						let wr = QBECSVWriter(data: fr, locale: self.locale)
						if let url = ns.URL {
							wr.writeToFile(url)
						}
					}
				}
			}
		})
	}
	
	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier=="grid" {
			dataViewController = segue.destinationController as? QBEDataViewController
			dataViewController?.data = currentStep?.exampleData
			dataViewController?.delegate = self
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

