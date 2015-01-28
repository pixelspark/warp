import Foundation
import Cocoa

internal class QBECSVConfigurator: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var separatorField: NSComboBox?
	@IBOutlet var hasHeadersButton: NSButton?
	let step: QBECSVSourceStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBECSVSourceStep {
			self.step = s
			super.init(nibName: "QBECSVConfigurator", bundle: nil)
		}
		else {
			super.init(nibName: "QBECSVConfigurator", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		if let s = step {
			separatorField?.stringValue = String(Character(UnicodeScalar(s.fieldSeparator)))
			hasHeadersButton?.state = s.hasHeaders ? NSOnState : NSOffState
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			if let sv = separatorField?.stringValue {
				if !sv.isEmpty {
					s.fieldSeparator = sv.utf16[sv.utf16.startIndex]
				}
			}
			s.hasHeaders = hasHeadersButton?.state == NSOnState
			delegate?.suggestionsView(self, previewStep: s)
		}
	}
}