import Foundation
import Cocoa
import WarpCore

internal class QBECalculateStepView: QBEConfigurableStepViewControllerFor<QBECalculateStep>, NSComboBoxDataSource, NSComboBoxDelegate {
	@IBOutlet var targetColumnNameField: NSTextField?
	@IBOutlet var formulaField: NSTextField?
	@IBOutlet var insertAfterField: NSComboBox!
	@IBOutlet var insertPositionPopup: NSPopUpButton!
	var existingColumns: OrderedSet<Column>?
	
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
		NotificationCenter.default.removeObserver(self)
		super.viewWillDisappear()
	}
	
	func comboBox(_ aComboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
		if let c = existingColumns, index >= 0 && index < c.count {
			return c[index].name
		}
		return ""
	}
	
	func numberOfItems(in aComboBox: NSComboBox) -> Int {
		return existingColumns?.count ?? 0
	}
	
	
	private func updateView() {
		assertMainThread()

		let job = Job(.userInitiated)
		self.insertAfterField?.stringValue = step.insertRelativeTo?.name ?? ""
		self.insertPositionPopup.selectItem(withTag: step.insertBefore ? 1 : 0)
		self.existingColumns = nil
		
		step.exampleDataset(job, maxInputRows: 100, maxOutputRows: 100) { (data) in
			switch data {
				case .success(let d):
					d.columns(job) {(cns) in
						switch cns {
							case .success(let e):
								self.existingColumns = e
							
							case .failure(_):
								// Error is ignored
								self.existingColumns = nil
								break;
						}
						
						asyncMain {
							self.insertAfterField?.reloadData()
						}
					}
			
				case .failure(_):
					break
			}
		}
	
		let f = step.function.toFormula(self.delegate?.locale ?? Language(), topLevel: true)
		let fullFormula = f
		if let parsed = Formula(formula: fullFormula, locale: (self.delegate?.locale ?? Language())) {
			self.formulaField?.attributedStringValue = parsed.syntaxColoredFormula
		}
	}
	
	@IBAction func update(_ sender: NSObject) {
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
			if let parsed = Formula(formula: f, locale: (self.delegate?.locale ?? Language())) {
				step.function = parsed.root
				updateView()
			}
			else {
				// TODO: this should be a bit more informative
				let a = NSAlert()
				a.messageText = NSLocalizedString("The formula you typed is not valid.", comment: "")
				a.alertStyle = NSAlertStyle.warning
				a.beginSheetModal(for: self.view.window!, completionHandler: nil)
			}
		}
		delegate?.configurableView(self, didChangeConfigurationFor: step)
	}
}
