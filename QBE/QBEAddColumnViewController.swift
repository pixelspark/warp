import Foundation
import Cocoa

class QBEAddColumnViewController: NSViewController {
	@IBOutlet var columnNameField: NSTextField?
	@IBOutlet var columnFormulaField: NSTextField?
	weak var delegate: QBESuggestionsViewDelegate!
	
	dynamic var columnName: String?
	dynamic var columnFormula: String?
	
	@IBAction func confirm(sender: NSObject) {
		if let targetColumn = columnName {
			if let formula = QBEFormula(formula: "=" + (columnFormula ?? ""), locale: QBEDefaultLocale()) {
				let exp = "\(targetColumn) = \(formula.root.toFormula(delegate!.locale))"
				let cs = QBECalculateStep(previous: delegate?.currentStep, explanation: exp, targetColumn: QBEColumn(columnName ?? ""), function: formula.root)
				delegate?.suggestionsView(self, didSelectStep: cs)
				self.dismissController(sender)
			}
		}
	}
	
	@IBAction func cancel(sender: NSObject) {
		self.dismissController(sender)
	}
}