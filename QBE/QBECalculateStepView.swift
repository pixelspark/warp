import Foundation
import Cocoa

internal class QBECalculateStepView: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var targetColumnNameField: NSTextField?
	@IBOutlet var formulaField: NSTextField?
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
			self.formulaField?.stringValue = "=" + s.function.toFormula(self.delegate?.locale ?? QBEDefaultLocale())
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			s.targetColumn = QBEColumn(self.targetColumnNameField?.stringValue ?? s.targetColumn.name)
			if let f = self.formulaField?.stringValue {
				if let parsed = QBEFormula(formula: f, locale: (self.delegate?.locale ?? QBEDefaultLocale()))?.root {
					s.function = parsed
				}
				else {
					// TODO parsing error
				}
			}
			delegate?.suggestionsView(self, previewStep: s)
		}
	}
}