import Foundation

class QBEFlattenStepView: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var rowIdentifierField: NSTextField?
	@IBOutlet var rowColumnField: NSTextField?
	@IBOutlet var columnColumnField: NSTextField?
	@IBOutlet var valueColumnField: NSTextField?
	
	let step: QBEFlattenStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBEFlattenStep {
			self.step = s
			super.init(nibName: "QBEFlattenStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBEFlattenStepView", bundle: nil)
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
			if let ri = s.rowIdentifier {
				self.rowIdentifierField?.stringValue = "=" + (ri.toFormula(self.delegate?.locale ?? QBEDefaultLocale()) ?? "")
			}
			else {
				self.rowIdentifierField?.stringValue = ""
			}
			self.valueColumnField?.stringValue = s.valueColumn.name
			self.rowColumnField?.stringValue = s.rowColumn?.name ?? ""
			self.columnColumnField?.stringValue = s.colColumn?.name ?? ""
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			var changed = false
			
			if let newRowColumn = self.rowColumnField?.stringValue {
				if newRowColumn != s.rowColumn?.name {
					s.rowColumn = newRowColumn.isEmpty ? nil : QBEColumn(newRowColumn)
					changed = true
				}
			}
			
			if let newColColumn = self.columnColumnField?.stringValue {
				if newColColumn != s.colColumn?.name {
					s.colColumn = newColColumn.isEmpty ? nil : QBEColumn(newColColumn)
					changed = true
				}
			}
			
			if let newValueColumn = self.valueColumnField?.stringValue {
				if newValueColumn != s.valueColumn.name {
					s.valueColumn = QBEColumn(newValueColumn)
					changed = true
				}
			}
			
			let oldFormula = "=" + (s.rowIdentifier?.toFormula(self.delegate?.locale ?? QBEDefaultLocale()) ?? "");
			if let f = self.rowIdentifierField?.stringValue {
				if f != oldFormula {
					if let parsed = QBEFormula(formula: f, locale: (self.delegate?.locale ?? QBEDefaultLocale()))?.root {
						self.rowIdentifierField?.stringValue = "="+parsed.toFormula(self.delegate?.locale ?? QBEDefaultLocale())
						s.rowIdentifier = parsed
					}
					else {
						// TODO parsing error
					}
					changed = true
				}
			}
			
			if changed {
				delegate?.suggestionsView(self, previewStep: nil)
			}
		}
	}
}