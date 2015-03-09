import Foundation
import Cocoa

internal class QBECSVStepView: NSViewController, NSComboBoxDataSource {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var separatorField: NSComboBox?
	@IBOutlet var hasHeadersButton: NSButton?
	@IBOutlet var cacheButton: NSButton?
	@IBOutlet var cacheUpdateButton: NSButton?
	@IBOutlet var cacheProgress: NSProgressIndicator?
	@IBOutlet var fileField: NSTextField?
	
	let step: QBECSVSourceStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
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
		super.init(coder: coder)
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		updateView()
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
	
	@IBAction func trashCache(sender: NSObject) {
		if let s = step {
			s.updateCache(callback: {
				self.updateView()
			})
		}
		updateView()
	}
	
	private func updateView() {
		if let s = step {
			separatorField?.stringValue = String(Character(UnicodeScalar(s.fieldSeparator)))
			hasHeadersButton?.state = s.hasHeaders ? NSOnState : NSOffState
			cacheButton?.state = s.useCaching ? NSOnState : NSOffState
			cacheUpdateButton?.enabled = s.useCaching && s.isCached
			fileField?.stringValue = s.file?.url?.absoluteString ?? ""
			
			if s.useCaching && !s.isCached {
				cacheProgress?.startAnimation(nil)
			}
			else {
				cacheProgress?.stopAnimation(nil)
			}
		}
	}
	
	@IBAction func chooseFile(sender: NSObject) {
		if let s = step {
			let no = NSOpenPanel()
			no.canChooseFiles = true
			no.allowedFileTypes = ["public.comma-separated-values-text"]
			
			no.beginSheetModalForWindow(self.view.window!, completionHandler: { (result: Int) -> Void in
				if result==NSFileHandlingPanelOKButton {
					if let url = no.URLs[0] as? NSURL {
						var error: NSError?
						s.file = QBEFileReference.URL(url)
						self.delegate?.suggestionsView(self, previewStep: s)
					}
				}
				self.updateView()
			})
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
			
			let shouldCache = (cacheButton?.state == NSOnState)
			if s.useCaching != shouldCache {
				s.useCaching = shouldCache
				changed = true
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
		
		updateView()
	}
}