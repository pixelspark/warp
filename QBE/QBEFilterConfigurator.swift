import Foundation

class QBEFilterConfigurator: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var formulaField: NSTextField?
	let step: QBEFilterStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBEFilterStep {
			self.step = s
			super.init(nibName: "QBEFilterConfigurator", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBEFilterConfigurator", bundle: nil)
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
			self.formulaField?.stringValue = "=" + (s.condition?.toFormula(self.delegate?.locale ?? QBEDefaultLocale()) ?? "")
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			if let f = self.formulaField?.stringValue {
				if let parsed = QBEFormula(formula: f, locale: (self.delegate?.locale ?? QBEDefaultLocale()))?.root {
					s.condition = parsed
				}
				else {
					// TODO parsing error
				}
			}
			delegate?.suggestionsView(self, previewStep: s)
		}
	}
}