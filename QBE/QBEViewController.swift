import Cocoa

class QBEViewController: NSViewController, QBESuggestionsViewDelegate, QBEDataViewDelegate {
    var dataViewController: QBEDataViewController?
    @IBOutlet var descriptionField: NSTextField?
    var suggestions: [QBEStep]?

    dynamic var currentStep: QBEStep? {
        didSet {
            self.dataViewController?.data = currentStep?.data
        }
    }
    
    var document: QBEDocument? {
        didSet {
            self.currentStep = document?.head
        }
    }
    
    func dataView(view: QBEDataViewController, didChangeValue: QBEValue, toValue: QBEValue, inRow: Int, column: Int) {
        if let r = currentStep?.data?.raster() {
            suggestSteps([
                    QBEReplaceStep(previous: currentStep, explanation: "Replace all occorrences of '\(didChangeValue)' with '\(toValue)' in column \(r.columnNames[column])", replaceValue: didChangeValue, withValue: toValue, inColumn: r.columnNames[column])
            ])
        }
    }
    
    private func pushStep(step: QBEStep) {
        assert(step.previous==currentStep)
        currentStep?.next = step
        if document?.head == nil || currentStep == document?.head {
            document?.head = step
        }
        
        println("push cs=\(step) prev=\(currentStep)")
        currentStep = step
    }
    
    private func popStep() {
        currentStep = currentStep?.previous
        println("cur=\(currentStep) next=\(currentStep?.next)")
    }
    
    @IBAction func transposeData(sender: NSObject) {
        if let cs = currentStep {
            suggestSteps([QBETransposeStep(previous: cs, explanation: NSLocalizedString("Switch rows/columns", comment: ""))])
        }
    }
    
    func suggestionsView(view: QBESuggestionsViewController, didSelectStep step: QBEStep) {
        pushStep(step)
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
    
    @IBAction func removeColumns(sender: NSObject) {
        // TODO: implement
    }
    
    @IBAction func removeRows(sender: NSObject) {
        var suggestions: [QBEStep] = []
        
        if let rowsToRemove = dataViewController?.tableView?.selectedRowIndexes {
            // Check if the row selection is contiguous from the bottom of the data set; if so, this is a limit operation
            if let data = currentStep?.data? {
                var contiguousLimit = true
                for index in 1...rowsToRemove.count {
                    if !rowsToRemove.containsIndex(data.raster().rowCount-index) {
                        contiguousLimit = false
                        break;
                    }
                }
                
                if contiguousLimit {
                    let rowLimit = data.raster().rowCount - rowsToRemove.count
                    suggestions.append(QBELimitStep(previous: currentStep, explanation: "Limit to \(rowLimit) rows", numberOfRows: rowLimit))
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
    }
    
    func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action()==Selector("transposeData:") {
            return currentStep != nil
        }
        else if item.action()==Selector("removeRows:") {
            if let rowsToRemove = dataViewController?.tableView?.selectedRowIndexes {
                return rowsToRemove.count > 0
            }
            return false
        }
        else if item.action()==Selector("importFile:") {
            return true
        }
        else if item.action()==Selector("goBack:") {
            return currentStep?.previous != nil
        }
        else if item.action()==Selector("goForward:") {
            return currentStep?.next != nil
        }
        else {
            return false
        }
    }
    
    @IBAction func goBack(sender: NSObject) {
        popStep()
    }
    
    @IBAction func goForward(sender: NSObject) {
        if currentStep?.next != nil {
            pushStep(currentStep!.next!)
        }
    }
    
    @IBAction func importFile(sender: NSObject) {
        let no = NSOpenPanel()
        no.canChooseFiles = true
        
        no.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
            if(result==NSFileHandlingPanelOKButton) {
                if let url = no.URLs[0] as? NSURL {
                    self.currentStep = nil
                    let gq = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
                    dispatch_async(gq) {
                        let inStream = NSInputStream(URL: url)
                        let parser = CHCSVParser(contentsOfCSVURL: url)
                        let reader = QBERasterCSVReader()
                        parser.delegate = reader
                        parser.parse()
                        
                        dispatch_async(dispatch_get_main_queue()) {
                            self.pushStep(QBERasterStep(raster: reader.raster, explanation: "Import \(url)"))
                            self.dataViewController?.data = self.currentStep!.data
                        }
                    }
                }
            }
        })
    }
    
    override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
        if(segue.identifier=="grid") {
            dataViewController = segue.destinationController as? QBEDataViewController
            dataViewController?.data = currentStep?.data
            dataViewController?.delegate = self
        }
        else if segue.identifier=="suggestions" {
            let sv = segue.destinationController as? QBESuggestionsViewController
            sv?.delegate = self
            sv?.suggestions = self.suggestions
            self.suggestions = nil
        }
        super.prepareForSegue(segue, sender: sender)
    }
}

