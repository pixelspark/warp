import Foundation
import Cocoa

class QBESettingsViewController: NSViewController, NSComboBoxDataSource {
	var locale: QBELocale! { get {
		return QBEAppDelegate.sharedInstance.locale
	} }
	
	override func viewWillAppear() {
		assert(locale != nil, "Locale needs to be set before presenting settings view controller")
	}
	
	func comboBox(aComboBox: NSComboBox, objectValueForItemAtIndex index: Int) -> AnyObject {
		return locale.commonFieldSeparators[index]
	}
	
	func numberOfItemsInComboBox(aComboBox: NSComboBox) -> Int {
		return locale.commonFieldSeparators.count
	}
}