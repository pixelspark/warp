import Foundation
import Cocoa
import WarpCore

internal class QBECSVStepView: NSViewController, NSComboBoxDataSource {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var separatorField: NSComboBox?
	@IBOutlet var hasHeadersButton: NSButton?
	@IBOutlet var languageField: NSComboBox!
	@IBOutlet var languageLabel: NSTextField!
	
	let step: QBECSVSourceStep?
	private let languages: [QBELocale.QBELanguage]
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		languages = Array(QBELocale.languages.keys)
		
		if let s = step as? QBECSVSourceStep {
			self.step = s
			super.init(nibName: "QBECSVStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBECSVStepView", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		self.step = nil
		languages = Array(QBELocale.languages.keys)
		super.init(coder: coder)
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
				return QBELocale.languages[langId] ?? ""
			}
		}
		return ""
	}

	private func updateView() {
		if let s = step {
			separatorField?.stringValue = String(Character(UnicodeScalar(s.fieldSeparator)))
			hasHeadersButton?.state = s.hasHeaders ? NSOnState : NSOffState
			languageField.selectItemAtIndex((self.languages.indexOf(s.interpretLanguage ?? "") ?? -1) + 1)
			
			let testValue = QBEValue.DoubleValue(1110819.88)
			if let language = s.interpretLanguage {
				let locale = QBELocale(language: language)
				languageLabel.stringValue = String(format: NSLocalizedString("In this language, numbers look like this: %@ (numbers without thousand separators will also be accepted)", comment: ""), locale.localStringFor(testValue))
			}
			else {
				languageLabel.stringValue = String(format: NSLocalizedString("In this language, numbers look like this: %@", comment: ""), QBELocale.stringForExchangedValue(testValue))
			}
		}
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
			
			// Interpretation language
			let languageSelection = self.languageField.indexOfSelectedItem
			let languageID: QBELocale.QBELanguage?
			if languageSelection <= 0 {
				languageID = nil
			}
			else {
				languageID = self.languages[languageSelection - 1]
			}
			
			if s.interpretLanguage != languageID {
				s.interpretLanguage = languageID
				changed = true
			}
			
			// Headers
			let shouldHaveHeaders = (hasHeadersButton?.state == NSOnState)
			if s.hasHeaders != shouldHaveHeaders {
				s.hasHeaders = shouldHaveHeaders
				changed = true
			}
			
			if changed {
				delegate?.suggestionsView(self, previewStep: s)
			}
		}
		
		updateView()
	}
}