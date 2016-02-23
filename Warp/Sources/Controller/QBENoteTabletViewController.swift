import Cocoa

class QBENoteTabletViewController: QBETabletViewController {
	@IBOutlet var textField: NSTextView!

	private var noteTablet: QBENoteTablet? { return self.tablet as? QBENoteTablet }

	override func viewWillAppear() {
		if let text = self.noteTablet?.note.text {
			textField.textStorage?.setAttributedString(text)
		}
	}

	override func controlTextDidChange(obj: NSNotification) {
		self.noteTablet?.note.text = textField.attributedString()
	}
}