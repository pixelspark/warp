import Foundation
import Cocoa

class QBESettings {
	static let sharedInstance = QBESettings()
	private let defaults: NSUserDefaults
	
	init () {
		defaults = NSUserDefaults.standardUserDefaults()
		
		#if DEBUG
			resetOnces()
		#endif
	}
	
	var locale: QBELocale.QBELanguage {
		get {
			return defaults.stringForKey("locale") ?? QBELocale.defaultLanguage
		}
	}
	
	var defaultFieldSeparator: String {
		get {
			return defaults.stringForKey("defaultSeparator") ?? ","
		}
	}
	
	/** Call the provided callback only when this function has not been called before with the same key. This can be used
	to show the user certain things (such as tips) only once. **/
	func once(key: String, callback: () -> ()) {
		let onceKey = "once.\(key)"
		if !defaults.boolForKey(onceKey) {
			defaults.setBool(true, forKey: onceKey)
			callback()
		}
	}
	
	func resetOnces() {
		/* In debug builds, all keys starting with "once." are removed, to re-enable all 'once' actions such as
		first-time tips. */
		let dict = defaults.dictionaryRepresentation()
		for (key, value) in dict {
			let keyString = key.description
			if let r = keyString.rangeOfString("once.", options: NSStringCompareOptions.CaseInsensitiveSearch, range: nil, locale: nil) where r.startIndex==keyString.startIndex {
				defaults.removeObjectForKey(keyString)
			}
		}
	}
}

class QBESettingsViewController: NSViewController, NSComboBoxDataSource {
	@IBOutlet var separatorBox: NSComboBox?
	@IBOutlet var localeBox: NSComboBox?
	
	var locale: QBELocale! { get {
		return QBEAppDelegate.sharedInstance.locale
	} }
	
	override func viewWillAppear() {
		assert(locale != nil, "Locale needs to be set before presenting settings view controller")
		
		self.view.window?.titlebarAppearsTransparent = true
		
		if let language = NSUserDefaults.standardUserDefaults().stringForKey("locale") {
			if let name = QBELocale.languages[language] {
				self.localeBox?.stringValue = name
			}
		}
	}
	
	@IBAction func resetOnces(sender: NSObject) {
		QBESettings.sharedInstance.resetOnces()
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