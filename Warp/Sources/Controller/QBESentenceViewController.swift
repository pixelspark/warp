import Cocoa
import WarpCore

protocol QBESentenceViewDelegate: NSObjectProtocol {
	func sentenceView(view: QBESentenceViewController, didChangeConfigurable: QBEConfigurable)
	var locale: Locale { get }
}

class QBESentenceViewController: NSViewController, NSTokenFieldDelegate, NSTextFieldDelegate,
	QBEFormulaEditorViewDelegate, QBEConfigurableViewDelegate, QBESetEditorDelegate {
	@IBOutlet var tokenField: NSTokenField!
	@IBOutlet var configureButton: NSButton!

	var variant: QBESentenceVariant = .Neutral
	private var editingToken: QBEEditingToken? = nil
	private var editingConfigurable: QBEConfigurable? = nil
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
		if let inputToken = editingToken?.token as? QBESentenceTextInput, let s = editingConfigurable {
			// Was a formula typed in?
			if text.hasPrefix("=") {
				if let formula = Formula(formula: text, locale: self.locale) where formula.root.isConstant {
					text = locale.localStringFor(formula.root.apply(Row(), foreign: nil, inputValue: nil))
				}
			}

			if inputToken.change(text) {
				self.delegate?.sentenceView(self, didChangeConfigurable: s)
				updateView()
				return true
			}
			return false
		}
		else if let inputToken = editingToken?.token as? QBESentenceFormula, let s = editingConfigurable, let locale = self.delegate?.locale {
			if let formula = Formula(formula: text, locale: locale) {
				inputToken.change(formula.root)
				self.delegate?.sentenceView(self, didChangeConfigurable: s)
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
				let item = NSMenuItem(title: title, action: #selector(QBESentenceViewController.selectOption(_:)), keyEquivalent: "")
				item.state = (key == options.value) ? NSOnState : NSOffState
				item.tag = index
				menu.addItem(item)
				index += 1
			}
			return menu
		}
		else if let options = representedObject as? QBESentenceList {
			editingToken = QBEEditingToken(options)
			let menu = NSMenu()
			menu.autoenablesItems = false
			let loadingItem = NSMenuItem(title: NSLocalizedString("Loading...", comment: ""), action: nil, keyEquivalent: "")
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

							if items.isEmpty {
								let loadingItem = NSMenuItem(title: NSLocalizedString("(no items)", comment: ""), action: nil, keyEquivalent: "")
								loadingItem.enabled = false
								menu.addItem(loadingItem)
							}
							else {
								var index = 0
								for item in items {
									let menuItem = NSMenuItem(title: item, action: #selector(QBESentenceViewController.selectListOption(_:)), keyEquivalent: "")
									menuItem.tag = index
									menu.addItem(menuItem)
									index += 1
								}
							}

						case .Failure(let e):
							let errorItem = NSMenuItem(title: e, action: #selector(QBESentenceViewController.dismissInputEditor(_:)), keyEquivalent: "")
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
			menu.autoenablesItems = false
			menu.addItem(item)
			menu.addItem(NSMenuItem(title: NSLocalizedString("OK", comment: ""), action: #selector(QBESentenceViewController.dismissInputEditor(_:)), keyEquivalent: ""))

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
		else if let inputToken = representedObject as? QBESentenceSet {
			editingToken = QBEEditingToken(inputToken)

			/* We want to show a popover, but NSTokenField only lets us show a menu. So return an empty menu and
			asynchronously present a popover right at this location */
			if let event = self.view.window?.currentEvent {
				asyncMain {
					self.editSet(event)
				}
			}

			return NSMenu()
		}
		else if let inputToken = representedObject as? QBESentenceFile {
			self.editingToken = QBEEditingToken(inputToken)

			let menu = NSMenu()

			// Items related to the currently selected file
			let showItem = NSMenuItem(title: NSLocalizedString("Show in Finder", comment: ""), action: #selector(QBESentenceViewController.showFileInFinder(_:)), keyEquivalent: "")
			showItem.enabled = inputToken.file != nil
			menu.addItem(showItem)

			menu.addItem(NSMenuItem.separatorItem())

			// Items for selecting a new file
			if inputToken.isDirectory {
				menu.addItem(NSMenuItem(title: NSLocalizedString("Select directory...", comment: ""), action: #selector(QBESentenceViewController.selectFile(_:)), keyEquivalent: ""))
			}
			else {
				menu.addItem(NSMenuItem(title: NSLocalizedString("Select file...", comment: ""), action: #selector(QBESentenceViewController.selectFile(_:)), keyEquivalent: ""))
			}

			if case .Reading(let canCreate) = inputToken.mode where canCreate {
				let createItem = NSMenuItem(title: "New file...".localized, action: #selector(QBESentenceViewController.createNewFile(_:)), keyEquivalent: "")
				menu.addItem(createItem)
			}

			// Items for selecting a recent file
			if let recents = self.fileRecentsForSelectedToken?.loadRememberedFiles() {
				menu.addItem(NSMenuItem.separatorItem())

				let label = NSMenuItem(title: "Recent files".localized, action: nil, keyEquivalent: "")
				label.enabled = false
				menu.addItem(label)

				for recent in recents {
					if let u = recent.url, let title = u.lastPathComponent {
						let recentItem = NSMenuItem(title:  title, action: #selector(QBESentenceViewController.selectURL(_:)), keyEquivalent: "")
						recentItem.representedObject = u
						menu.addItem(recentItem)
					}
				}
			}

			return menu
		}
		return nil
	}

	@IBAction func selectURL(sender: NSObject) {
		if let nm = sender as? NSMenuItem, let url = nm.representedObject as? NSURL {
			if let token = editingToken?.token as? QBESentenceFile, let s = editingConfigurable {
				let fileRef = QBEFileReference.URL(url)
				token.change(fileRef)
				self.delegate?.sentenceView(self, didChangeConfigurable: s)
				self.updateView()
			}
		}
	}

	@IBAction func createNewFile(sender: NSObject) {
		self.selectFileWithPanel(true)
	}

	@IBAction func showFileInFinder(sender: NSObject) {
		if let token = editingToken?.token as? QBESentenceFile, let file = token.file?.url {
			NSWorkspace.sharedWorkspace().activateFileViewerSelectingURLs([file])
		}
	}

	@IBAction func selectFile(sender: NSObject) {
		self.selectFileWithPanel(false)
	}

	private func selectFileWithPanel(createNew: Bool) {
		if let token = editingToken?.token as? QBESentenceFile, let s = editingConfigurable {
			let savePanel: NSSavePanel

			switch token.mode {
			case .Reading(canCreate: let canCreate):
				if token.isDirectory {
					let no = NSOpenPanel()
					no.canChooseDirectories = true
					no.canCreateDirectories = canCreate
					savePanel = no
				}
				else if canCreate && createNew {
					savePanel = NSSavePanel()
				}
				else {
					let no = NSOpenPanel()
					no.canChooseFiles = true
					no.allowedFileTypes = token.allowedFileTypes
					savePanel = no
				}

			case .Writing():
				savePanel = NSSavePanel()
			}

			savePanel.allowedFileTypes = token.allowedFileTypes
			savePanel.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
				if result==NSFileHandlingPanelOKButton {
					if let url = savePanel.URL {
						let fileRef = QBEFileReference.URL(url)
						token.change(fileRef)
						self.fileRecentsForSelectedToken?.remember(fileRef)
						self.delegate?.sentenceView(self, didChangeConfigurable: s)
						self.updateView()
					}
				}
			})
		}
	}

	private var fileRecentsForSelectedToken: QBEFileRecents? {
		if let token = editingToken?.token as? QBESentenceFile {
			return QBEFileRecents(key: token.allowedFileTypes.joinWithSeparator(";"))
		}
		return nil
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
		if let options = editingToken?.token as? QBESentenceOptions, let menuItem = sender as? NSMenuItem, let s = editingConfigurable {
			let keys = Array(options.options.keys)
			if keys.count > menuItem.tag {
				let value = keys[menuItem.tag]
				options.select(value)
				self.delegate?.sentenceView(self, didChangeConfigurable: s)
				updateView()
			}
			self.editingToken = nil
		}
	}

	@IBAction func selectListOption(sender: NSObject) {
		if let listToken = editingToken?.token as? QBESentenceList, let options = editingToken?.options, let menuItem = sender as? NSMenuItem, let s = editingConfigurable {
			let value = options[menuItem.tag]
			listToken.select(value)
			self.delegate?.sentenceView(self, didChangeConfigurable: s)
			updateView()
		}
		self.editingToken = nil
	}

	private func updateView() {
		self.tokenField.hidden =  self.editingConfigurable == nil
		self.configureButton.hidden = self.editingConfigurable == nil

		if let s = editingConfigurable, let locale = delegate?.locale {
			let sentence = s.sentence(locale, variant: self.variant)
			tokenField.objectValue = sentence.tokens.map({ return $0 as! NSObject })
			configureButton.enabled = QBEFactory.sharedInstance.hasViewForConfigurable(s)
		}
		else {
			tokenField.objectValue = []
			configureButton.enabled = false
		}
	}

	func startConfiguring(configurable: QBEConfigurable?, variant: QBESentenceVariant, delegate: QBESentenceViewDelegate?) {
		if self.editingConfigurable != configurable || configurable == nil {
			let tr = CATransition()
			tr.duration = 0.3
			tr.type = kCATransitionPush
			tr.subtype = self.editingConfigurable == nil ? kCATransitionFromTop : kCATransitionFromBottom
			tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
			self.view.layer?.addAnimation(tr, forKey: kCATransition)

			self.editingConfigurable = configurable
			self.variant = variant
		}

		self.delegate = delegate
		updateView()
		self.view.window?.update()

		/* Check whether the window is visible before showing the tip, because this may get called early while setting
		up views, or while we are editing a formula (which occludes the configure button) */
		if let s = configurable where QBEFactory.sharedInstance.hasViewForConfigurable(s) && (self.view.window?.visible == true) {
			QBESettings.sharedInstance.showTip("sentenceView.configureButton") {
				self.showTip(NSLocalizedString("Click here to change additional settings for this step.", comment: ""), atView: self.configureButton)
			}
		}
	}

	/** Opens the popover containing more detailed configuration options for the current configurable. */
	@IBAction func configure(sender: AnyObject) {
		if let s = self.editingConfigurable, let stepView = QBEFactory.sharedInstance.viewForConfigurable(s.self, delegate: self) {
			self.presentViewController(stepView, asPopoverRelativeToRect: configureButton.frame, ofView: self.view, preferredEdge: NSRectEdge.MinY, behavior: NSPopoverBehavior.Semitransient)
		}
	}

	func formulaEditor(view: QBEFormulaEditorViewController, didChangeExpression newExpression: Expression?) {
		if let inputToken = editingToken?.token as? QBESentenceFormula, let s = self.editingConfigurable {
			inputToken.change(newExpression ?? Literal(Value.EmptyValue))
			self.delegate?.sentenceView(self, didChangeConfigurable: s)
			updateView()
			view.updateContextInformation(inputToken)
		}
	}

	func setEditor(editor: QBESetEditorViewController, didChangeSelection selection: Set<String>) {
		if let inputToken = editingToken?.token as? QBESentenceSet, let s = self.editingConfigurable {
			inputToken.select(selection)
			self.delegate?.sentenceView(self, didChangeConfigurable: s)
			updateView()
		}
	}

	func editSet(sender: NSEvent) {
		if let inputToken = editingToken?.token as? QBESentenceSet {
			inputToken.provider { result in
				result.maybe { options in
					asyncMain {
						if let editor = self.storyboard?.instantiateControllerWithIdentifier("setEditor") as? QBESetEditorViewController {
							editor.delegate = self
							editor.possibleValues = Array(options)
							editor.possibleValues.sortInPlace()
							editor.selection = inputToken.value
							let windowRect = NSMakeRect(sender.locationInWindow.x + 5, sender.locationInWindow.y, 1, 1)
							var viewRect = self.view.convertRect(windowRect, fromView: nil)
							viewRect.origin.y = 0.0
							self.presentViewController(editor, asPopoverRelativeToRect: viewRect, ofView: self.view, preferredEdge: NSRectEdge.MinY, behavior: NSPopoverBehavior.Transient)
						}
					}
				}
			}
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
				editor.updateContextInformation(inputToken)
				self.presentViewController(editor, asPopoverRelativeToRect: viewRect, ofView: self.view, preferredEdge: NSRectEdge.MinY, behavior: NSPopoverBehavior.Transient)
			}
		}
	}

	var locale: Locale { return self.delegate!.locale }

	func configurableView(view: QBEConfigurableViewController, didChangeConfigurationFor c: QBEConfigurable) {
		asyncMain { self.updateView() }
		self.delegate?.sentenceView(self, didChangeConfigurable: c)
	}
}

private extension QBEFormulaEditorViewController {
	func updateContextInformation(sentence: QBESentenceFormula) {
		if let getContext = sentence.contextCallback {
			let job = Job(.UserInitiated)
			getContext(job) { result in
				switch result {
				case .Success(let r):
					asyncMain {
						self.exampleResult = self.expression?.apply(r.row, foreign: nil, inputValue: nil)
						self.columns = r.columns.sort({ return $0.name < $1.name })
					}

				case .Failure(_):
					asyncMain {
						self.exampleResult = nil
					}
				}
			}
		}
		else {
			self.columns = []
			self.exampleResult = nil
		}
	}
}

class QBESentenceTokenField: NSTokenField {
	override func layout() {
		self.preferredMaxLayoutWidth = self.frame.size.width
		super.layout()
	}
}