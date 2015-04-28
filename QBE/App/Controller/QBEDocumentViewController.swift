import Foundation
import Cocoa

private extension NSView {
	func addSubview(view: NSView, animated: Bool) {
		if !animated {
			self.addSubview(view)
			return
		}
		
		let duration = 0.35
		view.wantsLayer = true
		self.addSubview(view)
		
		CATransaction.begin()
		CATransaction.setAnimationDuration(duration)
		let ta = CABasicAnimation(keyPath: "transform")
		
		// Scale, but centered in the middle of the view
		var begin = CATransform3DIdentity
		begin = CATransform3DTranslate(begin, view.bounds.size.width/2, view.bounds.size.height/2, 0.0)
		begin = CATransform3DScale(begin, 0.0, 0.0, 0.0)
		begin = CATransform3DTranslate(begin, -view.bounds.size.width/2, -view.bounds.size.height/2, 0.0)
		
		var end = CATransform3DIdentity
		end = CATransform3DTranslate(end, view.bounds.size.width/2, view.bounds.size.height/2, 0.0)
		end = CATransform3DScale(end, 1.0, 1.0, 0.0)
		end = CATransform3DTranslate(end, -view.bounds.size.width/2, -view.bounds.size.height/2, 0.0)
		
		// Fade in
		ta.fromValue = NSValue(CATransform3D: begin)
		ta.toValue = NSValue(CATransform3D: end)
		ta.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
		view.layer?.addAnimation(ta, forKey: "transformAnimation")
		
		let oa = CABasicAnimation(keyPath: "opacity")
		oa.fromValue = 0.0
		oa.toValue = 1.0
		oa.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
		view.layer?.addAnimation(oa, forKey: "opacityAnimation")
		
		CATransaction.commit()
	}
}

class QBEDocumentViewController: NSViewController, QBEChainViewDelegate {
	var document: QBEDocument?
	private var configurator: QBEConfiguratorViewController? = nil
	@IBOutlet var addTabletMenu: NSMenu!
	@IBOutlet var workspaceView: NSScrollView!
	
	internal var locale: QBELocale { get {
		return QBEAppDelegate.sharedInstance.locale ?? QBELocale()
	} }
	
	func chainView(view: QBEChainViewController, configureStep: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.configurator?.configure(configureStep, delegate: delegate)
	}
	
	func addTablet(tablet: QBETablet) {
		// Check if this tablet is also in the document
		if let d = document where tablet.document != document {
			d.addTablet(tablet)
		}
		
		if let tabletController = self.storyboard?.instantiateControllerWithIdentifier("chain") as? QBEChainViewController {
			tabletController.delegate = self
			
			let vr = self.workspaceView.visibleRect
			let defaultWidth: CGFloat = 640
			let defaultHeight: CGFloat = 640
			
			let resizer = QBEResizableView(frame: CGRectMake((vr.size.width - defaultWidth) / 2, (vr.size.height - defaultHeight) / 2, defaultWidth, defaultHeight))
			resizer.contentView = tabletController.view
			self.addChildViewController(tabletController)
			
			tabletController.chain = tablet.chain
			
			if let dv = self.workspaceView.documentView as? NSView {
				dv.addSubview(resizer, animated: true)
			}
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
	
	@IBAction func addTabletFromFile(sender: NSObject) {
		let no = NSOpenPanel()
		no.canChooseFiles = true
		no.allowedFileTypes = QBEFactory.sharedInstance.fileTypesForReading
		
		no.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
			if result==NSFileHandlingPanelOKButton {
				if let url = no.URLs[0] as? NSURL {
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
		return false
	}
	
	override func viewWillAppear() {
		self.workspaceView.documentView = NSView(frame: CGRectMake(0,0,9999,9999))
		if let d = self.document {
			for tablet in d.tablets {
				self.addTablet(tablet)
			}
		}
	}
}