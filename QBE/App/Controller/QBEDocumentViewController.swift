import Foundation
import Cocoa

private class QBEResizableTabletView: QBEResizableView {
	let tabletController: QBEChainViewController
	
	init(frame: CGRect, controller: QBEChainViewController) {
		tabletController = controller
		super.init(frame: frame)
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}
}

class QBEDocumentViewController: NSViewController, QBEChainViewDelegate, QBEDocumentViewDelegate, QBEResizableDelegate {
	var document: QBEDocument? { didSet {
		self.documentView.subviews.each({($0 as? NSView)?.removeFromSuperview()})
		if let d = document {
			for tablet in d.tablets {
				self.addTablet(tablet)
			}
		}
	} }
	
	private var documentView: QBEDocumentView!
	private var configurator: QBEConfiguratorViewController? = nil
	@IBOutlet var addTabletMenu: NSMenu!
	@IBOutlet var workspaceView: NSScrollView!
	@IBOutlet var formulaField: NSTextField!
	
	private var formulaFieldCallback: ((QBEValue) -> ())?
	
	internal var locale: QBELocale { get {
		return QBEAppDelegate.sharedInstance.locale ?? QBELocale()
	} }
	
	func chainViewDidClose(view: QBEChainViewController) {
		if let t = view.chain?.tablet {
			removeTablet(t)
		}
	}
	
	func chainView(view: QBEChainViewController, configureStep: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.configurator?.configure(configureStep, delegate: delegate)
	}
	
	func chainView(view: QBEChainViewController, editValue: QBEValue, callback: ((QBEValue) -> ())?) {
		formulaField.enabled = callback != nil
		formulaField.stringValue = editValue.stringValue ?? ""
		formulaFieldCallback = callback
	}
	
	func removeTablet(tablet: QBETablet) {
		assert(tablet.document == document, "tablet should belong to our document")
		document?.removeTablet(tablet)
		self.configurator?.configure(nil, delegate: nil)
		
		for subview in documentView.subviews {
			if let rv = subview as? QBEResizableTabletView {
				if let ct = rv.tabletController.chain?.tablet where ct == tablet {
					subview.removeFromSuperview()
				}
			}
		}
	}
	
	func addTablet(tablet: QBETablet) {
		// Check if this tablet is also in the document
		if let d = document where tablet.document != document {
			d.addTablet(tablet)
		}
		
		if tablet.frame == nil {
			let vr = self.workspaceView.documentVisibleRect
			let defaultWidth: CGFloat = vr.size.width * 0.619;
			let defaultHeight: CGFloat = vr.size.height * 0.619;
			tablet.frame = CGRectMake(vr.origin.x + (vr.size.width - defaultWidth) / 2, vr.origin.y + (vr.size.height - defaultHeight) / 2, defaultWidth, defaultHeight)
		}
		
		if let tabletController = self.storyboard?.instantiateControllerWithIdentifier("chain") as? QBEChainViewController {
			tabletController.delegate = self

			self.addChildViewController(tabletController)
			tabletController.chain = tablet.chain
			tabletController.view.frame = tablet.frame!
			
			let resizer = QBEResizableTabletView(frame: tablet.frame!, controller: tabletController)
			resizer.contentView = tabletController.view
			resizer.delegate = self
			
			documentView.addTablet(resizer)
		}
	}
	
	func resizableView(view: QBEResizableView, changedFrameTo frame: CGRect) {
		if let tv = view as? QBEResizableTabletView {
			if let tablet = tv.tabletController.chain?.tablet {
				tablet.frame = frame
			}
		}
	}
	
	@IBAction func updateFromFormulaField(sender: NSObject) {
		if let fc = formulaFieldCallback {
			fc(locale.valueForLocalString(formulaField.stringValue))
		}
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
				let s = QBERasterStep(raster: raster)
				let tablet = QBETablet(chain: QBEChain(head: s))
				addTablet(tablet)
			}
		}
	}
	
	@IBAction func addButtonClicked(sender: NSView) {
		NSMenu.popUpContextMenu(self.addTabletMenu, withEvent: NSApplication.sharedApplication().currentEvent!, forView: self.view)
	}
	
	func documentView(view: QBEDocumentView, didReceiveFiles files: [String]) {
		for file in files {
			if let url = NSURL(fileURLWithPath: file) {
				addTabletFromURL(url)
			}
		}
	}
	
	private func addTabletFromURL(url: NSURL) {
		QBEAsyncBackground {
			let sourceStep = QBEFactory.sharedInstance.stepForReadingFile(url)
			
			QBEAsyncMain {
				if sourceStep != nil {
					// FIXME: in the future, we should propose data set joins here
					//self.currentStep = nil
					//self.document?.head = sourceStep!
					let tablet = QBETablet(chain: QBEChain(head: sourceStep))
					self.addTablet(tablet)
				}
				else {
					let alert = NSAlert()
					alert.messageText = NSLocalizedString("Unknown file format: ", comment: "") + (url.pathExtension ?? "")
					alert.alertStyle = NSAlertStyle.WarningAlertStyle
					alert.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: NSModalResponse) -> Void in
						// Do nothing...
					})
				}
			}
		}
	}
	
	@IBAction func addTabletFromFile(sender: NSObject) {
		let no = NSOpenPanel()
		no.canChooseFiles = true
		no.allowedFileTypes = QBEFactory.sharedInstance.fileTypesForReading
		
		no.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
			if result==NSFileHandlingPanelOKButton {
				if let url = no.URLs[0] as? NSURL {
				self.addTabletFromURL(url)
				}
			}
		})
	}
	
	@IBAction func addTabletFromPresto(sender: NSObject) {
		self.addTablet(QBETablet(chain: QBEChain(head: QBEPrestoSourceStep())))
	}
	
	@IBAction func addTabletFromMySQL(sender: NSObject) {
		let s = QBEMySQLSourceStep(host: "127.0.0.1", port: 3306, user: "root", password: "", database: "test", tableName: "test")
		self.addTablet(QBETablet(chain: QBEChain(head: s)))
	}
	
	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier == "configurator" {
			self.configurator = segue.destinationController as? QBEConfiguratorViewController
		}
	}
	
	func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
		if item.action() == Selector("addButtonClicked:") { return true }
		if item.action() == Selector("addTabletFromFile:") { return true }
		if item.action() == Selector("addTabletFromPresto:") { return true }
		if item.action() == Selector("addTabletFromMySQL:") { return true }
		if item.action() == Selector("paste:") { return true }
		if item.action() == Selector("updateFromFormulaField:") { return true }
		if item.action() == Selector("delete:") { return true }
		return false
	}
	
	override func viewDidLoad() {
		documentView = QBEDocumentView(frame: CGRectMake(0,0,9999,9999))
		documentView.delegate = self
		self.workspaceView.documentView = documentView
	}
}