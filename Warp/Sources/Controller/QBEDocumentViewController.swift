import Foundation
import Cocoa
import WarpCore

@objc class QBEDocumentViewController: NSViewController, QBETabletViewDelegate, QBEDocumentViewDelegate, QBEWorkspaceViewDelegate, QBEExportViewDelegate, QBEAlterTableViewDelegate {
	private var documentView: QBEDocumentView!
	private var sentenceEditor: QBESentenceViewController? = nil
	@IBOutlet var addTabletMenu: NSMenu!
	@IBOutlet var readdMenuItem: NSMenuItem!
	@IBOutlet var readdTabletMenu: NSMenu!
	@IBOutlet var workspaceView: QBEWorkspaceView!
	@IBOutlet var welcomeLabel: NSTextField!
	@IBOutlet var documentAreaView: NSView!
	private var zoomedView: (NSView, CGRect)? = nil
	
	var document: QBEDocument? { didSet {
		self.documentView?.removeAllTablets()
		if let d = document {
			for tablet in d.tablets {
				self.addTablet(tablet, undo: false, animated: false)
			}
			self.zoomToAll()
		}
	} }
	
	internal var locale: Locale { get {
		return QBEAppDelegate.sharedInstance.locale ?? Locale()
	} }
	
	func tabletViewDidClose(view: QBETabletViewController) -> Bool {
		if let t = view.tablet {
			let force = self.view.window?.currentEvent?.modifierFlags.contains(.AlternateKeyMask) ?? false
			return removeTablet(t, undo: true, force: force)
		}
		return false
	}

	func tabletView(view: QBETabletViewController, exportObject: NSObject) {
		if let chain = exportObject as? QBEChain {
			if let pointInWindow = self.view.window?.currentEvent?.locationInWindow {
				let pointInView = self.view.convertPoint(pointInWindow, fromView: nil)
				self.receiveChain(chain, atLocation: nil, isDestination: false)
			}
		}
	}

	func tabletViewDidChangeContents(view: QBETabletViewController) {
		if workspaceView.magnifiedView == nil {
			documentView.resizeDocument()
		}
		documentView.reloadData()
	}
	
	func tabletView(view: QBETabletViewController, didSelectConfigurable configurable: QBEConfigurable?, configureNow: Bool, delegate: QBESentenceViewDelegate) {
		documentView.selectTablet(view.tablet, notifyDelegate: false)
		view.view.superview?.orderFront()

		// Only show this tablet in the sentence editor if it really has become the selected tablet
		if self.documentView.selectedTablet == view.tablet {
			self.sentenceEditor?.startConfiguring(configurable, variant: .Read, delegate: delegate)
		}

		if configureNow {
			self.sentenceEditor?.configure(self)
		}

		// When editing the sentence, all other commands should still go to the original tablet
		self.sentenceEditor?.nextResponder = self.view.window!.firstResponder
	}
	
	@objc func removeTablet(tablet: QBETablet) {
		removeTablet(tablet, undo: false, force: false)
	}
	
	func removeTablet(tablet: QBETablet, undo: Bool, force: Bool = false) -> Bool {
		assert(tablet.document == document, "tablet should belong to our document")

		// Who was dependent on this tablet?
		if let d = document {
			for otherTablet in d.tablets {
				if otherTablet == tablet {
					continue
				}

				for dep in otherTablet.arrows {
					if dep.from == tablet {
						if force {
							if let to = dep.to {
								// Recursively remove the dependent tablets first
								self.removeTablet(to, undo: undo, force: true)
							}
						}
						else {
							// TODO: automatically remove this dependency. For now just bail out
							NSAlert.showSimpleAlert("This item cannot be removed, because other items are still linked to it.".localized, infoText: "To remove the item, first remove any links to this item, then try to remove the table itself. Alternatively, if you hold the option key while removing the item, the linked items will be removed as well.".localized, style: .WarningAlertStyle, window: self.view.window)
							return false
						}
					}
				}
			}
		}

		document?.removeTablet(tablet)
		self.sentenceEditor?.startConfiguring(nil, variant: .Read, delegate: nil)
		documentView.removeTablet(tablet) {
			assertMainThread()
			self.workspaceView.magnifyView(nil)
		
			for cvc in self.childViewControllers {
				if let child = cvc as? QBEChainViewController {
					if child.chain?.tablet == tablet {
						child.removeFromParentViewController()
					}
				}
			}
		
			self.view.window?.makeFirstResponder(self.documentView)
			self.updateView()
			
			// Register undo operation. Do not retain the QBETablet but instead serialize, so all caches are properly destroyed.
			if undo {
				let data = NSKeyedArchiver.archivedDataWithRootObject(tablet)
				
				if let um = self.undoManager {
					um.registerUndoWithTarget(self, selector: #selector(QBEDocumentViewController.addTabletFromArchivedData(_:)), object: data)
					um.setActionName(NSLocalizedString("Remove tablet", comment: ""))
				}
			}
		}
		return true
	}
	
	private var defaultTabletFrame: CGRect { get {
		let vr = self.workspaceView.documentVisibleRect
		let defaultWidth: CGFloat = max(350, min(800, vr.size.width * 0.382 * self.workspaceView.magnification))
		let defaultHeight: CGFloat = max(300, min(600, vr.size.height * 0.382 * self.workspaceView.magnification))
		
		// If this is not the first view, place it to the right of all other views
		if let ab = documentView.boundsOfAllTablets {
			return CGRectMake(ab.origin.x + ab.size.width + 25, ab.origin.y + ((ab.size.height - defaultHeight) / 2), defaultWidth, defaultHeight)
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
		
		self.addTablet(tablet, undo: undo, animated: true)
	}
	
	@objc func addTabletFromArchivedData(data: NSData) {
		if let t = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? QBETablet {
			self.addTablet(t, undo: false, animated: true)
		}
	}
	
	@objc func addTablet(tablet: QBETablet, undo: Bool, animated: Bool, callback: ((QBETabletViewController) -> ())? = nil) {
		self.workspaceView.magnifyView(nil) {
			// Check if this tablet is also in the document
			if let d = self.document where tablet.document != self.document {
				d.addTablet(tablet)
			}
			
			if tablet.frame == nil {
				tablet.frame = self.defaultTabletFrame
			}

			let vc = self.viewControllerForTablet(tablet)
			self.addChildViewController(vc)
				
			self.documentView.addTablet(vc, animated: animated) {
				self.documentView.selectTablet(tablet)
				callback?(vc)
			}
			self.updateView()
		}
	}

	private func viewControllerForTablet(tablet: QBETablet) -> QBETabletViewController {
		let tabletController = QBEFactory.sharedInstance.viewControllerForTablet(tablet, storyboard: self.storyboard!)
		tabletController.delegate = self
		return tabletController
	}
	
	private func updateView() {
		self.workspaceView.hasHorizontalScroller = (self.document?.tablets.count ?? 0) > 0
		self.workspaceView.hasVerticalScroller = (self.document?.tablets.count ?? 0) > 0
		self.welcomeLabel.hidden = (self.document?.tablets.count ?? 0) != 0

		// Apparently, starting in El Capitan, the label does not repaint itself automatically and stays in view after setting hidden=true
		self.welcomeLabel.setNeedsDisplay()
		self.view.setNeedsDisplayInRect(self.view.bounds)
	}
	
	private func zoomToAll(animated: Bool = true) {
		if let ab = documentView.boundsOfAllTablets {
			if self.workspaceView.magnifiedView != nil {
				self.workspaceView.magnifyView(nil) {
					self.documentView.resizeDocument()
				}
			}
			else {
				if animated {
					NSAnimationContext.runAnimationGroup({ (ac) -> Void in
						ac.duration = 0.3
						self.workspaceView.animator().magnifyToFitRect(ab)
					}, completionHandler: nil)
				}
				else {
					self.workspaceView.magnifyToFitRect(ab)
				}
			}
		}
	}

	@IBAction func selectPreviousTablet(sender: NSObject) {
		cycleTablets(-1)
	}

	@IBAction func selectNextTablet(sender: NSObject) {
		cycleTablets(1)
	}

	private func cycleTablets(offset: Int) {
		if let d = self.document where d.tablets.count > 0 {
			let currentTablet = documentView.selectedTablet ?? d.tablets[0]
			if let index = d.tablets.indexOf(currentTablet) {
				let nextIndex = (index+offset) % d.tablets.count
				let nextTablet = d.tablets[nextIndex]
				self.documentView.selectTablet(nextTablet)
				if let selectedView = documentView.selectedTabletController?.view.superview {
					if self.workspaceView.magnification != 1.0 {
						self.workspaceView.zoomView(selectedView)
					}
					else {
						self.workspaceView.animator().magnifyToFitRect(selectedView.frame)
						//selectedView.scrollRectToVisible(selectedView.bounds)
					}
				}
			}
		}
	}

	@objc func exportView(view: QBEExportViewController, finishedExportingTo: NSURL) {
		if let ext = finishedExportingTo.pathExtension {
			if QBEFactory.sharedInstance.fileTypesForReading.contains(ext) {
				self.addTabletFromURL(finishedExportingTo)
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

	@IBAction func pasteAsPlainText(sender: AnyObject) {
		let pboard = NSPasteboard.generalPasteboard()

		if let data = pboard.stringForType(NSPasteboardTypeString) {
			let note = QBENoteTablet()
			note.note.text = NSAttributedString(string: data)
			self.addTablet(note, undo: true, animated: true)
		}
	}

	@IBAction func paste(sender: NSObject) {
		// Pasting a step?
		let pboard = NSPasteboard.generalPasteboard()
		if let data = pboard.dataForType(QBEStep.dragType) {
			if let step = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? QBEStep {
				self.addTablet(QBEChainTablet(chain: QBEChain(head: step)), undo: true, animated: true)
			}
		}
		else {
			// No? Maybe we're pasting TSV/CSV data...
			var data = pboard.stringForType(NSPasteboardTypeString)
			if data == nil {
				data = pboard.stringForType(NSPasteboardTypeTabularText)
			}
			
			if let tsvString = data {
				var data: [Tuple] = []
				var headerRow: Tuple? = nil
				let rows = tsvString.componentsSeparatedByString("\r")
				for row in rows {
					var rowValues: [Value] = []
					
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
					let raster = Raster(data: data, columns: headerRow!.map({return Column($0.stringValue ?? "")}), readOnly: false)
					let s = QBERasterStep(raster: raster)
					let tablet = QBEChainTablet(chain: QBEChain(head: s))
					addTablet(tablet, undo: true, animated: true)
				}
			}
		}
	}
	
	@IBAction func addButtonClicked(sender: NSView) {
		// Populate the 'copy of source step' sub menu
		class QBETemplateAdder: NSObject {
			var templateSteps: [QBEStep] = []
			var documentView: QBEDocumentViewController

			init(documentView: QBEDocumentViewController) {
				self.documentView = documentView
			}

			@objc func readdStep(sender: NSMenuItem) {
				if sender.tag >= 0 && sender.tag < templateSteps.count {
					let templateStep = templateSteps[sender.tag]
					let templateData = NSKeyedArchiver.archivedDataWithRootObject(templateStep)
					let newStep = NSKeyedUnarchiver.unarchiveObjectWithData(templateData) as? QBEStep
					let tablet = QBEChainTablet(chain: QBEChain(head: newStep))
					self.documentView.addTablet(tablet, undo: true, animated: true) { _ in
						self.documentView.sentenceEditor?.configure(self.documentView)
					}
				}
			}
		}

		let adder = QBETemplateAdder(documentView: self)
		readdTabletMenu.removeAllItems()
		if let d = self.document {
			// Loop over all chain tablets and add menu items to re-add the starting step from each chain
			for tablet in d.tablets {
				if let chainTablet = tablet as? QBEChainTablet {
					for step in chainTablet.chain.steps {
						if step.previous == nil {
							// This is a source step
							let item = NSMenuItem(title: step.sentence(self.locale, variant: .Read).stringValue, action: #selector(QBETemplateAdder.readdStep(_:)), keyEquivalent: "")
							item.enabled = true
							item.tag = adder.templateSteps.count
							item.target = adder
							adder.templateSteps.append(step)
							readdTabletMenu.addItem(item)
						}
					}
				}
			}
		}

		// The re-add menu item is hidden when the menu is opened from the context menu
		readdMenuItem.hidden = false
		readdMenuItem.enabled = !adder.templateSteps.isEmpty
		NSMenu.popUpContextMenu(self.addTabletMenu, withEvent: NSApplication.sharedApplication().currentEvent!, forView: self.view)
		readdMenuItem.enabled = false
		readdMenuItem.hidden = true
	}

	func workspaceView(view: QBEWorkspaceView, didReceiveStep step: QBEStep, atLocation location: CGPoint) {
		assertMainThread()

		let chain = QBEChain(head: step)
		let tablet = QBEChainTablet(chain: chain)
		self.addTablet(tablet, atLocation: location, undo: true)
	}

	func receiveChain(chain: QBEChain, atLocation: CGPoint?, isDestination: Bool) {
		assertMainThread()

		if chain.head != nil {
			let ac = QBEDropChainAction(chain: chain, documentView: self, location: atLocation)
			ac.present(isDestination)
		}
	}

	/** Called when an outlet is dropped onto the workspace itself (e.g. an empty spot). */
	func workspaceView(view: QBEWorkspaceView, didReceiveChain chain: QBEChain, atLocation: CGPoint) {
		receiveChain(chain, atLocation: atLocation, isDestination: true)
	}

	/** Called when a set of columns was dropped onto the document. */
	func workspaceView(view: QBEWorkspaceView, didReceiveColumnSet colset: [Column], fromDataViewController dc: QBEDataViewController) {
		let action = QBEDropColumnsAction(columns: colset, dataViewController: dc, documentViewController: self)
		action.present()
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
						if let cn = child as? String {
							let childName = NSString(string: cn)
							// Skip UNIX hidden files (e.g. .DS_Store).
							// TODO: check Finder 'hidden' bit here like so: http://stackoverflow.com/questions/1140235/is-the-file-hidden
							if !childName.lastPathComponent.hasPrefix(".") {
								let childPath = NSString(string: file).stringByAppendingPathComponent(childName as String)
								
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
	
	func documentView(view: QBEDocumentView, didSelectArrow arrow: QBETabletArrow?) {
		if let a = arrow, fromTablet = a.to {
			findAndSelectArrow(a, inTablet: fromTablet)
		}
	}

	func tabletViewControllerForTablet(tablet: QBETablet) -> QBETabletViewController? {
		for cvc in self.childViewControllers {
			if let child = cvc as? QBETabletViewController {
				if child.tablet == tablet {
					return child
				}
			}
		}
		return nil
	}
	
	func findAndSelectArrow(arrow: QBETabletArrow, inTablet tablet: QBETablet) {
		if let child = self.tabletViewControllerForTablet(tablet) {
			documentView.selectTablet(tablet)
			child.view.superview?.orderFront()
			didSelectTablet(child.tablet)
			child.selectArrow(arrow)
		}
	}
	
	private func didSelectTablet(tablet: QBETablet?) {
		self.sentenceEditor?.startConfiguring(nil, variant: .Neutral, delegate: nil)

		for childController in self.childViewControllers {
			if let cvc = childController as? QBETabletViewController {
				if cvc.tablet != tablet {
					cvc.tabletWasDeselected()
				}
				else {
					cvc.tabletWasSelected()
					cvc.view.orderFront()
				}
			}
		}

		self.view.window?.update()
		self.view.window?.toolbar?.validateVisibleItems()
	}
	
	func documentView(view: QBEDocumentView, didSelectTablet tablet: QBETablet?) {
		didSelectTablet(tablet)
	}
	
	private func addTabletFromURL(url: NSURL, atLocation: CGPoint? = nil) -> QBETablet? {
		assertMainThread()

		if let sourceStep = QBEFactory.sharedInstance.stepForReadingFile(url) {
			let tablet = QBEChainTablet(chain: QBEChain(head: sourceStep))
			self.addTablet(tablet, atLocation: atLocation, undo: true)
			return tablet
		}
		else {
			// This may be a warp document - open separately
			if let p = url.path {
				NSWorkspace.sharedWorkspace().openFile(p)
			}
		}

		return nil
	}

	func alterTableView(view: QBEAlterTableViewController, didAlterTable mutableData: MutableData?) {
		let job = Job(.UserInitiated)
		mutableData?.data(job) {result in
			switch result {
			case .Success(let data):
				data.raster(job) { result in
					switch result {
					case .Success(let raster):
						asyncMain {
							let tablet = QBEChainTablet(chain: QBEChain(head: QBERasterStep(raster: raster)))
							self.addTablet(tablet, atLocation: nil, undo: true)
						}

					case .Failure(let e):
						asyncMain {
							NSAlert.showSimpleAlert(NSLocalizedString("Could not add table", comment: ""), infoText: e, style: .CriticalAlertStyle, window: self.view.window)
						}
					}
				}

			case .Failure(let e):
				asyncMain {
					NSAlert.showSimpleAlert(NSLocalizedString("Could not add table", comment: ""), infoText: e, style: .CriticalAlertStyle, window: self.view.window)
				}
			}
		}
	}

	@IBAction func addNoteTablet(sender: NSObject) {
		let tablet = QBENoteTablet()
		self.addTablet(tablet, undo: true, animated: true)
	}

	@IBAction func addRasterTablet(sender: NSObject) {
		let raster = Raster(data: [], columns: [Column.defaultNameForNewColumn([])], readOnly: false)
		let chain = QBEChain(head: QBERasterStep(raster: raster))
		let tablet = QBEChainTablet(chain: chain)
		self.addTablet(tablet, undo: true, animated: true) { tabletViewController in
			tabletViewController.startEditing()
		}
	}

	@IBAction func addSequencerTablet(sender: NSObject) {
		let chain = QBEChain(head: QBESequencerStep())
		let tablet = QBEChainTablet(chain: chain)
		self.addTablet(tablet, undo: true, animated: true)
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
		self.addTablet(QBEChainTablet(chain: QBEChain(head: QBEPrestoSourceStep())), undo: true, animated: true) { _ in
			self.sentenceEditor?.configure(self)
		}
	}
	
	@IBAction func addTabletFromMySQL(sender: NSObject) {
		let s = QBEMySQLSourceStep(host: "127.0.0.1", port: 3306, user: "root", database: nil, tableName: nil)
		self.addTablet(QBEChainTablet(chain: QBEChain(head: s)), undo: true, animated: true) { _ in
			self.sentenceEditor?.configure(self)
		}
	}

	@IBAction func addTabletFromRethinkDB(sender: NSObject) {
		let s = QBERethinkSourceStep(previous: nil)
		self.addTablet(QBEChainTablet(chain: QBEChain(head: s)), undo: true, animated: true) { _ in
			self.sentenceEditor?.configure(self)
		}
	}
	
	@IBAction func addTabletFromPostgres(sender: NSObject) {
		let s = QBEPostgresSourceStep(host: "127.0.0.1", port: 5432, user: "postgres", database: "postgres", schemaName: "public", tableName: "")
		self.addTablet(QBEChainTablet(chain: QBEChain(head: s)), undo: true, animated: true) { _ in
			self.sentenceEditor?.configure(self)
		}
	}
	
	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier == "sentence" {
			self.sentenceEditor = segue.destinationController as? QBESentenceViewController
			self.sentenceEditor?.view.translatesAutoresizingMaskIntoConstraints = false
		}
	}

	func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
			return validateSelector(item.action())
	}

	override func validateToolbarItem(theItem: NSToolbarItem) -> Bool {
		return validateSelector(theItem.action)
	}

	@IBAction func zoomSegment(sender: NSSegmentedControl) {
		if sender.selectedSegment == 0 {
			self.zoomToAll(sender)
		}
		else if sender.selectedSegment == 1 {
			self.zoomSelection(sender)
		}
	}

	private func validateSelector(selector: Selector) -> Bool {
		if selector == #selector(QBEDocumentViewController.selectNextTablet(_:)) { return (self.document?.tablets.count > 0) ?? false }
		if selector == #selector(QBEDocumentViewController.selectPreviousTablet(_:)) { return (self.document?.tablets.count > 0) ?? false }
		if selector == #selector(QBEDocumentViewController.addButtonClicked(_:)) { return true }
		if selector == #selector(QBEDocumentViewController.addSequencerTablet(_:)) { return true }
		if selector == #selector(QBEDocumentViewController.addRasterTablet(_:)) { return true }
		if selector == #selector(QBEDocumentViewController.addNoteTablet(_:)) { return true }
		if selector == #selector(QBEDocumentViewController.addTabletFromFile(_:)) { return true }
		if selector == #selector(QBEDocumentViewController.addTabletFromPresto(_:)) { return true }
		if selector == #selector(QBEDocumentViewController.addTabletFromMySQL(_:)) { return true }
		if selector == #selector(QBEDocumentViewController.addTabletFromRethinkDB(_:)) { return true }
		if selector == #selector(QBEDocumentViewController.addTabletFromPostgres(_:)) { return true }
		if selector == #selector(QBEDocumentViewController.zoomSegment(_:)) { return documentView.boundsOfAllTablets != nil }
		if selector == #selector(QBEDocumentViewController.zoomToAll(_:) as (QBEDocumentViewController) -> (NSObject) -> ()) { return documentView.boundsOfAllTablets != nil }
		if selector == #selector(QBEDocumentViewController.zoomSelection(_:)) { return documentView.selectedTablet != nil }
		if selector == #selector(NSText.delete(_:)) { return true }
		if selector == #selector(QBEDocumentViewController.paste(_:)) {
			let pboard = NSPasteboard.generalPasteboard()
			if pboard.dataForType(QBEStep.dragType) != nil || pboard.dataForType(NSPasteboardTypeString) != nil || pboard.dataForType(NSPasteboardTypeTabularText) != nil {
				return true
			}
		}
		if selector == #selector(QBEDocumentViewController.pasteAsPlainText(_:)) {
			let pboard = NSPasteboard.generalPasteboard()
			return pboard.dataForType(NSPasteboardTypeString) != nil
		}
		return false
	}

	override func viewWillAppear() {
		super.viewWillAppear()
		self.zoomToAll(false)
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

private class QBEDropChainAction: NSObject {
	private var chain: QBEChain
	private var documentView: QBEDocumentViewController
	private var location: CGPoint?

	init(chain: QBEChain, documentView: QBEDocumentViewController, location: CGPoint?) {
		self.chain = chain
		self.documentView = documentView
		self.location = location
	}

	@objc func addClone(sender: NSObject) {
		let tablet = QBEChainTablet(chain: QBEChain(head: QBECloneStep(chain: chain)))
		self.documentView.addTablet(tablet, atLocation: location, undo: true)
	}

	@objc func addChart(sender: NSObject) {
		if let sourceTablet = chain.tablet as? QBEChainTablet {
			let job = Job(.UserInitiated)
			let jobProgressView = QBEJobViewController(job: job, description: "Analyzing data...".localized)!
			self.documentView.presentViewControllerAsSheet(jobProgressView)

			sourceTablet.chain.head?.exampleData(job, maxInputRows: 1000, maxOutputRows: 1, callback: { (result) -> () in
				switch result {
				case .Success(let data):
					data.columns(job) { result in
						switch result {
						case .Success(let columns):
							asyncMain {
								jobProgressView.dismissController(sender)
								if let first = columns.first, let last = columns.last where columns.count > 1 {
									let tablet = QBEChartTablet(source: sourceTablet, type: .Bar, xExpression: Sibling(first), yExpression: Sibling(last))
									self.documentView.addTablet(tablet, atLocation: self.location, undo: true)
								}
								else {
									asyncMain {
										NSAlert.showSimpleAlert("Could not create a chart of this data".localized, infoText: "In order to be able to create a chart, the data set must contain at least two columns.".localized, style: .CriticalAlertStyle, window: self.documentView.view.window)
									}
								}
							}

						case .Failure(let e):
							asyncMain {
								NSAlert.showSimpleAlert("Could not create a chart of this data".localized, infoText: e, style: .CriticalAlertStyle, window: self.documentView.view.window)
							}
						}
					}

				case .Failure(let e):
					asyncMain {
						NSAlert.showSimpleAlert("Could not create a chart of this data".localized, infoText: e, style: .CriticalAlertStyle, window: self.documentView.view.window)
					}
				}
			})
		}
	}

	@objc func addMap(sender: NSObject) {
		if let sourceTablet = chain.tablet as? QBEChainTablet {
			let job = Job(.UserInitiated)
			let jobProgressView = QBEJobViewController(job: job, description: "Analyzing data...".localized)!
			self.documentView.presentViewControllerAsSheet(jobProgressView)

			sourceTablet.chain.head?.exampleData(job, maxInputRows: 1000, maxOutputRows: 1, callback: { (result) -> () in
				switch result {
				case .Success(let data):
					data.columns(job) { result in
						switch result {
						case .Success(let columns):
							asyncMain {
								jobProgressView.dismissController(sender)
								let tablet = QBEMapTablet(source: sourceTablet,columns: columns)
								self.documentView.addTablet(tablet, atLocation: self.location, undo: true)
							}

						case .Failure(let e):
							asyncMain {
								NSAlert.showSimpleAlert("Could not create a map of this data".localized, infoText: e, style: .CriticalAlertStyle, window: self.documentView.view.window)
							}
						}
					}

				case .Failure(let e):
					asyncMain {
						NSAlert.showSimpleAlert("Could not create a map of this data".localized, infoText: e, style: .CriticalAlertStyle, window: self.documentView.view.window)
					}
				}
			})
		}
	}


	@objc func addCopy(sender: NSObject) {
		let job = Job(.UserInitiated)
		QBEAppDelegate.sharedInstance.jobsManager.addJob(job, description: NSLocalizedString("Create copy of data here", comment: ""))
		chain.head?.fullData(job) { result in
			switch result {
			case .Success(let fd):
				fd.raster(job) { result in
					switch result {
					case .Success(let raster):
						asyncMain {
							let tablet = QBEChainTablet(chain: QBEChain(head: QBERasterStep(raster: raster)))
							self.documentView.addTablet(tablet, atLocation: self.location, undo: true)
						}
					case .Failure(let e):
						asyncMain {
							NSAlert.showSimpleAlert(NSLocalizedString("Could not copy the data",comment: ""), infoText: e, style: .CriticalAlertStyle, window: self.documentView.view.window)
						}
					}
				}
			case .Failure(let e):
				asyncMain {
					NSAlert.showSimpleAlert(NSLocalizedString("Could not copy the data",comment: ""), infoText: e, style: .CriticalAlertStyle, window: self.documentView.view.window)
				}
			}
		}
	}

	@objc func exportFile(sender: NSObject) {
		var exts: [String: String] = [:]
		for ext in QBEFactory.sharedInstance.fileExtensionsForWriting {
			let writer = QBEFactory.sharedInstance.fileWriterForType(ext)!
			exts[ext] = writer.explain(ext, locale: self.documentView.locale)
		}

		let ns = QBEFilePanel(allowedFileTypes: exts)
		ns.askForSaveFile(self.documentView.view.window!) { (urlFallible) -> () in
			urlFallible.maybe { (url) in
				self.exportToFile(url)
			}
		}
	}

	private func exportToFile(url: NSURL) {
		let writerType: QBEFileWriter.Type
		if let ext = url.pathExtension {
			writerType = QBEFactory.sharedInstance.fileWriterForType(ext) ?? QBECSVWriter.self
		}
		else {
			writerType = QBECSVWriter.self
		}

		let title = chain.tablet?.displayName ?? NSLocalizedString("Warp data", comment: "")
		let s = QBEExportStep(previous: chain.head!, writer: writerType.init(locale: self.documentView.locale, title: title), file: QBEFileReference.URL(url))

		if let editorController = self.documentView.storyboard?.instantiateControllerWithIdentifier("exportEditor") as? QBEExportViewController {
			editorController.step = s
			editorController.delegate = self.documentView
			editorController.locale = self.documentView.locale
			self.documentView.presentViewControllerAsSheet(editorController)
		}
	}

	@objc func saveToWarehouse(sender: NSObject) {
		let stepTypes = QBEFactory.sharedInstance.dataWarehouseSteps
		if let s = sender as? NSMenuItem where s.tag >= 0 && s.tag <= stepTypes.count {
			let stepType = stepTypes[s.tag]

			let uploadView = self.documentView.storyboard?.instantiateControllerWithIdentifier("uploadData") as! QBEUploadViewController
			let targetStep = stepType.init()
			uploadView.targetStep = targetStep
			uploadView.sourceStep = chain.head
			uploadView.afterSuccessfulUpload = {
				// Add the written data as tablet to the document view
				asyncMain {
					let tablet = QBEChainTablet(chain: QBEChain(head: targetStep))
					self.documentView.addTablet(tablet, atLocation: self.location, undo: true)
				}
			}
			self.documentView.presentViewControllerAsSheet(uploadView)
		}
	}

	/** Present the menu with actions to perform with the chain. When `atDestination` is true, the menu uses wording that
	is appropriate when the menu is shown at the location of the drop. When it is false, wording is used that fits when
	the menu is presented at the source. */
	func present(atDestination: Bool) {
		let menu = NSMenu()
		menu.autoenablesItems = false

		let cloneItem = NSMenuItem(title: (atDestination ? "Create linked clone of data here" : "Create a linked clone of data").localized, action: #selector(QBEDropChainAction.addClone(_:)), keyEquivalent: "")
		cloneItem.target = self
		menu.addItem(cloneItem)

		if self.chain.tablet is QBEChainTablet {
			let chartItem = NSMenuItem(title: (atDestination ? "Create chart of data here" : "Create a chart from the data").localized, action: #selector(QBEDropChainAction.addChart(_:)), keyEquivalent: "")
			chartItem.target = self
			menu.addItem(chartItem)

			let mapItem = NSMenuItem(title: (atDestination ? "Create map of data here" : "Create a map from the data").localized, action: #selector(QBEDropChainAction.addMap(_:)), keyEquivalent: "")
			mapItem.target = self
			menu.addItem(mapItem)
		}

		let copyItem = NSMenuItem(title: (atDestination ? "Create copy of data here" : "Create a copy of the data").localized, action: #selector(QBEDropChainAction.addCopy(_:)), keyEquivalent: "")
		copyItem.target = self
		menu.addItem(copyItem)

		menu.addItem(NSMenuItem.separatorItem())

		let stepTypes = QBEFactory.sharedInstance.dataWarehouseSteps

		for i in 0..<stepTypes.count {
			let stepType = stepTypes[i]
			if let name = QBEFactory.sharedInstance.dataWarehouseStepNames[stepType.className()] {
				let saveItem = NSMenuItem(title: String(format: "Upload data to %@...".localized, name), action: #selector(QBEDropChainAction.saveToWarehouse(_:)), keyEquivalent: "")
				saveItem.target = self
				saveItem.tag = i
				menu.addItem(saveItem)
			}
		}

		menu.addItem(NSMenuItem.separatorItem())
		let exportFileItem = NSMenuItem(title: "Export data to file...".localized, action: #selector(QBEDropChainAction.exportFile(_:)), keyEquivalent: "")
		exportFileItem.target = self
		menu.addItem(exportFileItem)

		NSMenu.popUpContextMenu(menu, withEvent: NSApplication.sharedApplication().currentEvent!, forView: self.documentView.view)
	}
}

/** Action that handles dropping a set of columns on the document. Usually the columns come from another data view / chain
controller. */
private class QBEDropColumnsAction: NSObject {
	let columns: [Column]
	let documentViewController: QBEDocumentViewController
	let dataViewController: QBEDataViewController

	init(columns: [Column], dataViewController: QBEDataViewController, documentViewController: QBEDocumentViewController) {
		self.columns = columns
		self.dataViewController = dataViewController
		self.documentViewController = documentViewController
	}

	/** Add a tablet to the document containing a chain that calculates the histogram of this column (unique values and
	their occurrence count). */
	@objc private func addHistogram(sender: NSObject) {
		if columns.count == 1 {
			if let sourceChainController = dataViewController.parentViewController as? QBEChainViewController, let sourceChain = sourceChainController.chain {
				let countColumn = Column("Count".localized)
				let cloneStep = QBECloneStep(chain: sourceChain)
				let histogramStep = QBEPivotStep()
				histogramStep.previous = cloneStep
				histogramStep.rows = columns
				histogramStep.aggregates = [Aggregation(map: Sibling(columns.first!), reduce: .CountAll, targetColumn: countColumn)]
				let sortStep = QBESortStep(previous: histogramStep, orders: [Order(expression: Sibling(countColumn), ascending: false, numeric: true)])

				let histogramChain = QBEChain(head: sortStep)
				let histogramTablet = QBEChainTablet(chain: histogramChain)

				self.documentViewController.addTablet(histogramTablet, atLocation: nil, undo: true)
			}
		}
	}

	/** Add a tablet to the document containing a raster table containing all unique values in the original column. This
	tablet is then joined to the original table. */
	@objc private func addLookupTable(sender: NSObject) {
		if columns.count == 1 {
			if let sourceChainController = dataViewController.parentViewController as? QBEChainViewController, let step = sourceChainController.chain?.head {
				let job = Job(.UserInitiated)
				let jobProgressView = QBEJobViewController(job: job, description: String(format: NSLocalizedString("Analyzing %d column(s)...", comment: ""), columns.count))!
				self.documentViewController.presentViewControllerAsSheet(jobProgressView)

				step.fullData(job) { result in
					switch result {
					case .Success(let data):
						data.unique(Sibling(self.columns.first!), job: job) { result in
							switch result {
							case .Success(let uniqueValues):
								let rows = uniqueValues.map({ item in return [item] })
								let raster = Raster(data: rows, columns: [self.columns.first!], readOnly: false)
								let chain = QBEChain(head: QBERasterStep(raster: raster))
								let tablet = QBEChainTablet(chain: chain)
								asyncMain {
									jobProgressView.dismissController(nil)
									self.documentViewController.addTablet(tablet, atLocation: nil, undo: true)

									let joinStep = QBEJoinStep(previous: nil)
									joinStep.joinType = JoinType.LeftJoin
									joinStep.condition = Comparison(first: Sibling(self.columns.first!), second: Foreign(self.columns.first!), type: .Equal)
									joinStep.right = chain
									sourceChainController.chain?.insertStep(joinStep, afterStep: sourceChainController.chain?.head)
									sourceChainController.currentStep = joinStep
								}

							case .Failure(_):
								break
							}

						}

					case .Failure(_):
						break
					}
				}
			}
		}
	}

	func present() {
		let menu = NSMenu()
		menu.autoenablesItems = false

		if columns.count == 1 {
			if let sourceChainController = dataViewController.parentViewController as? QBEChainViewController where sourceChainController.chain?.head != nil {
				let item = NSMenuItem(title: "Create a look-up table for this column".localized, action: #selector(QBEDropColumnsAction.addLookupTable(_:)), keyEquivalent: "")
				item.target = self
				menu.addItem(item)

				let histogramItem = NSMenuItem(title: "Add a histogram of this column".localized, action: #selector(QBEDropColumnsAction.addHistogram(_:)), keyEquivalent: "")
				histogramItem.target = self
				menu.addItem(histogramItem)
			}
		}
		else {
			// Do something with more than one column (multijoin)
		}

		NSMenu.popUpContextMenu(menu, withEvent: NSApplication.sharedApplication().currentEvent!, forView: self.documentViewController.view)
	}
}