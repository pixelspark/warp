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
	
	var exampleMaximumTime: Double {
		get {
			return defaults.doubleForKey("exampleMaximumTime") ?? 1.5
		}
		
		set {
			defaults.setDouble(max(0.25, newValue), forKey: "exampleMaximumTime")
		}
	}
	
	var exampleMaximumRows: Int {
		get {
			return defaults.integerForKey("exampleMaximumRows") ?? 500
		}
		
		set {
			defaults.setInteger(max(100, newValue), forKey: "exampleMaximumRows")
		}
	}
	
	func defaultWidthForColumn(withName: QBEColumn) -> Double? {
		return defaults.doubleForKey("width.\(withName.name)")
	}
	
	func setDefaultWidth(width: Double, forColumn: QBEColumn) {
		defaults.setDouble(width, forKey: "width.\(forColumn.name)")
	}
	
	/** Return whether it is allowable to cache a file of the indicated size in the indicated location. This function 
	bases its decision on the amount of disk space free in the target location (and allows any file to be cached to
	only use a particular fraction of it). In the future, it may use preferences exposed to the user. The result of this 
	function should be used to set the default preference for caching in steps that allow the user to toggle caching.
	Caching explicitly requested by the user should be disabled anyway if this function returns false. **/
	func shouldCacheFile(ofEstimatedSize size: Int, atLocation: NSURL) -> Bool {
		// Let's find out how much disk space is left in the proposed cache location
		var error: NSError?
		if let attrs = NSFileManager.defaultManager().attributesOfFileSystemForPath(atLocation.path!, error: &error) {
			if let freeSpace = attrs[NSFileSystemFreeSize] as? NSNumber {
				let freeSize = Double(size) / Double(freeSpace)
				if freeSize < 0.8 {
					return true
				}
			}
		}
		return false
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
	@IBOutlet var exampleRowsSlider: NSSlider?
	@IBOutlet var exampleTimeSlider: NSSlider?
	@IBOutlet var exampleRowsLabel: NSTextField?
	@IBOutlet var exampleTimeLabel: NSTextField?
	
	var locale: QBELocale! { get {
		return QBEAppDelegate.sharedInstance.locale
	} }
	
	override func viewWillAppear() {
		assert(locale != nil, "Locale needs to be set before presenting settings view controller")
		self.view.window?.titlebarAppearsTransparent = true
		updateView()
	}
	
	private func updateView() {
		let formatter = NSNumberFormatter()
		formatter.numberStyle = .DecimalStyle
		formatter.usesSignificantDigits = false
		formatter.minimumFractionDigits = 1
		formatter.maximumFractionDigits = 1
		
		self.exampleRowsSlider?.integerValue = QBESettings.sharedInstance.exampleMaximumRows
		self.exampleTimeSlider?.doubleValue = QBESettings.sharedInstance.exampleMaximumTime
		self.exampleRowsLabel?.integerValue = QBESettings.sharedInstance.exampleMaximumRows
		self.exampleTimeLabel?.stringValue = formatter.stringFromNumber(NSNumber(double: QBESettings.sharedInstance.exampleMaximumTime)) ?? ""
		
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
		if let mr = self.exampleRowsSlider?.integerValue {
			QBESettings.sharedInstance.exampleMaximumRows = mr
		}
		
		if let ms = self.exampleTimeSlider?.doubleValue {
			QBESettings.sharedInstance.exampleMaximumTime = ms
		}
		
		let langs = [String](QBELocale.languages.keys)
		if let index = self.localeBox?.indexOfSelectedItem where index >= 0 {
			NSUserDefaults.standardUserDefaults().setObject(langs[index], forKey: "locale")
		}
		
		updateView()
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