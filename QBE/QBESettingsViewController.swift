import Foundation
import Cocoa

class QBESettingsViewController: NSViewController, NSComboBoxDataSource {
	@IBOutlet var separatorBox: NSComboBox?
	@IBOutlet var localeBox: NSComboBox?
	
	var locale: QBELocale! { get {
		return QBEAppDelegate.sharedInstance.locale
	} }
	
	override func viewWillAppear() {
		assert(locale != nil, "Locale needs to be set before presenting settings view controller")
		if let language = NSUserDefaults.standardUserDefaults().stringForKey("locale") {
			if let name = QBELocale.languages[language] {
				self.localeBox?.stringValue = name
			}
		}
	}
	
	@IBAction func valuesChanged(sender: NSObject) {
		let langs = [String](QBELocale.languages.keys)
		if let index = self.localeBox?.indexOfSelectedItem where index >= 0 {
			NSUserDefaults.standardUserDefaults().setObject(langs[index], forKey: "locale")
		}
	}
	
	func comboBox(aComboBox: NSComboBox, objectValueForItemAtIndex index: Int) -> AnyObject {
		if aComboBox == separatorBox {
			return locale.commonFieldSeparators[index]
		}
		else if aComboBox == localeBox {
			let langs = [String](QBELocale.languages.values)
			return langs[index]
		}
		
		return ""
	}
	
	func numberOfItemsInComboBox(aComboBox: NSComboBox) -> Int {
		if aComboBox == separatorBox {
			return locale.commonFieldSeparators.count
		}
		else if aComboBox == localeBox {
			return QBELocale.languages.count
		}
		return 0
	}
}