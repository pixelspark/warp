import Foundation
import Cocoa

internal class QBECSVConfigurator: NSViewController, NSComboBoxDataSource {
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
			self.step = nil
			super.init(nibName: "QBECSVConfigurator", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		self.step = nil
		super.init(coder: coder)
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		if let s = step {
			separatorField?.stringValue = String(Character(UnicodeScalar(s.fieldSeparator)))
			hasHeadersButton?.state = s.hasHeaders ? NSOnState : NSOffState
		}
	}
	
	func numberOfItemsInComboBox(aComboBox: NSComboBox) -> Int {
		if let locale = self.delegate?.locale {
			return locale.commonFieldSeparators.count
		}
		return 0
	}
	
	func comboBox(aComboBox: NSComboBox, objectValueForItemAtIndex index: Int) -> AnyObject {
		if let locale = self.delegate?.locale {
			return locale.commonFieldSeparators[index]
		}
		return ""
	}
	
	@IBAction func update(sender: NSObject) {
		var changed = false
		
		if let s = step {
			if let sv = separatorField?.stringValue {
				if !sv.isEmpty {
					let separator = sv.utf16[sv.utf16.startIndex]
					if s.fieldSeparator != separator {
						s.fieldSeparator = separator
						changed = true
					}
				}
			}
			
			let shouldHaveHeaders = (hasHeadersButton?.state == NSOnState)
			if s.hasHeaders != shouldHaveHeaders {
				s.hasHeaders = shouldHaveHeaders
				changed = true
			}
			
			if changed {
				delegate?.suggestionsView(self, previewStep: s)
			}
		}
	}
}