import Foundation
import Cocoa
import WarpCore

internal class QBECalculateStepView: NSViewController, NSComboBoxDataSource, NSComboBoxDelegate {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var targetColumnNameField: NSTextField?
	@IBOutlet var formulaField: NSTextField?
	@IBOutlet var insertAfterField: NSComboBox!
	@IBOutlet var insertPositionPopup: NSPopUpButton!
	var existingColumns: [QBEColumn]?
	let step: QBECalculateStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBECalculateStep {
			self.step = s
			super.init(nibName: "QBECalculateStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBECalculateStepView", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		step = nil
		super.init(coder: coder)
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		if let s = step {
			self.targetColumnNameField?.stringValue = s.targetColumn.name
			updateView()
		}
	}
	
	override func viewWillDisappear() {
		NSNotificationCenter.defaultCenter().removeObserver(self)
		super.viewWillDisappear()
	}
	
	func comboBox(aComboBox: NSComboBox, objectValueForItemAtIndex index: Int) -> AnyObject {
		if let c = existingColumns where index >= 0 && index < c.count {
			return c[index].name
		}
		return ""
	}
	
	func numberOfItemsInComboBox(aComboBox: NSComboBox) -> Int {
		return existingColumns?.count ?? 0
	}
	
	
	private func updateView() {
		QBEAssertMainThread()
		
		if let s = step {
			let job = QBEJob(.UserInitiated)
			self.insertAfterField?.stringValue = s.insertRelativeTo?.name ?? ""
			self.insertPositionPopup.selectItemWithTag(s.insertBefore ? 1 : 0)
			self.existingColumns = nil
			
			s.exampleData(job, maxInputRows: 100, maxOutputRows: 100) { (data) in
				switch data {
					case .Success(let d):
						d.columnNames(job) {(cns) in
							switch cns {
								case .Success(let e):
									self.existingColumns = e
								
								case .Failure(_):
									// Error is ignored
									self.existingColumns = nil
									break;
							}
							
							QBEAsyncMain {
								self.insertAfterField?.reloadData()
							}
						}
				
					case .Failure(_):
						break
				}
			}
		
			let f = s.function.toFormula(self.delegate?.locale ?? QBELocale(), topLevel: true)
			let fullFormula = f
			if let parsed = QBEFormula(formula: fullFormula, locale: (self.delegate?.locale ?? QBELocale())) {
				self.formulaField?.attributedStringValue = parsed.syntaxColoredFormula
			}
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			if sender == insertPositionPopup {
				if let position = insertPositionPopup.selectedItem {
					let before = position.tag == 1
					if s.insertBefore != before {
						s.insertBefore = before
						delegate?.suggestionsView(self, previewStep: s)
						return
					}
				}
			}
			
			if sender == insertAfterField {
				let after = insertAfterField.stringValue
				if after != s.insertRelativeTo?.name {
					s.insertRelativeTo = after.isEmpty ? nil : QBEColumn(after)
				}
				delegate?.suggestionsView(self, previewStep: s)
				return
			}
			
			s.targetColumn = QBEColumn(self.targetColumnNameField?.stringValue ?? s.targetColumn.name)
			if let f = self.formulaField?.stringValue {
				if let parsed = QBEFormula(formula: f, locale: (self.delegate?.locale ?? QBELocale())) {
					s.function = parsed.root
					updateView()
				}
				else {
					// TODO: this should be a bit more informative
					let a = NSAlert()
					a.messageText = NSLocalizedString("The formula you typed is not valid.", comment: "")
					a.alertStyle = NSAlertStyle.WarningAlertStyle
					a.beginSheetModalForWindow(self.view.window!, completionHandler: nil)
				}
			}
			delegate?.suggestionsView(self, previewStep: s)
		}
	}
}