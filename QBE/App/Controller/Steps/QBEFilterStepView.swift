import Foundation

class QBEFilterStepView: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var formulaField: NSTextField?
	let step: QBEFilterStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBEFilterStep {
			self.step = s
			super.init(nibName: "QBEFilterStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBEFilterStepView", bundle: nil)
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
			self.formulaField?.stringValue = (s.condition?.toFormula(self.delegate?.locale ?? QBELocale(), topLevel: true) ?? "")
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			let oldFormula = s.condition?.toFormula(self.delegate?.locale ?? QBELocale(), topLevel: true) ?? ""
			if let f = self.formulaField?.stringValue {
				if f != oldFormula {
					if let parsed = QBEFormula(formula: f, locale: (self.delegate?.locale ?? QBELocale()))?.root {
						self.formulaField?.stringValue = parsed.toFormula(self.delegate?.locale ?? QBELocale(), topLevel: true)
						s.condition = parsed
					}
					else {
						// TODO this should be a bit more informative
						let a = NSAlert()
						a.messageText = NSLocalizedString("The formula you typed is not valid.", comment: "")
						a.alertStyle = NSAlertStyle.WarningAlertStyle
						a.beginSheetModalForWindow(self.view.window!, completionHandler: nil)
					}
					delegate?.suggestionsView(self, previewStep: s)
				}
			}
		}
	}
}