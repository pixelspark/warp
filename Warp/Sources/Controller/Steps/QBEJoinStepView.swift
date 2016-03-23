import Foundation
import WarpCore

class QBEJoinStepView: QBEConfigurableStepViewControllerFor<QBEJoinStep> {
	@IBOutlet var formulaField: NSTextField?

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBEJoinStepView", bundle: nil)
	}
	
	func tabView(tabView: NSTabView, didSelectTabViewItem tabViewItem: NSTabViewItem?) {
		updateView()
	}
	
	required init?(coder: NSCoder) {
		fatalError("Should not be called")
	}

	internal override func viewWillAppear() {
		super.viewWillAppear()
		self.formulaField?.stringValue = (step.condition?.toFormula(self.delegate?.locale ?? Locale(), topLevel: true) ?? "")
		updateView()
	}
	
	private func updateView() {
		if let f = step.condition {
			let formula = f.toFormula(self.delegate?.locale ?? Locale(), topLevel: true)
			if let parsed = Formula(formula: formula, locale: self.delegate?.locale ?? Locale()) {
				self.formulaField?.attributedStringValue = parsed.syntaxColoredFormula
			}
		}
	}
	
	@IBAction func updateFromComplexView(sender: NSObject) {
		// Set formula
		let oldFormula = step.condition?.toFormula(self.delegate?.locale ?? Locale(), topLevel: true) ?? ""
		if let f = self.formulaField?.stringValue {
			if f != oldFormula {
				if let parsed = Formula(formula: f, locale: (self.delegate?.locale ?? Locale()))?.root {
					step.condition = parsed
					delegate?.configurableView(self, didChangeConfigurationFor: step)
					updateView()
				}
				else {
					// TODO this should be a bit more informative
					let a = NSAlert()
					a.messageText = NSLocalizedString("The formula you typed is not valid.", comment: "")
					a.alertStyle = NSAlertStyle.WarningAlertStyle
					a.beginSheetModalForWindow(self.view.window!, completionHandler: nil)
				}
			}
		}
	}
	
	override func viewWillDisappear() {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}
}