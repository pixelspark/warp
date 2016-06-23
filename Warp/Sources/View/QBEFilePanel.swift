import Foundation
import WarpCore

class QBEFilePanelAccessoryView: NSViewController {
	@IBOutlet var popupButton: NSPopUpButton!
	weak var savePanel: NSSavePanel? = nil

	private var extensions: [String] = []

	var allowedFileTypes: [String: String] = [:] { didSet {
		self.extensions = Array(allowedFileTypes.keys)
		self.popupButton.removeAllItems()

		var options: [String] = []
		for ext in extensions {
			options.append("\(allowedFileTypes[ext]!) (*.\(ext))")
		}
		self.popupButton.addItems(withTitles: options)
	} }

	var selectedExtension: String? { get {
		if popupButton.indexOfSelectedItem >= 0 && popupButton.indexOfSelectedItem < self.extensions.count {
			return extensions[popupButton.indexOfSelectedItem]
		}
		return nil
	} }

	@IBAction func didSelectType(_ sender: NSObject) {
		if popupButton.indexOfSelectedItem >= 0 && popupButton.indexOfSelectedItem < self.extensions.count {
			let ext = extensions[popupButton.indexOfSelectedItem]
			if let sp = savePanel {
				sp.allowedFileTypes = [ext]
			}
		}
	}
}

class QBEFilePanel {
	let allowedFileTypes: [String: String] // extension -> label
	var allowsOtherFileTypes: Bool = false

	init(allowedFileTypes: [String: String]) {
		self.allowedFileTypes = allowedFileTypes
	}

	func askForSaveFile(_ inWindow: NSWindow, callback: (Fallible<URL>) -> ()) {
		let no = NSSavePanel()
		no.allowedFileTypes = Array(allowedFileTypes.keys)
		no.allowsOtherFileTypes = self.allowsOtherFileTypes
		no.isExtensionHidden = true

		// Create accessory view
		if let accessoryView = QBEFilePanelAccessoryView(nibName: "QBEFilePanelAccessoryView", bundle: nil) {
			no.accessoryView = accessoryView.view
			accessoryView.savePanel = no
			accessoryView.allowedFileTypes = self.allowedFileTypes

			no.beginSheetModal(for: inWindow) { (result) -> Void in
				let x = accessoryView
				x.allowedFileTypes.removeAll()
				if result == NSFileHandlingPanelOKButton {
					callback(.success(no.url!))
				}
				else {
					callback(.failure(NSLocalizedString("No file was selected.", comment: "")))
				}
			}
		}
	}
}
