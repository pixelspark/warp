import Cocoa

protocol QBEFormulaEditorViewDelegate: NSObjectProtocol {
	func formulaEditor(view: QBEFormulaEditorViewController, didChangeExpression: QBEExpression?)
}

class QBEFormulaEditorViewController: NSViewController, QBEReferenceViewDelegate, NSTextFieldDelegate {
	private(set) var expression: QBEExpression? = nil
	private(set) var locale: QBELocale? = nil
	weak var delegate: QBEFormulaEditorViewDelegate? = nil
	@IBOutlet private var formulaField: NSTextField!
	private var lastSelectedRange: NSRange? = nil
	@IBOutlet private var referenceView: NSView!

	func referenceView(view: QBEReferenceViewController, didSelectFunction: QBEFunction) {
		if let locale = self.locale {
			self.view.window?.makeFirstResponder(formulaField)
			if let ed = formulaField.currentEditor() {
				let er = lastSelectedRange ?? ed.selectedRange
				if er.length > 0 {
					ed.selectedRange = er
					let selectedText = NSString(string: ed.string ?? "").substringWithRange(er)
					let replacement: String
					if let f = QBEFormula(formula: selectedText, locale: locale) {
						let wrapped = QBEFunctionExpression(arguments: [f.root], type: didSelectFunction)
						replacement = wrapped.toFormula(locale, topLevel: true)
					}
					else {
						replacement = "\(locale.nameForFunction(didSelectFunction)!)(\(selectedText))"
					}
					ed.replaceCharactersInRange(er, withString: replacement)
					ed.selectedRange = NSMakeRange(er.location, replacement.characters.count)
				}
				else {
					formulaField.stringValue += QBEFunctionExpression(arguments: [], type: didSelectFunction).toFormula(locale, topLevel: false)
				}
			}
			else {
				formulaField.stringValue += QBEFunctionExpression(arguments: [], type: didSelectFunction).toFormula(locale, topLevel: false)
			}
		}
		updateFromView(self.formulaField)
	}

	func startEditingExpression(expression: QBEExpression, locale: QBELocale) {
		self.locale = locale
		self.expression = expression
		updateView(true)
	}

	override func controlTextDidEndEditing(obj: NSNotification) {
		if let r = self.formulaField.currentEditor()?.selectedRange {
			lastSelectedRange = r
		}
	}

	override func controlTextDidChange(obj: NSNotification) {
		updateFromView(self.formulaField)
	}

	private func updateView(force: Bool) {
		if let ff = self.formulaField {
			if let e = expression, let locale = self.locale {
				if let formula = QBEFormula(formula: e.toFormula(locale, topLevel: true), locale: locale) {
					ff.attributedStringValue = formula.syntaxColoredFormula
				}
				else {
					if force {
						ff.stringValue = e.toFormula(locale)
					}
				}
			}
			else {
				if force {
					ff.stringValue = ""
				}
			}
		}
	}
	
	@IBAction func updateFromView(sender: NSObject) {
		if sender == self.formulaField {
			if let r = self.formulaField.currentEditor()?.selectedRange {
				lastSelectedRange = r
			}
		}

		if let formulaText = self.formulaField?.stringValue, let locale = self.locale, let formula = QBEFormula(formula: formulaText, locale: locale) {
			if formula.root != self.expression {
				self.expression = formula.root
				delegate?.formulaEditor(self, didChangeExpression: self.expression)
				updateView(false)
			}
		}
	}

    override func viewDidLoad() {
        super.viewDidLoad()
		updateView(true)
    }

	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier == "showReference" {
			if let dest = segue.destinationController as? QBEReferenceViewController {
				dest.delegate = self
			}
		}
	}
}
