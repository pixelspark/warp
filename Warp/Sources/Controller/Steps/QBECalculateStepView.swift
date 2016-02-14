import Foundation
import Cocoa
import WarpCore

internal class QBECalculateStepView: QBEConfigurableStepViewControllerFor<QBECalculateStep>, NSComboBoxDataSource, NSComboBoxDelegate {
	@IBOutlet var targetColumnNameField: NSTextField?
	@IBOutlet var formulaField: NSTextField?
	@IBOutlet var insertAfterField: NSComboBox!
	@IBOutlet var insertPositionPopup: NSPopUpButton!
	var existingColumns: [Column]?
	
	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBECalculateStepView", bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("Cannot load from coder")
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		self.targetColumnNameField?.stringValue = step.targetColumn.name
		updateView()
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
		assertMainThread()

		let job = Job(.UserInitiated)
		self.insertAfterField?.stringValue = step.insertRelativeTo?.name ?? ""
		self.insertPositionPopup.selectItemWithTag(step.insertBefore ? 1 : 0)
		self.existingColumns = nil
		
		step.exampleData(job, maxInputRows: 100, maxOutputRows: 100) { (data) in
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
						
						asyncMain {
							self.insertAfterField?.reloadData()
						}
					}
			
				case .Failure(_):
					break
			}
		}
	
		let f = step.function.toFormula(self.delegate?.locale ?? Locale(), topLevel: true)
		let fullFormula = f
		if let parsed = Formula(formula: fullFormula, locale: (self.delegate?.locale ?? Locale())) {
			self.formulaField?.attributedStringValue = parsed.syntaxColoredFormula
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if sender == insertPositionPopup {
			if let position = insertPositionPopup.selectedItem {
				let before = position.tag == 1
				if step.insertBefore != before {
					step.insertBefore = before
					delegate?.configurableView(self, didChangeConfigurationFor: step)
					return
				}
			}
		}
		
		if sender == insertAfterField {
			let after = insertAfterField.stringValue
			if after != step.insertRelativeTo?.name {
				step.insertRelativeTo = after.isEmpty ? nil : Column(after)
			}
			delegate?.configurableView(self, didChangeConfigurationFor: step)
			return
		}
		
		step.targetColumn = Column(self.targetColumnNameField?.stringValue ?? step.targetColumn.name)
		if let f = self.formulaField?.stringValue {
			if let parsed = Formula(formula: f, locale: (self.delegate?.locale ?? Locale())) {
				step.function = parsed.root
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
		delegate?.configurableView(self, didChangeConfigurationFor: step)
	}
}