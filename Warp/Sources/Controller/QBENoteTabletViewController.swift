import Cocoa

class QBENoteTabletViewController: QBETabletViewController {
	@IBOutlet var textField: NSTextView!

	private var noteTablet: QBENoteTablet? { return self.tablet as? QBENoteTablet }

	override func viewWillAppear() {
		textField.insertText(self.noteTablet?.text ?? NSAttributedString())
	}

	override func controlTextDidChange(obj: NSNotification) {
		self.noteTablet?.text = textField.attributedString()
	}
}