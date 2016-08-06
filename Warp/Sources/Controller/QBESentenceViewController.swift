import Cocoa
import WarpCore

protocol QBESentenceViewDelegate: NSObjectProtocol {
	func sentenceView(_ view: QBESentenceViewController, didChangeConfigurable: QBEConfigurable)
	var locale: Language { get }
}

class QBESentenceViewController: NSViewController, NSTokenFieldDelegate, NSTextFieldDelegate,
	QBEFormulaEditorViewDelegate, QBEConfigurableViewDelegate, QBESetEditorDelegate, QBEListEditorDelegate {
	@IBOutlet var tokenField: NSTokenField!
	@IBOutlet var configureButton: NSButton!

	var variant: QBESentenceVariant = .neutral
	private var editingToken: QBEEditingToken? = nil
	private var editingConfigurable: QBEConfigurable? = nil
	private weak var delegate: QBESentenceViewDelegate? = nil

	var enabled: Bool {
		get {
			return tokenField.isEnabled
		}
		set {
			assertMainThread()
			tokenField.isEnabled = enabled
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

	func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: AnyObject) -> NSTokenStyle {
		if let r = representedObject as? QBESentenceToken {
			return r.isToken ? NSTokenStyle.default : NSTokenStyle.none
		}
		return NSTokenStyle.none
	}

	func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: AnyObject) -> String? {
		if let x = representedObject as? QBESentenceToken {
			return x.label
		}
		return nil
	}

	func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: AnyObject) -> Bool {
		return true
	}

	/** The 'change' functions execute changes to tokens while also managing undo/redo actions. */
	@discardableResult private func change(token inputToken: QBESentenceTextInput, to text: String) -> Bool {
		let oldValue = inputToken.label
		if inputToken.change(text) {
			undoManager?.registerUndoWithTarget(inputToken) { [weak self] token in
				self?.change(token: inputToken, to: oldValue)
			}
			undoManager?.setActionName(String(format: "change '%@' to '%@'".localized, oldValue, text))

			if let s = self.editingConfigurable {
				self.delegate?.sentenceView(self, didChangeConfigurable: s)
			}
			updateView()
			return true
		}
		return false
	}

	@discardableResult private func change(token inputToken: QBESentenceFormula, to expression: Expression) -> Bool {
		let oldValue = inputToken.expression
		let oldFormula = oldValue.toFormula(self.delegate?.locale ?? Language())
		let newFormula = expression.toFormula(self.delegate?.locale ?? Language())

		if inputToken.change(expression) {
			undoManager?.registerUndoWithTarget(inputToken) { [weak self] token in
				self?.change(token: inputToken, to: oldValue)
			}
			undoManager?.setActionName(String(format: "change '%@' to '%@'".localized, oldFormula, newFormula))

			if let s = self.editingConfigurable {
				self.delegate?.sentenceView(self, didChangeConfigurable: s)
			}
			updateView()
			return true
		}
		return false
	}

	private func change(token inputToken: QBESentenceSet, to set: Set<String>) {
		let oldValue = inputToken.value
		inputToken.select(set)
		undoManager?.registerUndoWithTarget(inputToken) { [weak self] token in
			self?.change(token: inputToken, to: oldValue)
		}
		undoManager?.setActionName(String(format: "change selection".localized))

		if let s = self.editingConfigurable {
			self.delegate?.sentenceView(self, didChangeConfigurable: s)
		}
		updateView()
	}

	@discardableResult private func change(token inputToken: QBESentenceColumns, to selection: OrderedSet<Column>) {
		let oldValue = inputToken.value

		inputToken.select(selection)
		undoManager?.registerUndoWithTarget(inputToken) { [weak self] token in
			self?.change(token: inputToken, to: oldValue)
		}

		if let s = self.editingConfigurable {
			undoManager?.setActionName(String(format: "change selection".localized))
			self.delegate?.sentenceView(self, didChangeConfigurable: s)
		}
		updateView()
	}

	@discardableResult private func change(token inputToken: QBESentenceList, to value: String) -> Bool {
		let oldValue = inputToken.value
		inputToken.select(value)
		undoManager?.registerUndoWithTarget(inputToken) { [weak self] token in
			self?.change(token: inputToken, to: oldValue)
		}
		undoManager?.setActionName(String(format: "change '%@' to '%@'".localized, oldValue, value))

		if let s = self.editingConfigurable {
			self.delegate?.sentenceView(self, didChangeConfigurable: s)
		}
		updateView()
		return true
	}

	@discardableResult private func change(token inputToken: QBESentenceOptions, to value: String) -> Bool {
		let oldValue = inputToken.value
		inputToken.select(value)
		undoManager?.registerUndoWithTarget(inputToken) { [weak self] token in
			self?.change(token: inputToken, to: oldValue)
		}

		undoManager?.setActionName(String(format: "change '%@' to '%@'".localized, inputToken.options[oldValue]!, inputToken.options[value]!))

		if let s = self.editingConfigurable {
			self.delegate?.sentenceView(self, didChangeConfigurable: s)
		}
		updateView()
		return true
	}

	func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
		var text = control.stringValue
		if let inputToken = editingToken?.token as? QBESentenceTextInput {
			// Was a formula typed in?
			if text.hasPrefix("=") {
				if let formula = Formula(formula: text, locale: self.locale), formula.root.isConstant {
					text = locale.localStringFor(formula.root.apply(Row(), foreign: nil, inputValue: nil))
				}
			}
			return self.change(token: inputToken, to: text)
		}

		return true
	}

	func tokenField(_ tokenField: NSTokenField, menuForRepresentedObject representedObject: AnyObject) -> NSMenu? {
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
			loadingItem.isEnabled = false
			menu.addItem(loadingItem)

			let queue = DispatchQueue.global(qos: .userInitiated)
			queue.async {
				options.optionsProvider { [weak self] (itemsFallible) in
					asyncMain {
						menu.removeAllItems()

						switch itemsFallible {
						case .success(let items):
							self?.editingToken?.options = items

							if items.isEmpty {
								let loadingItem = NSMenuItem(title: NSLocalizedString("(no items)", comment: ""), action: nil, keyEquivalent: "")
								loadingItem.isEnabled = false
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

						case .failure(let e):
							let errorItem = NSMenuItem(title: e, action: #selector(QBESentenceViewController.dismissInputEditor(_:)), keyEquivalent: "")
							errorItem.isEnabled = false
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
		else if let inputToken = representedObject as? QBESentenceColumns {
			editingToken = QBEEditingToken(inputToken)

			/* We want to show a popover, but NSTokenField only lets us show a menu. So return an empty menu and
			asynchronously present a popover right at this location */
			if let event = self.view.window?.currentEvent {
				asyncMain {
					self.editList(event)
				}
			}

			return NSMenu()
		}
		else if let inputToken = representedObject as? QBESentenceFile {
			self.editingToken = QBEEditingToken(inputToken)

			let menu = NSMenu()

			// Items related to the currently selected file
			let showItem = NSMenuItem(title: NSLocalizedString("Show in Finder", comment: ""), action: #selector(QBESentenceViewController.showFileInFinder(_:)), keyEquivalent: "")
			showItem.isEnabled = inputToken.file != nil
			menu.addItem(showItem)

			menu.addItem(NSMenuItem.separator())

			// Items for selecting a new file
			if inputToken.isDirectory {
				menu.addItem(NSMenuItem(title: NSLocalizedString("Select directory...", comment: ""), action: #selector(QBESentenceViewController.selectFile(_:)), keyEquivalent: ""))
			}
			else {
				menu.addItem(NSMenuItem(title: NSLocalizedString("Select file...", comment: ""), action: #selector(QBESentenceViewController.selectFile(_:)), keyEquivalent: ""))
			}

			if case .reading(let canCreate) = inputToken.mode, canCreate {
				let createItem = NSMenuItem(title: "New file...".localized, action: #selector(QBESentenceViewController.createNewFile(_:)), keyEquivalent: "")
				menu.addItem(createItem)
			}

			// Items for selecting a recent file
			if let recents = self.fileRecentsForSelectedToken?.loadRememberedFiles() {
				menu.addItem(NSMenuItem.separator())

				let label = NSMenuItem(title: "Recent files".localized, action: nil, keyEquivalent: "")
				label.isEnabled = false
				menu.addItem(label)

				for recent in recents {
					if let u = recent.url {
						let title = u.lastPathComponent
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

	@IBAction func selectURL(_ sender: NSObject) {
		if let nm = sender as? NSMenuItem, let url = nm.representedObject as? URL {
			if let token = editingToken?.token as? QBESentenceFile, let s = editingConfigurable {
				let fileRef = QBEFileReference.absolute(url)
				token.change(fileRef)
				self.delegate?.sentenceView(self, didChangeConfigurable: s)
				self.updateView()
			}
		}
	}

	@IBAction func createNewFile(_ sender: NSObject) {
		self.selectFileWithPanel(true)
	}

	@IBAction func showFileInFinder(_ sender: NSObject) {
		if let token = editingToken?.token as? QBESentenceFile, let file = token.file?.url {
			NSWorkspace.shared().activateFileViewerSelecting([file as URL])
		}
	}

	@IBAction func selectFile(_ sender: NSObject) {
		self.selectFileWithPanel(false)
	}

	private func selectFileWithPanel(_ createNew: Bool) {
		if let token = editingToken?.token as? QBESentenceFile, let s = editingConfigurable {
			let savePanel: NSSavePanel

			switch token.mode {
			case .reading(canCreate: let canCreate):
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

			case .writing():
				savePanel = NSSavePanel()
			}

			savePanel.allowedFileTypes = token.allowedFileTypes
			savePanel.beginSheetModal(for: self.view.window!, completionHandler: { (result: Int) -> Void in
				if result==NSFileHandlingPanelOKButton {
					if let url = savePanel.url {
						let fileRef = QBEFileReference.absolute(url)
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
			return QBEFileRecents(key: token.allowedFileTypes.joined(separator: ";"))
		}
		return nil
	}

	@IBAction func dismissInputEditor(_ sender: NSObject) {
		// Do nothing
	}

	private func showPopoverAtToken(_ viewController: NSViewController) {
		let displayRect = NSMakeRect((NSEvent.mouseLocation().x - 2.5), (NSEvent.mouseLocation().y - 2.5), 5, 5)
		if let realRect = self.view.window?.convertFromScreen(displayRect) {
			let viewRect = self.view.convert(realRect, from: nil)
			self.presentViewController(viewController, asPopoverRelativeTo: viewRect, of: self.view, preferredEdge: NSRectEdge.minY, behavior: NSPopoverBehavior.transient)
		}
	}

	@IBAction func selectOption(_ sender: NSObject) {
		if let options = editingToken?.token as? QBESentenceOptions, let menuItem = sender as? NSMenuItem {
			let keys = Array(options.options.keys)
			if keys.count > menuItem.tag {
				let value = keys[menuItem.tag]
				change(token: options, to: value)
			}
			self.editingToken = nil
		}
	}

	@IBAction func selectListOption(_ sender: NSObject) {
		if let listToken = editingToken?.token as? QBESentenceList, let options = editingToken?.options, let menuItem = sender as? NSMenuItem {
			let value = options[menuItem.tag]
			self.change(token: listToken, to: value)
		}
		self.editingToken = nil
	}

	private func updateView() {
		self.tokenField.isHidden =  self.editingConfigurable == nil
		self.configureButton.isHidden = self.editingConfigurable == nil

		if let s = editingConfigurable, let locale = delegate?.locale {
			let sentence = s.sentence(locale, variant: self.variant)
			tokenField.objectValue = sentence.tokens.map({ return $0 as! NSObject })
			configureButton.isEnabled = QBEFactory.sharedInstance.hasViewForConfigurable(s)
		}
		else {
			tokenField.objectValue = []
			configureButton.isEnabled = false
		}
	}

	func startConfiguring(_ configurable: QBEConfigurable?, variant: QBESentenceVariant, delegate: QBESentenceViewDelegate?) {
		if self.editingConfigurable != configurable || configurable == nil {
			let tr = CATransition()
			tr.duration = 0.3
			tr.type = kCATransitionPush
			tr.subtype = self.editingConfigurable == nil ? kCATransitionFromTop : kCATransitionFromBottom
			tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
			self.view.layer?.add(tr, forKey: kCATransition)

			self.editingConfigurable = configurable
			self.variant = variant
		}

		self.delegate = delegate
		updateView()
		self.view.window?.update()

		/* Check whether the window is visible before showing the tip, because this may get called early while setting
		up views, or while we are editing a formula (which occludes the configure button) */
		if let s = configurable, QBEFactory.sharedInstance.hasViewForConfigurable(s) && (self.view.window?.isVisible == true) {
			QBESettings.sharedInstance.showTip("sentenceView.configureButton") {
				self.showTip(NSLocalizedString("Click here to change additional settings for this step.", comment: ""), atView: self.configureButton)
			}
		}
	}

	/** Opens the popover containing more detailed configuration options for the current configurable. */
	@IBAction func configure(_ sender: AnyObject) {
		if let s = self.editingConfigurable, let stepView = QBEFactory.sharedInstance.viewForConfigurable(s.self, delegate: self) {
			self.presentViewController(stepView, asPopoverRelativeTo: configureButton.frame, of: self.view, preferredEdge: NSRectEdge.minY, behavior: NSPopoverBehavior.semitransient)
		}
	}

	func formulaEditor(_ view: QBEFormulaEditorViewController, didChangeExpression newExpression: Expression?) {
		if let inputToken = editingToken?.token as? QBESentenceFormula {
			self.change(token: inputToken, to: newExpression ?? Identity())
			view.updateContextInformation(inputToken)
		}
	}

	func setEditor(_ editor: QBESetEditorViewController, didChangeSelection selection: Set<String>) {
		if let inputToken = editingToken?.token as? QBESentenceSet {
			self.change(token: inputToken, to: selection)
		}
	}

	func listEditor(_ editor: QBEListEditorViewController, didChangeSelection selection: [String]) {
		if let inputToken = editingToken?.token as? QBESentenceColumns {
			let cols = selection.map { Column($0) }.uniqueElements
			editor.selection = cols.map { $0.name }
			self.change(token: inputToken, to: OrderedSet<Column>(cols))
		}
	}

	func editList(_ sender: NSEvent) {
		if let inputToken = editingToken?.token as? QBESentenceColumns {
			asyncMain {
				if let editor = self.storyboard?.instantiateController(withIdentifier: "listEditor") as? QBEListEditorViewController {
					editor.delegate = self
					editor.selection = inputToken.value.map { $0.name }
					let windowRect = NSMakeRect(sender.locationInWindow.x + 5, sender.locationInWindow.y, 1, 1)
					var viewRect = self.view.convert(windowRect, from: nil)
					viewRect.origin.y = 0.0
					self.presentViewController(editor, asPopoverRelativeTo: viewRect, of: self.view, preferredEdge: .minY, behavior: .transient)
				}
			}
		}
	}

	func editSet(_ sender: NSEvent) {
		if let inputToken = editingToken?.token as? QBESentenceSet {
			inputToken.provider { result in
				result.maybe { options in
					asyncMain {
						if let editor = self.storyboard?.instantiateController(withIdentifier: "setEditor") as? QBESetEditorViewController {
							editor.delegate = self
							editor.possibleValues = Array(options)
							editor.possibleValues.sort()
							editor.selection = inputToken.value
							let windowRect = NSMakeRect(sender.locationInWindow.x + 5, sender.locationInWindow.y, 1, 1)
							var viewRect = self.view.convert(windowRect, from: nil)
							viewRect.origin.y = 0.0
							self.presentViewController(editor, asPopoverRelativeTo: viewRect, of: self.view, preferredEdge: .minY, behavior: .transient)
						}
					}
				}
			}
		}
	}

	func editFormula(_ sender: NSEvent) {
		if let inputToken = editingToken?.token as? QBESentenceFormula, let locale = self.delegate?.locale {
			if let editor = self.storyboard?.instantiateController(withIdentifier: "formulaEditor") as? QBEFormulaEditorViewController {
				editor.delegate = self
				editor.startEditingExpression(inputToken.expression, locale: locale)
				let windowRect = NSMakeRect(sender.locationInWindow.x + 5, sender.locationInWindow.y, 1, 1)
				var viewRect = self.view.convert(windowRect, from: nil)
				viewRect.origin.y = 0.0
				editor.updateContextInformation(inputToken)
				self.presentViewController(editor, asPopoverRelativeTo: viewRect, of: self.view, preferredEdge: NSRectEdge.minY, behavior: NSPopoverBehavior.transient)
			}
		}
	}

	var locale: Language { return self.delegate!.locale }

	func configurableView(_ view: QBEConfigurableViewController, didChangeConfigurationFor c: QBEConfigurable) {
		asyncMain { self.updateView() }
		self.delegate?.sentenceView(self, didChangeConfigurable: c)
	}
}

private extension QBEFormulaEditorViewController {
	func updateContextInformation(_ sentence: QBESentenceFormula) {
		if let getContext = sentence.contextCallback {
			let job = Job(.userInitiated)
			getContext(job) { result in
				switch result {
				case .success(let r):
					asyncMain {
						self.exampleResult = self.expression?.apply(r.row, foreign: nil, inputValue: nil)
						self.columns = OrderedSet<Column>(r.columns.sorted(by: { return $0.name < $1.name }))
					}

				case .failure(_):
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
