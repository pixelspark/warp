import Foundation
import Cocoa
import WarpCore

internal class QBECSVStepView: QBEStepViewControllerFor<QBECSVSourceStep>, NSComboBoxDataSource {
	@IBOutlet var separatorField: NSComboBox?
	@IBOutlet var hasHeadersButton: NSButton?
	@IBOutlet var languageField: NSComboBox!
	@IBOutlet var languageLabel: NSTextField!

	private let languages: [Locale.LanguageIdentifier]

	required init?(step: QBEStep, delegate: QBEStepViewDelegate) {
		languages = Array(Locale.languages.keys)
		super.init(step: step, delegate: delegate, nibName: "QBECSVStepView", bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("Should not be called")
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		updateView()
	}
	
	func numberOfItemsInComboBox(aComboBox: NSComboBox) -> Int {
		if aComboBox == separatorField {
			if let locale = self.delegate?.locale {
				return locale.commonFieldSeparators.count
			}
		}
		else if aComboBox == languageField {
			return languages.count + 1
		}
		return 0
	}
	
	func comboBox(aComboBox: NSComboBox, objectValueForItemAtIndex index: Int) -> AnyObject {
		if aComboBox == self.separatorField {
			if let locale = self.delegate?.locale {
				return locale.commonFieldSeparators[index]
			}
		}
		else if aComboBox == self.languageField {
			if index == 0 {
				return NSLocalizedString("Standard language", comment: "")
			}
			else {
				let langId = self.languages[index-1]
				return Locale.languages[langId] ?? ""
			}
		}
		return ""
	}

	private func updateView() {
		separatorField?.stringValue = String(Character(UnicodeScalar(step.fieldSeparator)))
		hasHeadersButton?.state = step.hasHeaders ? NSOnState : NSOffState
		languageField.selectItemAtIndex((self.languages.indexOf(step.interpretLanguage ?? "") ?? -1) + 1)
		
		let testValue = Value.DoubleValue(1110819.88)
		if let language = step.interpretLanguage {
			let locale = Locale(language: language)
			languageLabel.stringValue = String(format: NSLocalizedString("In this language, numbers look like this: %@ (numbers without thousand separators will also be accepted)", comment: ""), locale.localStringFor(testValue))
		}
		else {
			languageLabel.stringValue = String(format: NSLocalizedString("In this language, numbers look like this: %@", comment: ""), Locale.stringForExchangedValue(testValue))
		}
	}
	
	@IBAction func update(sender: NSObject) {
		var changed = false

		if let sv = separatorField?.stringValue {
			if !sv.isEmpty {
				let separator = sv.utf16[sv.utf16.startIndex]
				if step.fieldSeparator != separator {
					step.fieldSeparator = separator
					changed = true
				}
			}
		}
		
		// Interpretation language
		let languageSelection = self.languageField.indexOfSelectedItem
		let languageID: Locale.LanguageIdentifier?
		if languageSelection <= 0 {
			languageID = nil
		}
		else {
			languageID = self.languages[languageSelection - 1]
		}
		
		if step.interpretLanguage != languageID {
			step.interpretLanguage = languageID
			changed = true
		}
		
		// Headers
		let shouldHaveHeaders = (hasHeadersButton?.state == NSOnState)
		if step.hasHeaders != shouldHaveHeaders {
			step.hasHeaders = shouldHaveHeaders
			changed = true
		}
		
		if changed {
			delegate?.stepView(self, didChangeConfigurationForStep: step)
		}
		
		updateView()
	}
}