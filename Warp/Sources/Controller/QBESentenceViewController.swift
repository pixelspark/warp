import Cocoa
import WarpCore

protocol QBESentenceViewDelegate: NSObjectProtocol {
	func sentenceView(view: QBESentenceViewController, didChangeStep: QBEStep)
	var locale: Locale { get }
}

class QBESentenceViewController: NSViewController, NSTokenFieldDelegate, NSTextFieldDelegate, QBEFormulaEditorViewDelegate, QBEStepViewDelegate {
	@IBOutlet var tokenField: NSTokenField!
	@IBOutlet var configureButton: NSButton!

	var variant: QBESentenceVariant = .Neutral
	private var editingToken: QBEEditingToken? = nil
	private var editingStep: QBEStep? = nil
	private weak var delegate: QBESentenceViewDelegate? = nil

	var enabled: Bool {
		get {
			return tokenField.enabled
		}
		set {
			assertMainThread()
			tokenField.enabled = enabled
		}
	}

	private struct QBEEditingToken {
		let token: QBESentenceToken
		var options: [String]? = nil

		init(_ token: QBESentenceToken) {
			self.token = token
		}
	}

	private struct QBEEditingFormula {
		let value: Value
		var callback: ((Value) -> ())?
	}

	override func viewDidLoad() {
		super.viewDidLoad()
	}

	func tokenField(tokenField: NSTokenField, styleForRepresentedObject representedObject: AnyObject) -> NSTokenStyle {
		if let r = representedObject as? QBESentenceToken {
			return r.isToken ? NSTokenStyle.Default : NSTokenStyle.None
		}
		return NSTokenStyle.None
	}

	func tokenField(tokenField: NSTokenField, displayStringForRepresentedObject representedObject: AnyObject) -> String? {
		if let x = representedObject as? QBESentenceToken {
			return x.label
		}
		return nil
	}

	func tokenField(tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: AnyObject) -> Bool {
		return true
	}

	func control(control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
		var text = control.stringValue
		if let inputToken = editingToken?.token as? QBESentenceTextInput, let s = editingStep {
			// Was a formula typed in?
			if text.hasPrefix("=") {
				if let formula = Formula(formula: text, locale: self.locale) where formula.root.isConstant {
					text = locale.localStringFor(formula.root.apply(Row(), foreign: nil, inputValue: nil))
				}
			}

			if inputToken.change(text) {
				self.delegate?.sentenceView(self, didChangeStep: s)
				updateView()
				return true
			}
			return false
		}
		else if let inputToken = editingToken?.token as? QBESentenceFormula, let s = editingStep, let locale = self.delegate?.locale {
			if let formula = Formula(formula: text, locale: locale) {
				inputToken.change(formula.root)
				self.delegate?.sentenceView(self, didChangeStep: s)
				updateView()
				return true
			}
			return false
		}

		return true
	}

	func tokenField(tokenField: NSTokenField, menuForRepresentedObject representedObject: AnyObject) -> NSMenu? {
		editingToken = nil

		if let options = representedObject as? QBESentenceOptions {
			editingToken = QBEEditingToken(options)
			let menu = NSMenu()
			let keys = Array(options.options.keys)
			var index = 0
			for key in keys {
				let title = options.options[key]!
				let item = NSMenuItem(title: title, action: Selector("selectOption:"), keyEquivalent: "")
				item.state = (key == options.value) ? NSOnState : NSOffState
				item.tag = index
				menu.addItem(item)
				index++
			}
			return menu
		}
		else if let options = representedObject as? QBESentenceList {
			editingToken = QBEEditingToken(options)
			let menu = NSMenu()
			menu.autoenablesItems = false
			let loadingItem = NSMenuItem(title: NSLocalizedString("Loading...", comment: ""), action: Selector("dismissInputEditor:"), keyEquivalent: "")
			loadingItem.enabled = false
			menu.addItem(loadingItem)

			let queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
			dispatch_async(queue) {
				options.optionsProvider { [weak self] (itemsFallible) in
					asyncMain {
						menu.removeAllItems()

						switch itemsFallible {
						case .Success(let items):
							self?.editingToken?.options = items
							var index = 0
							for item in items {
								let menuItem = NSMenuItem(title: item, action: Selector("selectListOption:"), keyEquivalent: "")
								menuItem.tag = index
								menu.addItem(menuItem)
								index++
							}

						case .Failure(let e):
							let errorItem = NSMenuItem(title: e, action: Selector("dismissInputEditor:"), keyEquivalent: "")
							errorItem.enabled = false
							menu.addItem(errorItem)
							break
						}
					}
				}
			}

			return menu
		}
		else if let inputToken = representedObject as? QBESentenceTextInput {
			editingToken = QBEEditingToken(inputToken)
			let borderView = NSView()
			borderView.frame = NSMakeRect(0, 0, 250, 22+2+8)
			let textField = NSTextField(frame: NSMakeRect(8, 8, 250 - 2*8, 22))
			textField.stringValue = inputToken.label
			textField.delegate = self
			textField.autoresizingMask = []
			borderView.addSubview(textField)

			let item = NSMenuItem()
			item.view = borderView
			let menu = NSMenu()
			menu.addItem(item)
			menu.addItem(NSMenuItem(title: NSLocalizedString("OK", comment: ""), action: Selector("dismissInputEditor:"), keyEquivalent: ""))

			return menu
		}
		else if let inputToken = representedObject as? QBESentenceFormula {
			editingToken = QBEEditingToken(inputToken)

			/* We want to show a popover, but NSTokenField only lets us show a menu. So return an empty menu and 
			asynchronously present a popover right at this location */
			if let event = self.view.window?.currentEvent {
				asyncMain {
					self.editFormula(event)
				}
			}

			return NSMenu()
		}
		else if let inputToken = representedObject as? QBESentenceFile {
			self.editingToken = QBEEditingToken(inputToken)

			let menu = NSMenu()
			if inputToken.isDirectory {
				menu.addItem(NSMenuItem(title: NSLocalizedString("Select directory...", comment: ""), action: Selector("selectFile:"), keyEquivalent: ""))
			}
			else {
				menu.addItem(NSMenuItem(title: NSLocalizedString("Select file...", comment: ""), action: Selector("selectFile:"), keyEquivalent: ""))
			}
			let showItem = NSMenuItem(title: NSLocalizedString("Show in Finder", comment: ""), action: Selector("showFileInFinder:"), keyEquivalent: "")
			showItem.enabled = inputToken.file != nil
			menu.addItem(showItem)
			return menu
		}
		return nil
	}

	@IBAction func showFileInFinder(sender: NSObject) {
		if let token = editingToken?.token as? QBESentenceFile, let file = token.file?.url {
			NSWorkspace.sharedWorkspace().activateFileViewerSelectingURLs([file])
		}
	}

	@IBAction func selectFile(sender: NSObject) {
		if let token = editingToken?.token as? QBESentenceFile, let s = editingStep {
			if token.mustExist || token.isDirectory {
				let no = NSOpenPanel()
				if token.isDirectory {
					no.canChooseDirectories = true
					no.canCreateDirectories = true
				}
				else {
					no.canChooseFiles = true
					no.allowedFileTypes = token.allowedFileTypes
				}

				no.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
					if result==NSFileHandlingPanelOKButton {
						let url = no.URLs[0]
						token.change(QBEFileReference.URL(url))
						self.delegate?.sentenceView(self, didChangeStep: s)
						self.updateView()
					}
				})

			}
			else {
				let no = NSSavePanel()
				no.allowedFileTypes = token.allowedFileTypes
				no.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
					if result==NSFileHandlingPanelOKButton {
						if let url = no.URL {
							token.change(QBEFileReference.URL(url))
							self.delegate?.sentenceView(self, didChangeStep: s)
							self.updateView()
						}
					}
				})
			}
		}
	}

	@IBAction func dismissInputEditor(sender: NSObject) {
		// Do nothing
	}

	private func showPopoverAtToken(viewController: NSViewController) {
		let displayRect = NSMakeRect((NSEvent.mouseLocation().x - 2.5), (NSEvent.mouseLocation().y - 2.5), 5, 5)
		if let realRect = self.view.window?.convertRectFromScreen(displayRect) {
			let viewRect = self.view.convertRect(realRect, fromView: nil)
			self.presentViewController(viewController, asPopoverRelativeToRect: viewRect, ofView: self.view, preferredEdge: NSRectEdge.MinY, behavior: NSPopoverBehavior.Transient)
		}
	}

	@IBAction func selectOption(sender: NSObject) {
		if let options = editingToken?.token as? QBESentenceOptions, let menuItem = sender as? NSMenuItem, let s = editingStep {
			let keys = Array(options.options.keys)
			if keys.count > menuItem.tag {
				let value = keys[menuItem.tag]
				options.select(value)
				self.delegate?.sentenceView(self, didChangeStep: s)
				updateView()
			}
			self.editingToken = nil
		}
	}

	@IBAction func selectListOption(sender: NSObject) {
		if let listToken = editingToken?.token as? QBESentenceList, let options = editingToken?.options, let menuItem = sender as? NSMenuItem, let s = editingStep {
			let value = options[menuItem.tag]
			listToken.select(value)
			self.delegate?.sentenceView(self, didChangeStep: s)
			updateView()
		}
		self.editingToken = nil
	}

	private func updateView() {
		self.tokenField.hidden =  self.editingStep == nil
		self.configureButton.hidden = self.editingStep == nil

		if let s = editingStep, let locale = delegate?.locale {
			let sentence = s.sentence(locale, variant: self.variant)
			tokenField.objectValue = sentence.tokens.map({ return $0 as! NSObject })
			configureButton.enabled = QBEFactory.sharedInstance.hasViewForStep(s)
		}
		else {
			tokenField.objectValue = []
			configureButton.enabled = false
		}
	}

	func configure(step: QBEStep?, variant: QBESentenceVariant, delegate: QBESentenceViewDelegate?) {
		if self.editingStep != step || step == nil {
			let tr = CATransition()
			tr.duration = 0.3
			tr.type = kCATransitionPush
			tr.subtype = self.editingStep == nil ? kCATransitionFromTop : kCATransitionFromBottom
			tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
			self.view.layer?.addAnimation(tr, forKey: kCATransition)

			self.editingStep = step
			self.variant = variant
		}

		self.delegate = delegate
		updateView()
		self.view.window?.update()

		/* Check whether the window is visible before showing the tip, because this may get called early while setting
		up views, or while we are editing a formula (which occludes the configure button) */
		if let s = step where QBEFactory.sharedInstance.hasViewForStep(s) && (self.view.window?.visible == true) {
			QBESettings.sharedInstance.showTip("sentenceView.configureButton") {
				self.showTip(NSLocalizedString("Click here to change additional settings for this step.", comment: ""), atView: self.configureButton)
			}
		}
	}

	@IBAction func configure(sender: NSObject) {
		if let s = self.editingStep, let stepView = QBEFactory.sharedInstance.viewForStep(s.self, delegate: self) {
			self.presentViewController(stepView, asPopoverRelativeToRect: configureButton.frame, ofView: self.view, preferredEdge: NSRectEdge.MinY, behavior: NSPopoverBehavior.Semitransient)
		}
	}

	func formulaEditor(view: QBEFormulaEditorViewController, didChangeExpression newExpression: Expression?) {
		if let inputToken = editingToken?.token as? QBESentenceFormula, let s = self.editingStep {
			inputToken.change(newExpression ?? Literal(Value.EmptyValue))
			self.delegate?.sentenceView(self, didChangeStep: s)
			updateView()
		}
	}

	func editFormula(sender: NSEvent) {
		if let inputToken = editingToken?.token as? QBESentenceFormula, let locale = self.delegate?.locale {
			if let editor = self.storyboard?.instantiateControllerWithIdentifier("formulaEditor") as? QBEFormulaEditorViewController {
				editor.delegate = self
				editor.startEditingExpression(inputToken.expression, locale: locale)
				let windowRect = NSMakeRect(sender.locationInWindow.x + 5, sender.locationInWindow.y, 1, 1)
				var viewRect = self.view.convertRect(windowRect, fromView: nil)
				viewRect.origin.y = 0.0
				self.presentViewController(editor, asPopoverRelativeToRect: viewRect, ofView: self.view, preferredEdge: NSRectEdge.MinY, behavior: NSPopoverBehavior.Transient)
			}
		}
	}

	func stepView(view: QBEStepViewController, didChangeConfigurationForStep step: QBEStep) {
		asyncMain { self.updateView() }
		self.delegate?.sentenceView(self, didChangeStep: step)
	}

	var locale: Locale { return self.delegate!.locale }
}