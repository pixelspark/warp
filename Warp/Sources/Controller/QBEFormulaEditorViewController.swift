import Cocoa
import WarpCore

protocol QBEFormulaEditorViewDelegate: NSObjectProtocol {
	func formulaEditor(view: QBEFormulaEditorViewController, didChangeExpression: Expression?)
}

class QBEFormulaEditorViewController: NSViewController, QBEReferenceViewDelegate, NSTextFieldDelegate {
	private(set) var expression: Expression? = nil
	private(set) var locale: Locale? = nil
	weak var delegate: QBEFormulaEditorViewDelegate? = nil
	@IBOutlet private var formulaField: NSTextField!
	private var lastSelectedRange: NSRange? = nil
	@IBOutlet private var referenceView: NSView!

	private var syntaxColoringJob: Job? = nil

	func referenceView(view: QBEReferenceViewController, didSelectFunction: Function) {
		if let locale = self.locale {
			self.view.window?.makeFirstResponder(formulaField)
			if let ed = formulaField.currentEditor() {
				let er = lastSelectedRange ?? ed.selectedRange
				if er.length > 0 {
					ed.selectedRange = er
					let selectedText = NSString(string: ed.string ?? "").substringWithRange(er)
					let replacement: String
					if let f = Formula(formula: selectedText, locale: locale) {
						let wrapped = Call(arguments: [f.root], type: didSelectFunction)
						replacement = wrapped.toFormula(locale, topLevel: true)
					}
					else {
						replacement = "\(locale.nameForFunction(didSelectFunction)!)(\(selectedText))"
					}
					ed.replaceCharactersInRange(er, withString: replacement)
					ed.selectedRange = NSMakeRange(er.location, replacement.characters.count)
				}
				else {
					formulaField.stringValue += Call(arguments: [], type: didSelectFunction).toFormula(locale, topLevel: false)
				}
			}
			else {
				formulaField.stringValue += Call(arguments: [], type: didSelectFunction).toFormula(locale, topLevel: false)
			}
		}
		updateFromView(self.formulaField)
	}

	func startEditingExpression(expression: Expression, locale: Locale) {
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
				let job = Job(.UserInitiated)
				self.syntaxColoringJob?.cancel()
				self.syntaxColoringJob = job
				job.async {
					// Parse the formula to get coloring information. This can take a while, so do it in the background
					if let formula = Formula(formula: e.toFormula(locale, topLevel: true), locale: locale) {
						if !job.cancelled {
							asyncMain {
								ff.attributedStringValue = formula.syntaxColoredFormula
							}
						}
					}
				}
				if force {
					ff.stringValue = e.toFormula(locale)
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

		if let formulaText = self.formulaField?.stringValue, let locale = self.locale {
			self.syntaxColoringJob?.cancel()

			let job = Job(.UserInitiated)
			self.syntaxColoringJob = job
			job.async {
				if let formula = Formula(formula: formulaText, locale: locale) where formula.root != self.expression {
					if !job.cancelled {
						asyncMain {
							self.expression = formula.root
							self.delegate?.formulaEditor(self, didChangeExpression: self.expression)
							self.updateView(false)
						}
					}
				}
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
