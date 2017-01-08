/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Cocoa
import WarpCore

protocol QBEFormulaEditorViewDelegate: NSObjectProtocol {
	func formulaEditor(_ view: QBEFormulaEditorViewController, didChangeExpression: Expression?)
}

class QBEFormulaEditorViewController: NSViewController, QBEReferenceViewDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
	weak var delegate: QBEFormulaEditorViewDelegate? = nil
	var exampleResult: Value? = nil { didSet { assertMainThread(); self.updateView(false) } }
	var columns: OrderedSet<Column> = [] { didSet { assertMainThread(); self.updateView(false) } }

	private(set) var expression: Expression? = nil
	private(set) var locale: Language? = nil
	private var lastSelectedRange: NSRange? = nil
	private var syntaxColoringJob: Job? = nil

	@IBOutlet private var formulaField: NSTextField!
	@IBOutlet private var referenceView: NSView!
	@IBOutlet private var exampleOutputField: NSTextField!
	@IBOutlet private var columnsTableView: NSTableView!
	@IBOutlet private var assistantTabView: NSTabView!

	func referenceView(_ view: QBEReferenceViewController, didSelectFunction: Function) {
		if let locale = self.locale {
			self.view.window?.makeFirstResponder(formulaField)
			if let ed = formulaField.currentEditor() {
				let er = lastSelectedRange ?? ed.selectedRange
				if er.length > 0 {
					ed.selectedRange = er
					let selectedText = NSString(string: ed.string ?? "").substring(with: er)
					let replacement: String
					if let f = Formula(formula: selectedText, locale: locale) {
						let wrapped = Call(arguments: [f.root], type: didSelectFunction)
						replacement = wrapped.toFormula(locale, topLevel: true)
					}
					else {
						replacement = "\(locale.nameForFunction(didSelectFunction)!)(\(selectedText))"
					}
					ed.replaceCharacters(in: er, with: replacement)
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

	func startEditingExpression(_ expression: Expression, locale: Language) {
		self.locale = locale
		self.expression = expression
		updateView(true)
	}

	override func controlTextDidEndEditing(_ obj: Notification) {
		if let r = self.formulaField.currentEditor()?.selectedRange {
			lastSelectedRange = r
		}
	}

	override func controlTextDidChange(_ obj: Notification) {
		updateFromView(self.formulaField)
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		if tableView == self.columnsTableView {
			return self.columns.count
		}

		return 0
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		if tableView == self.columnsTableView && tableColumn?.identifier == "column" && row < self.columns.count {
			return self.columns[row].name
		}

		return nil
	}

	private func updateView(_ force: Bool) {
		if let v = self.exampleResult {
			self.exampleOutputField?.stringValue = self.locale?.localStringFor(v) ?? ""
		}
		else {
			self.exampleOutputField?.stringValue = ""
		}

		self.columnsTableView?.reloadData()

		if let ff = self.formulaField {
			if let e = expression, let locale = self.locale {
				let job = Job(.userInitiated)
				self.syntaxColoringJob?.cancel()
				self.syntaxColoringJob = job
				job.async {
					// Parse the formula to get coloring information. This can take a while, so do it in the background
					if let formula = Formula(formula: e.toFormula(locale, topLevel: true), locale: locale) {
						if !job.isCancelled {
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
	
	@IBAction func updateFromView(_ sender: NSObject) {
		if sender == self.formulaField {
			if let r = self.formulaField.currentEditor()?.selectedRange {
				lastSelectedRange = r
			}
		}

		if let formulaText = self.formulaField?.stringValue, let locale = self.locale {
			self.syntaxColoringJob?.cancel()

			let job = Job(.userInitiated)
			self.syntaxColoringJob = job
			job.async {
				if let formula = Formula(formula: formulaText, locale: locale), formula.root != self.expression {
					if !job.isCancelled {
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

	@IBAction func insertColumnFromList(_ sender: NSObject) {
		if let s = self.columnsTableView?.selectedRow, s != NSNotFound && s >= 0 && s < self.columns.count {
			if let locale = self.locale {
				let column = self.columns[s]
				let replacement = Sibling(column).toFormula(locale, topLevel: true)

				self.view.window?.makeFirstResponder(formulaField)
				if let ed = formulaField.currentEditor() {
					let er = lastSelectedRange ?? ed.selectedRange
					if er.length > 0 {
						ed.selectedRange = er
						ed.replaceCharacters(in: er, with: replacement)
						ed.selectedRange = NSMakeRange(er.location, replacement.characters.count)
					}
					else {
						if self.expression is Sibling || self.expression == nil {
							formulaField.stringValue = replacement
						}
						else {
							formulaField.stringValue += replacement
						}
					}
				}
				else {
					formulaField.stringValue += replacement
				}
			}
			updateFromView(self.formulaField)
		}
	}

    override func viewDidLoad() {
        super.viewDidLoad()
		updateView(true)
    }

	override func viewWillAppear() {
		if self.expression is Sibling {
			self.assistantTabView?.selectTabViewItem(withIdentifier: "columns")
		}
		else {
			self.assistantTabView?.selectTabViewItem(withIdentifier: "result")
		}
	}

	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		if segue.identifier == "showReference" {
			if let dest = segue.destinationController as? QBEReferenceViewController {
				dest.delegate = self
			}
		}
	}
}
