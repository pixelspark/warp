/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

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

class QBESettingsViewController: NSViewController, NSComboBoxDataSource {
	@IBOutlet var separatorBox: NSComboBox?
	@IBOutlet var localeBox: NSComboBox?
	@IBOutlet var exampleRowsSlider: NSSlider?
	@IBOutlet var exampleTimeSlider: NSSlider?
	@IBOutlet var exampleRowsLabel: NSTextField?
	@IBOutlet var exampleTimeLabel: NSTextField?
	
	var locale: Language! { get {
		return QBEAppDelegate.sharedInstance.locale
	} }
	
	override func viewWillAppear() {
		assert(locale != nil, "Language needs to be set before presenting settings view controller")
		self.view.window?.titlebarAppearsTransparent = true
		updateView()
	}
	
	private func updateView() {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.usesSignificantDigits = false
		formatter.minimumFractionDigits = 1
		formatter.maximumFractionDigits = 1
		
		self.exampleRowsSlider?.integerValue = QBESettings.sharedInstance.exampleMaximumRows
		self.exampleTimeSlider?.doubleValue = QBESettings.sharedInstance.exampleMaximumTime
		self.exampleRowsLabel?.integerValue = QBESettings.sharedInstance.exampleMaximumRows
		self.exampleTimeLabel?.stringValue = formatter.string(from: NSNumber(value: QBESettings.sharedInstance.exampleMaximumTime)) ?? ""
		
		if let language = UserDefaults.standard.string(forKey: "locale") {
			if let name = Language.languages[language] {
				self.localeBox?.stringValue = name
			}
		}
	}
	
	@IBAction func resetOnces(_ sender: NSObject) {
		QBESettings.sharedInstance.resetOnces()
	}
	
	@IBAction func valuesChanged(_ sender: NSObject) {
		if let mr = self.exampleRowsSlider?.integerValue {
			QBESettings.sharedInstance.exampleMaximumRows = mr
		}
		
		if let ms = self.exampleTimeSlider?.doubleValue {
			QBESettings.sharedInstance.exampleMaximumTime = ms
		}
		
		let langs = [String](Language.languages.keys)
		if let index = self.localeBox?.indexOfSelectedItem, index >= 0 {
			UserDefaults.standard.set(langs[index], forKey: "locale")
		}
		
		updateView()
	}
	
	func comboBox(_ aComboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
		if aComboBox == separatorBox {
			return locale.commonFieldSeparators[index]
		}
		else if aComboBox == localeBox {
			let langs = [String](Language.languages.values)
			return langs[index]
		}
		
		return ""
	}
	
	func numberOfItems(in aComboBox: NSComboBox) -> Int {
		if aComboBox == separatorBox {
			return locale.commonFieldSeparators.count
		}
		else if aComboBox == localeBox {
			return Language.languages.count
		}
		return 0
	}
}
