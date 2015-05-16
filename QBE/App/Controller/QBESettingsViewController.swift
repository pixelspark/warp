import Foundation
import Cocoa

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