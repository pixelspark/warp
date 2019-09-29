/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

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
	var isUntitledDocument = false

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
			documentObserver = NotificationCenter.default.addObserver(forName:
			UIDocument.stateChangedNotification, object: document, queue: nil) { _ in
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
		if self.isMovingFromParent {
			let pc = self.parent

			document?.close(completionHandler: { success in
				if !success {
					let title = self.documentURL?.lastPathComponent ?? ""

					let alert = UIAlertController(title: "Unable to save \"\(title)\"", message: "Saving the document failed", preferredStyle: .alert)

					let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default) { action in
						_ = self.navigationController?.popToRootViewController(animated: true)
					}

					alert.addAction(alertAction)
					pc?.present(alert, animated: true, completion: nil)
				}
				else {
					if let d = self.document, self.isUntitledDocument {
						// Ask to rename or delete
						var newNameField: UITextField? = nil
						let uac = UIAlertController(title: "Do you want to save this document?".localized, message: nil, preferredStyle: .alert)
						uac.addTextField { (tf) in
							tf.autocapitalizationType = .none
							tf.text = d.fileURL.lastPathComponent
							newNameField = tf
						}

						uac.addAction(UIAlertAction(title: "Delete".localized, style: .destructive, handler: { (act) in
							DispatchQueue.global(qos: .userInitiated).async {
								NSFileCoordinator().coordinate(writingItemAt: d.fileURL, options: .forDeleting, error: nil) { (writingUrl) in
									do {
										try FileManager.default.removeItem(at: writingUrl)
									}
									catch {
										Swift.print("Failure deleting: \(error)")
									}
								}
							}
						}))

						uac.addAction(UIAlertAction(title: "Save".localized, style: .default, handler: { (act) in
							var du = d.fileURL
							if let nn = newNameField!.text {
								DispatchQueue.global(qos: .userInitiated).async {
									NSFileCoordinator().coordinate(writingItemAt: du, options: .contentIndependentMetadataOnly, error: nil) { (writingUrl) in
										do {
											let ext = du.pathExtension
											var uv = URLResourceValues()
											uv.name = "\(nn).\(ext)"
											try du.setResourceValues(uv)
										}
										catch {
											Swift.print("Failure deleting: \(error)")
										}
									}
								}
							}
						}))
						
						pc?.present(uac, animated: true, completion: {
						})
					}
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
