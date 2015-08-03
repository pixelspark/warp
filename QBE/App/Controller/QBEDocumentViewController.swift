import Foundation
import Cocoa

@objc class QBEDocumentViewController: NSViewController, QBEChainViewDelegate, QBEDocumentViewDelegate, QBEWorkspaceViewDelegate {
	private var documentView: QBEDocumentView!
	private var sentenceEditor: QBESentenceViewController? = nil
	@IBOutlet var addTabletMenu: NSMenu!
	@IBOutlet var workspaceView: QBEWorkspaceView!
	@IBOutlet var formulaField: NSTextField!
	@IBOutlet var welcomeLabel: NSTextField!
	@IBOutlet var documentAreaView: NSView!
	private var formulaFieldCallback: ((QBEValue) -> ())?
	
	private var zoomedView: (NSView, CGRect)? = nil
	
	var document: QBEDocument? { didSet {
		self.documentView.removeAllTablets()
		if let d = document {
			for tablet in d.tablets {
				self.addTablet(tablet, undo: false)
			}
			self.zoomToAll()
		}
	} }
	
	internal var locale: QBELocale { get {
		return QBEAppDelegate.sharedInstance.locale ?? QBELocale()
	} }
	
	func chainViewDidClose(view: QBEChainViewController) {
		if let t = view.chain?.tablet {
			removeTablet(t, undo: true)
		}
	}
	
	func chainViewDidChangeChain(view: QBEChainViewController) {
		if workspaceView.magnifiedView == nil {
			documentView.resizeDocument()
		}
		documentView.reloadData()
	}
	
	func chainView(view: QBEChainViewController, configureStep: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		if let ch = view.chain {
			if let tablet = ch.tablet {
				for cvc in self.childViewControllers {
					if let child = cvc as? QBEChainViewController {
						if child.chain?.tablet == tablet {
							documentView.selectTablet(tablet, notifyDelegate: false)
							child.view.superview?.orderFront()
						}
					}
				}
			}
		}
		self.sentenceEditor?.configure(configureStep, delegate: delegate)
	}
	
	func chainView(view: QBEChainViewController, editValue: QBEValue, callback: ((QBEValue) -> ())?) {
		setFormula(editValue, callback: callback)
	}
	
	private func setFormula(value: QBEValue, callback: ((QBEValue) -> ())?) {
		formulaField.enabled = callback != nil
		formulaField.stringValue = value.stringValue ?? ""
		formulaFieldCallback = callback
	}
	
	@objc func removeTablet(tablet: QBETablet) {
		removeTablet(tablet, undo: false)
	}
	
	func removeTablet(tablet: QBETablet, undo: Bool) {
		assert(tablet.document == document, "tablet should belong to our document")

		document?.removeTablet(tablet)
		self.sentenceEditor?.configure(nil, delegate: nil)
		documentView.removeTablet(tablet)
		workspaceView.magnifyView(nil)
		
		for cvc in self.childViewControllers {
			if let child = cvc as? QBEChainViewController {
				if child.chain?.tablet == tablet {
					child.removeFromParentViewController()
				}
			}
		}
		
		self.view.window?.makeFirstResponder(self.documentView)
		updateView()
		
		// Register undo operation. Do not retain the QBETablet but instead serialize, so all caches are properly destroyed.
		if undo {
			let data = NSKeyedArchiver.archivedDataWithRootObject(tablet)
			
			if let um = undoManager {
				um.registerUndoWithTarget(self, selector: Selector("addTabletFromArchivedData:"), object: data)
				um.setActionName(NSLocalizedString("Remove tablet", comment: ""))
			}
		}
	}
	
	private var defaultTabletFrame: CGRect { get {
		let vr = self.workspaceView.documentVisibleRect
		let defaultWidth: CGFloat = vr.size.width * 0.8 * self.workspaceView.magnification
		let defaultHeight: CGFloat = vr.size.height * 0.8 * self.workspaceView.magnification
		
		// If this is not the first view, place it to the right of all other views
		if let ab = documentView.boundsOfAllTablets {
			return CGRectMake(ab.origin.x + ab.size.width + 10, ab.origin.y + ((ab.size.height - defaultHeight) / 2), defaultWidth, defaultHeight)
		}
		else {
			// If this is the first view, just center it in the visible rect
			return CGRectMake(vr.origin.x + (vr.size.width - defaultWidth) / 2, vr.origin.y + (vr.size.height - defaultHeight) / 2, defaultWidth, defaultHeight)
		}
	} }
	
	func addTablet(tablet: QBETablet, atLocation location: CGPoint?, undo: Bool) {
		// By default, tablets get a size that (when at 100% zoom) fills about 61% horizontally/vertically
		if tablet.frame == nil {
			tablet.frame = defaultTabletFrame
		}
		
		if let l = location {
			tablet.frame = tablet.frame!.centeredAt(l)
		}
		
		self.addTablet(tablet, undo: undo)
	}
	
	@objc func addTabletFromArchivedData(data: NSData) {
		if let t = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? QBETablet {
			self.addTablet(t, undo: false)
		}
	}
	
	@objc func addTablet(tablet: QBETablet, undo: Bool) {
		self.workspaceView.magnifyView(nil) {
			// Check if this tablet is also in the document
			if let d = self.document where tablet.document != self.document {
				d.addTablet(tablet)
			}
			
			if tablet.frame == nil {
				tablet.frame = self.defaultTabletFrame
			}

			if let tabletController = self.storyboard?.instantiateControllerWithIdentifier("chain") as? QBEChainViewController {
				tabletController.delegate = self

				self.addChildViewController(tabletController)
				tabletController.chain = tablet.chain
				tabletController.view.frame = tablet.frame!
				
				self.documentView.addTablet(tabletController) {
					self.documentView.selectTablet(tablet)
				}
			}
			self.updateView()
		}
	}
	
	private func updateView () {
		self.workspaceView.hasHorizontalScroller = (self.document?.tablets.count ?? 0) > 0
		self.workspaceView.hasVerticalScroller = (self.document?.tablets.count ?? 0) > 0
		self.welcomeLabel.hidden = (self.document?.tablets.count ?? 0) != 0
	}
	
	private func zoomToAll() {
		if let ab = documentView.boundsOfAllTablets {
			if self.workspaceView.magnifiedView != nil {
				self.workspaceView.magnifyView(nil) {
					self.documentView.resizeDocument()
				}
			}
			else {
				NSAnimationContext.runAnimationGroup({ (ac) -> Void in
					ac.duration = 0.3
					self.workspaceView.animator().magnifyToFitRect(ab)
				}, completionHandler: nil)
			}
		}
	}

	@IBAction func zoomToAll(sender: NSObject) {
		zoomToAll()
	}
	
	func documentView(view: QBEDocumentView, wantsZoomToView: NSView) {
		workspaceView.zoomView(wantsZoomToView)
		documentView.reloadData()
	}
	
	@IBAction func zoomSelection(sender: NSObject) {
		if let selectedView = documentView.selectedTabletController?.view.superview {
			workspaceView.zoomView(selectedView)
			documentView.reloadData()
		}
	}
	
	@IBAction func updateFromFormulaField(sender: NSObject) {
		if let fc = formulaFieldCallback {
			fc(locale.valueForLocalString(formulaField.stringValue))
			formulaFieldCallback = nil
		}
	}
	
	@IBAction func paste(sender: NSObject) {
		// Pasting a step?
		let pboard = NSPasteboard.generalPasteboard()
		if let data = pboard.dataForType(QBEStep.dragType) {
			if let step = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? QBEStep {
				self.addTablet(QBETablet(chain: QBEChain(head: step)), undo: true)
			}
		}
		else {
			// No? Maybe we're pasting TSV/CSV data...
			var data = pboard.stringForType(NSPasteboardTypeString)
			if data == nil {
				data = pboard.stringForType(NSPasteboardTypeTabularText)
			}
			
			if let tsvString = data {
				var data: [QBETuple] = []
				var headerRow: QBETuple? = nil
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
					let raster = QBERaster(data: data, columnNames: headerRow!.map({return QBEColumn($0.stringValue ?? "")}), readOnly: false)
					let s = QBERasterStep(raster: raster)
					let tablet = QBETablet(chain: QBEChain(head: s))
					addTablet(tablet, undo: true)
				}
			}
		}
	}
	
	@IBAction func addButtonClicked(sender: NSView) {
		NSMenu.popUpContextMenu(self.addTabletMenu, withEvent: NSApplication.sharedApplication().currentEvent!, forView: self.view)
	}
	
	func workspaceView(view: QBEWorkspaceView, didReceiveChain chain: QBEChain, atLocation: CGPoint) {
		QBEAssertMainThread()
		
		let tablet = QBETablet(chain: QBEChain(head: QBECloneStep(chain: chain)))
		self.addTablet(tablet, atLocation: atLocation, undo: true)
	}
	
	func workspaceView(view: QBEWorkspaceView, didReceiveFiles files: [String], atLocation: CGPoint) {
		// Gather file paths
		var tabletsAdded: [QBETablet] = []
		
		for file in files {
			var isDirectory: ObjCBool = false
			NSFileManager.defaultManager().fileExistsAtPath(file, isDirectory: &isDirectory)
			if isDirectory {
				// Find the contents of the directory, and add.
				if let enumerator = NSFileManager.defaultManager().enumeratorAtPath(file) {
					for child in enumerator {
						if let childName = child as? String {
							// Skip UNIX hidden files (e.g. .DS_Store).
							// TODO: check Finder 'hidden' bit here like so: http://stackoverflow.com/questions/1140235/is-the-file-hidden
							if !childName.lastPathComponent.hasPrefix(".") {
								let childPath = file.stringByAppendingPathComponent(childName)
								
								// Is  the enumerated item a directory? Then ignore it, the enumerator already recurses
								var isChildDirectory: ObjCBool = false
								NSFileManager.defaultManager().fileExistsAtPath(childPath, isDirectory: &isChildDirectory)
								if !isChildDirectory {
									if let t = addTabletFromURL(NSURL(fileURLWithPath: childPath)) {
										tabletsAdded.append(t)
									}
								}
							}
						}
					}
				}
			}
			else {
				if let t = addTabletFromURL(NSURL(fileURLWithPath: file)) {
					tabletsAdded.append(t)
				}
			}
		}
		
		// Zoom to all newly added tablets
		var allRect = CGRectZero
		for tablet in tabletsAdded {
			if let f = tablet.frame {
				allRect = CGRectUnion(allRect, f)
			}
		}
		self.workspaceView.magnifyToFitRect(allRect)
	}
	
	func documentView(view: QBEDocumentView, didSelectArrow arrow: QBEArrow?) {
		if let ta = arrow as? QBETabletArrow {
			if let fromStep = ta.fromStep, let fromTablet = ta.from {
				findAndSelectStep(fromStep, inChain: fromTablet.chain)
			}
		}
	}
	
	func findAndSelectStep(step: QBEStep, inChain chain: QBEChain) {
		if let tablet = chain.tablet {
			for cvc in self.childViewControllers {
				if let child = cvc as? QBEChainViewController {
					if child.chain?.tablet == tablet {
						documentView.selectTablet(tablet)
						child.view.superview?.orderFront()
						didSelectTablet(child)
						child.currentStep = step
					}
				}
			}
		}
	}
	
	private func didSelectTablet(tabletViewController: QBEChainViewController?) {
		if let tv = tabletViewController {
			self.setFormula(QBEValue.InvalidValue, callback: nil)
			tv.tabletWasSelected()
		}
		else {
			self.setFormula(QBEValue.InvalidValue, callback: nil)
			self.sentenceEditor?.configure(nil, delegate: nil)
		}
		self.view.window?.update()
	}
	
	func documentView(view: QBEDocumentView, didSelectTablet tablet: QBEChainViewController?) {
		didSelectTablet(tablet)
	}
	
	private func addTabletFromURL(url: NSURL, atLocation: CGPoint? = nil) -> QBETablet? {
		QBEAssertMainThread()
		let sourceStep = QBEFactory.sharedInstance.stepForReadingFile(url)
		
		if sourceStep != nil {
			let tablet = QBETablet(chain: QBEChain(head: sourceStep))
			self.addTablet(tablet, atLocation: atLocation, undo: true)
			return tablet
		}
		else {
			let alert = NSAlert()
			alert.messageText = String(format: NSLocalizedString("Unknown file type '%@'.'", comment: ""), (url.pathExtension ?? ""))
			alert.alertStyle = NSAlertStyle.WarningAlertStyle
			alert.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: NSModalResponse) -> Void in
				// Do nothing...
			})
			return nil
		}
	}
	
	@IBAction func addSequencerTablet(sender: NSObject) {
		let chain = QBEChain(head: QBESequencerStep(pattern: "[A-Z]{4}", column: QBEColumn(NSLocalizedString("Value", comment: ""))))
		let tablet = QBETablet(chain: chain)
		self.addTablet(tablet, undo: true)
	}
	
	@IBAction func addTabletFromFile(sender: NSObject) {
		let no = NSOpenPanel()
		no.canChooseFiles = true
		no.allowsMultipleSelection = true
		no.allowedFileTypes?.append("public.text")
		//	= NSArray(arrayLiteral: "public.text") // QBEFactory.sharedInstance.fileTypesForReading
		
		no.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
			if result==NSFileHandlingPanelOKButton {
				for url in no.URLs {
					self.addTabletFromURL(url)
				}
			}
		})
	}
	
	@IBAction func addTabletFromPresto(sender: NSObject) {
		self.addTablet(QBETablet(chain: QBEChain(head: QBEPrestoSourceStep())), undo: true)
	}
	
	@IBAction func addTabletFromMySQL(sender: NSObject) {
		let s = QBEMySQLSourceStep(host: "127.0.0.1", port: 3306, user: "root", password: "", database: "test", tableName: "test")
		self.addTablet(QBETablet(chain: QBEChain(head: s)), undo: true)
	}
	
	@IBAction func addTabletFromPostgres(sender: NSObject) {
		let s = QBEPostgresSourceStep(host: "127.0.0.1", port: 5432, user: "postgres", password: "", database: "postgres", schemaName: "public", tableName: "")
		self.addTablet(QBETablet(chain: QBEChain(head: s)), undo: true)
	}
	
	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier == "sentence" {
			self.sentenceEditor = segue.destinationController as? QBESentenceViewController
		}
	}
	
	@IBAction func setFullWorkingSet(sender: NSObject) {
		if let t = documentView.selectedTabletController {
			t.setFullWorkingSet(sender)
		}
	}
	
	@IBAction func cancelCalculation(sender: NSObject) {
		if let t = documentView.selectedTabletController {
			t.cancelCalculation(sender)
		}
	}
	
	@IBAction func showSuggestions(sender: NSObject) {
		if let t = documentView.selectedTabletController {
			t.showSuggestions(sender)
		}
	}
	
	@IBAction func exportFile(sender: NSObject) {
		if let t = documentView.selectedTabletController {
			t.exportFile(sender)
		}
	}
	
	func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
		if item.action() == Selector("addButtonClicked:") { return true }
		if item.action() == Selector("addSequencerTablet:") { return true }
		if item.action() == Selector("addTabletFromFile:") { return true }
		if item.action() == Selector("addTabletFromPresto:") { return true }
		if item.action() == Selector("addTabletFromMySQL:") { return true }
		if item.action() == Selector("addTabletFromPostgres:") { return true }
		if item.action() == Selector("updateFromFormulaField:") { return true }
		if item.action() == Selector("setFullWorkingSet:") { return documentView.selectedTabletController?.validateUserInterfaceItem(item) ?? false }
		if item.action() == Selector("cancelCalculation:") { return documentView.selectedTabletController?.validateUserInterfaceItem(item) ?? false }
		if item.action() == Selector("showSuggestions:") { return documentView.selectedTabletController?.validateUserInterfaceItem(item) ?? false }
		if item.action() == Selector("exportFile:") { return documentView.selectedTabletController?.validateUserInterfaceItem(item) ?? false }
		if item.action() == Selector("zoomToAll:") { return documentView.boundsOfAllTablets != nil }
		if item.action() == Selector("zoomSelection:") { return documentView.selectedTablet != nil }
		if item.action() == Selector("delete:") { return true }
		if item.action() == Selector("paste:") {
			let pboard = NSPasteboard.generalPasteboard()
			if pboard.dataForType(QBEStep.dragType) != nil || pboard.dataForType(NSPasteboardTypeString) != nil || pboard.dataForType(NSPasteboardTypeTabularText) != nil {
				return true
			}
		}
		return false
	}
	
	override func viewDidLoad() {
		let initialDocumentSize = self.workspaceView.bounds
		
		documentView = QBEDocumentView(frame: initialDocumentSize)
		documentView.delegate = self
		self.workspaceView.delegate = self
		self.workspaceView.documentView = documentView
		documentView.resizeDocument()
	}
}