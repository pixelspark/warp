import Cocoa

class QBESentenceViewController: NSViewController, NSTokenFieldDelegate, NSTextFieldDelegate {
	@IBOutlet var tokenField: NSTokenField!
	@IBOutlet var formulaField: NSTextField!
	@IBOutlet var backButton: NSButton!
	@IBOutlet var configureButton: NSButton!

	private var editingToken: QBEEditingToken? = nil
	private var editingStep: QBEStep? = nil
	private var editingFormula: QBEEditingFormula? = nil
	private weak var delegate: QBESuggestionsViewDelegate? = nil

	private struct QBEEditingToken {
		let token: QBESentenceToken
		var options: [String]? = nil

		init(_ token: QBESentenceToken) {
			self.token = token
		}
	}

	private struct QBEEditingFormula {
		let value: QBEValue
		var callback: ((QBEValue) -> ())?
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
		let text = control.stringValue
		if let inputToken = editingToken?.token as? QBESentenceTextInput, let s = editingStep {
			if inputToken.change(text) {
				self.delegate?.suggestionsView(self, previewStep: s)
				updateView()
				return true
			}
			return false
		}
		else if let inputToken = editingToken?.token as? QBESentenceFormula, let s = editingStep, let locale = self.delegate?.locale {
			if let formula = QBEFormula(formula: text, locale: locale) {
				inputToken.change(formula.root)
				self.delegate?.suggestionsView(self, previewStep: s)
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
			let loadingItem = NSMenuItem(title: NSLocalizedString("Loading...", comment: ""), action: Selector("dismissInputEditor:"), keyEquivalent: "")
			loadingItem.enabled = false
			menu.addItem(loadingItem)

			options.optionsProvider { [weak self] (itemsFallible) in
				QBEAsyncMain {
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
		else if let inputToken = representedObject as? QBESentenceFormula, let locale = self.delegate?.locale {
			editingToken = QBEEditingToken(inputToken)
			let borderView = NSView()
			borderView.frame = NSMakeRect(0, 0, 250, 111+2+8)
			let textField = NSTextField(frame: NSMakeRect(8, 8, 250 - 2*8, 111))
			textField.font = NSFont.userFixedPitchFontOfSize(NSFont.systemFontSize())
			if let formula = QBEFormula(formula: inputToken.expression.toFormula(locale, topLevel: true), locale: locale) {
				textField.attributedStringValue = formula.syntaxColoredFormula
			}
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
		else if let inputToken = representedObject as? QBESentenceFile {
			self.editingToken = QBEEditingToken(inputToken)

			let menu = NSMenu()
			menu.addItem(NSMenuItem(title: NSLocalizedString("Select file...", comment: ""), action: Selector("selectFile:"), keyEquivalent: ""))
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
			let no = NSOpenPanel()
			no.canChooseFiles = true
			no.allowedFileTypes = token.allowedFileTypes

			no.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
				if result==NSFileHandlingPanelOKButton {
					let url = no.URLs[0]
					token.change(QBEFileReference.URL(url))
					self.delegate?.suggestionsView(self, previewStep: s)
					self.updateView()
				}
			})
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
				self.delegate?.suggestionsView(self, previewStep: s)
				updateView()
			}
			self.editingToken = nil
		}
	}

	@IBAction func selectListOption(sender: NSObject) {
		if let listToken = editingToken?.token as? QBESentenceList, let options = editingToken?.options, let menuItem = sender as? NSMenuItem, let s = editingStep {
			let value = options[menuItem.tag]
			listToken.select(value)
			self.delegate?.suggestionsView(self, previewStep: s)
			updateView()
		}
		self.editingToken = nil
	}

	func startEditingValue(value: QBEValue, callback: ((QBEValue) -> ())) {
		if let locale = delegate?.locale where value.isValid {
			self.editingFormula = QBEEditingFormula(value: value, callback: callback)
			self.formulaField.stringValue = locale.localStringFor(value)
		}
		else {
			self.editingFormula = nil
		}
		updateView()
	}

	@IBAction func updateFromFormulaField(sender: NSObject) {
		if let fc = editingFormula?.callback, let locale = delegate?.locale {
			fc(locale.valueForLocalString(formulaField.stringValue))
			editingFormula?.callback = nil
		}
	}

	@IBAction func stopEditingFormula(sender: NSObject) {
		if self.editingFormula != nil {
			self.editingFormula = nil
			let tr = CATransition()
			tr.duration = 0.3
			tr.type = kCATransitionReveal
			tr.subtype = kCATransitionFromRight
			tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
			self.view.layer?.addAnimation(tr, forKey: kCATransition)
			updateView()
		}
	}

	private func updateView() {
		let isEditingFormula = editingFormula != nil
		self.formulaField.hidden = !isEditingFormula
		self.backButton.hidden = !isEditingFormula || self.editingStep == nil
		self.tokenField.hidden = isEditingFormula || self.editingStep == nil
		self.configureButton.hidden = isEditingFormula || self.editingStep == nil

		if let s = editingStep, let locale = delegate?.locale {
			let sentence = s.sentence(locale)
			tokenField.objectValue = sentence.tokens.map({ return $0 as! NSObject })
			configureButton.enabled = QBEFactory.sharedInstance.hasViewForStep(s)
		}
		else {
			tokenField.objectValue = []
			configureButton.enabled = false
		}
	}

	func configure(step: QBEStep?, delegate: QBESuggestionsViewDelegate?) {
		if self.editingStep != step || step == nil {
			let tr = CATransition()
			tr.duration = 0.3
			tr.type = kCATransitionPush
			tr.subtype = self.editingStep == nil ? kCATransitionFromTop : kCATransitionFromBottom
			tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
			self.view.layer?.addAnimation(tr, forKey: kCATransition)

			self.editingStep = step
			self.editingFormula = nil
		}

		self.delegate = delegate
		updateView()

		/* Check whether the window is visible before showing the tip, because this may get called early while setting
		up views */
		if let s = step where QBEFactory.sharedInstance.hasViewForStep(s) && (self.view.window?.visible == true) {
			QBESettings.sharedInstance.showTip("sentenceView.configureButton") {
				self.showTip(NSLocalizedString("Click here to change additional settings for this step.", comment: ""), atView: self.configureButton)
			}
		}
	}

	@IBAction func configure(sender: NSObject) {
		if let s = self.editingStep, let stepView = QBEFactory.sharedInstance.viewForStep(s.self, delegate: delegate!) {
			self.presentViewController(stepView, asPopoverRelativeToRect: configureButton.frame, ofView: self.view, preferredEdge: NSRectEdge.MinY, behavior: NSPopoverBehavior.Semitransient)
		}
	}
}