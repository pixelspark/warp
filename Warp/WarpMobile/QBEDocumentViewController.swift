/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import UIKit
import WarpCore

class QBEDocumentViewController: UIViewController {
	var document: QBEDocument!
	var opened = false

	var editingTablet: QBETablet? = nil { didSet {
		// Tablet must be in this document
		assert(editingTablet == nil || editingTablet?.document == self.document)
	} }

	var tabletController: QBEChainTabletViewController? = nil

	var documentURL: URL? {
		didSet {
			guard let url = documentURL else { return }

			document = QBEDocument(fileURL: url)

			do {
				var displayName: AnyObject?
				try (url as NSURL).getPromisedItemResourceValue(&displayName, forKey: URLResourceKey.localizedNameKey)
				title = displayName as? String
			}
			catch {
				// Ignore a failure here. We'll just keep the old display name.
			}
		}
	}

	var documentObserver: NSObjectProtocol?

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		if !opened {
			opened = true
			documentObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.UIDocumentStateChanged, object: document, queue: nil) { _ in
				if self.document.documentState.contains(.progressAvailable) {
					//self.progressView.observedProgress = self.document.progress
				}
			}

			self.document.open { success in
				if success {
					if let t = self.document.tablets.first {
						self.editingTablet = t
					}
					else {
						let ch = QBEChain(head: nil)
						let cht = QBEChainTablet(chain: ch)
						self.document.addTablet(cht)
						self.editingTablet = cht
					}

					self.updateView()
				}
				else {
					let title = self.documentURL?.lastPathComponent ?? ""

					let alert = UIAlertController(title: "Unable to Load \"\(title)\"", message: "Opening the document failed", preferredStyle: .alert)

					let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default) { action in
						_ = self.navigationController?.popToRootViewController(animated: true)
					}

					alert.addAction(alertAction)
					self.present(alert, animated: true, completion: nil)
				}

				if let observer = self.documentObserver {
					NotificationCenter.default.removeObserver(observer)
					self.documentObserver = nil
				}

				//self.progressView.isHidden = true
			}
		}
	}
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if self.isMovingFromParentViewController {
			document?.close(completionHandler: { success in
				if !success {
					let title = self.documentURL?.lastPathComponent ?? ""

					let alert = UIAlertController(title: "Unable to save \"\(title)\"", message: "Saving the document failed", preferredStyle: .alert)

					let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default) { action in
						_ = self.navigationController?.popToRootViewController(animated: true)
					}

					alert.addAction(alertAction)
					self.present(alert, animated: true, completion: nil)
				}
			})
		}
	}

	func updateView() {
		self.navigationItem.title = self.documentURL?.lastPathComponent ?? ""
		self.tabletController?.tablet = self.editingTablet as? QBEChainTablet
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "tablet", let dest = segue.destination as? QBEChainTabletViewController {
			self.tabletController = dest
			self.updateView()
		}
	}

	@IBAction func share(_ sender: UIBarButtonItem) {
		self.tabletController?.share(sender)
	}
}
