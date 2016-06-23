import Cocoa

class QBENoteTabletViewController: QBETabletViewController, NSTextStorageDelegate {
	@IBOutlet var textField: NSTextView!

	private var noteTablet: QBENoteTablet? { return self.tablet as? QBENoteTablet }

	override func viewWillAppear() {
		textField?.textStorage?.delegate = self
		if let text = self.noteTablet?.note.text {
			textField.textStorage?.setAttributedString(text)
		}
	}

	func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
		self.noteTablet?.note.text = textField.attributedString()
	}
}
