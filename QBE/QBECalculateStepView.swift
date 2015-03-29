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
			updateView()
		}
	}
	
	private func updateView() {
		if let f = step?.function.toFormula(self.delegate?.locale ?? QBELocale()) {
			let fullFormula = "="+f
			if let parsed = QBEFormula(formula: fullFormula, locale: (self.delegate?.locale ?? QBELocale())) {
				let ma = NSMutableAttributedString(string: fullFormula, attributes: [
					NSForegroundColorAttributeName: NSColor.blackColor(),
					NSFontAttributeName: NSFont.systemFontOfSize(13)
				])
				
				for fragment in parsed.fragments.sorted({return $0.length > $1.length}) {
					if let literal = fragment.expression as? QBELiteralExpression {
						ma.addAttributes([NSForegroundColorAttributeName: NSColor.blueColor()], range: NSMakeRange(fragment.start, fragment.length))
					}
					else if let literal = fragment.expression as? QBESiblingExpression {
						ma.addAttributes([NSForegroundColorAttributeName: NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)], range: NSMakeRange(fragment.start, fragment.length))
					}
					else if let literal = fragment.expression as? QBEIdentityExpression {
						ma.addAttributes([NSForegroundColorAttributeName: NSColor(red: 0.8, green: 0.5, blue: 0.0, alpha: 1.0)], range: NSMakeRange(fragment.start, fragment.length))
					}
				}
			
				self.formulaField?.attributedStringValue = ma
			}
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
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