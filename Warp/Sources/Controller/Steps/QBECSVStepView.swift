/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import Cocoa
import WarpCore

internal class QBECSVStepView: QBEConfigurableStepViewControllerFor<QBECSVSourceStep>, NSComboBoxDataSource {
	@IBOutlet var separatorField: NSComboBox?
	@IBOutlet var hasHeadersButton: NSButton?
	@IBOutlet var languageField: NSComboBox!
	@IBOutlet var languageLabel: NSTextField!

	private let languages: [Language.LanguageIdentifier]

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		languages = Array(Language.languages.keys)
		super.init(configurable: configurable, delegate: delegate, nibName: "QBECSVStepView", bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("Should not be called")
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		updateView()
	}
	
	func numberOfItems(in aComboBox: NSComboBox) -> Int {
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
	
	func comboBox(_ aComboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
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
				return Language.languages[langId] ?? ""
			}
		}
		return ""
	}

	private func updateView() {
		separatorField?.stringValue = String(Character(UnicodeScalar(step.fieldSeparator)!))
		hasHeadersButton?.state = step.hasHeaders ? NSOnState : NSOffState
		languageField.selectItem(at: (self.languages.index(of: step.interpretLanguage ?? "") ?? -1) + 1)
		
		let testValue = Value.double(1110819.88)
		if let language = step.interpretLanguage {
			let locale = Language(language: language)
			languageLabel.stringValue = String(format: NSLocalizedString("In this language, numbers look like this: %@ (numbers without thousand separators will also be accepted)", comment: ""), locale.localStringFor(testValue))
		}
		else {
			languageLabel.stringValue = String(format: NSLocalizedString("In this language, numbers look like this: %@", comment: ""), Language.stringForExchangedValue(testValue))
		}
	}
	
	@IBAction func update(_ sender: NSObject) {
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
		let languageID: Language.LanguageIdentifier?
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
			delegate?.configurableView(self, didChangeConfigurationFor: step)
		}
		
		updateView()
	}
}
