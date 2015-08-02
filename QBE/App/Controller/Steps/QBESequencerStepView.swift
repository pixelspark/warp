import Foundation
import Cocoa

internal class QBESequencerStepView: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var targetColumnNameField: NSTextField?
	@IBOutlet var formulaField: NSTextField?
	@IBOutlet var exampleField: NSTextField?
	@IBOutlet var cardinalityField: NSTextField?
	
	var existingColumns: [QBEColumn]?
	let step: QBESequencerStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBESequencerStep {
			self.step = s
			super.init(nibName: "QBESequencerStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBESequencerStepView", bundle: nil)
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
			self.targetColumnNameField?.stringValue = s.column.name
			updateView()
		}
	}
	
	private func updateView() {
		QBEAssertMainThread()
		
		if let s = step {
			// TODO: add syntax coloring
			self.formulaField?.stringValue = s.pattern
			
			if let sequencer = QBESequencer(s.pattern) {
				exampleField?.stringValue = sequencer.randomValue?.stringValue ?? ""
				cardinalityField?.stringValue = delegate?.locale.localStringFor(QBEValue.IntValue(sequencer.cardinality)) ?? ""
			}
			else {
				exampleField?.stringValue = ""
				cardinalityField?.stringValue = ""
			}
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			var changed = false
			if let newTarget = self.targetColumnNameField?.stringValue where newTarget != s.column.name {
				s.column = QBEColumn(newTarget)
				changed = true
			}
			
			if let f = self.formulaField?.stringValue {
				if let _ = QBESequencer(f) {
					s.pattern = f
					changed = true
					updateView()
				}
				else {
					exampleField?.stringValue = ""
					
					// TODO: this should be a bit more informative
					let a = NSAlert()
					a.messageText = NSLocalizedString("The pattern you typed is not valid.", comment: "")
					a.alertStyle = NSAlertStyle.WarningAlertStyle
					a.beginSheetModalForWindow(self.view.window!, completionHandler: nil)
				}
			}
			
			if changed {
				delegate?.suggestionsView(self, previewStep: s)
			}
		}
	}
}