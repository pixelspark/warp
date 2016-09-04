/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
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

	func askForSaveFile(_ inWindow: NSWindow, callback: @escaping (Fallible<URL>) -> ()) {
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
