/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore

enum ExportError: Error {
	case error(String)
}

@objc protocol QBEExportViewDelegate: NSObjectProtocol {
	@objc optional func exportView(_ view: QBEExportViewController, didAddStep: QBEExportStep)
	@objc optional func exportView(_ view: QBEExportViewController, finishedExportingTo: URL)
}

class QBEExportViewController: NSViewController, JobDelegate, QBESentenceViewDelegate {
	typealias CompletionCallback = (Error?) -> ()

	var step: QBEExportStep?
	var locale: Language = Language()
	var completionCallback: CompletionCallback? = nil
	weak var delegate: QBEExportViewDelegate? = nil

	@IBOutlet var progressView: NSProgressIndicator?
	@IBOutlet var backgroundButton: NSButton?
	@IBOutlet var exportButton: NSButton?
	@IBOutlet var addAsStepButton: NSButton?

	private var sentenceEditor: QBESentenceViewController!
	private var isExporting: Bool = false
	private var notifyUser = false
	private var job: Job? = nil

	@IBAction func addAsStep(_ sender: NSObject) {
		if let s = self.step {
			delegate?.exportView?(self, didAddStep: s)
		}
		self.dismiss(sender)
	}

	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		if segue.identifier == "sentenceEditor" {
			self.sentenceEditor = segue.destinationController as? QBESentenceViewController
		}
	}

	func job(_ job: AnyObject, didProgress: Double) {
		self.progressView?.doubleValue = didProgress * 1000.0
	}

	override func viewWillAppear() {
		super.viewWillAppear()
		update()
		if let s = step {
			self.sentenceEditor?.startConfiguring(s, variant: .write, delegate: self)
		}
	}

	func sentenceView(_ view: QBESentenceViewController, didChangeConfigurable: QBEConfigurable) {
		// TODO check if export is possible
	}

	private func update() {
		self.progressView?.isHidden = !isExporting
		self.backgroundButton?.isHidden = !isExporting
		self.addAsStepButton?.isEnabled = !isExporting
		self.addAsStepButton?.isHidden = self.delegate == nil || !(self.delegate?.responds(to: #selector(QBEExportViewDelegate.exportView(_:didAddStep:))) ?? true)
		self.exportButton?.isEnabled = !isExporting
	}

	@IBAction func continueInBackground(_ sender: NSObject) {
		if let j = job {
			if let url = self.step?.file?.url?.lastPathComponent {
				let jobName = String(format: NSLocalizedString("Export data to '%@'", comment: ""), url)
				QBEAppDelegate.sharedInstance.jobsManager.addJob(j, description: jobName)
			}

		}
		self.notifyUser = true
		self.dismiss(sender)
	}

	@IBAction func exportOnce(_ sender: NSObject) {
		let alertWindow = self.presentingViewController?.view.window
		let job = Job(.userInitiated)
		self.job = job
		job.addObserver(self)
		isExporting = true
		update()
		// What type of file are we exporting?
		job.async {
			if let cs = self.step {
				cs.write(job) { (fallibleDataset: Fallible<Dataset>) -> () in
					asyncMain {
						let alert = NSAlert()

						switch fallibleDataset {
						case .success(_):
							self.dismiss(sender)
							self.completionCallback?(nil)

							if self.notifyUser {
								let un = NSUserNotification()
								un.soundName = NSUserNotificationDefaultSoundName
								un.deliveryDate = Date()
								un.title = NSLocalizedString("Export completed", comment: "")
								if let url = self.step?.file?.url?.lastPathComponent {
									un.informativeText = String(format: NSLocalizedString("The data has been saved to '%@'", comment: ""), url)
								}
								NSUserNotificationCenter.default.scheduleNotification(un)
							}

							if let url = self.step?.file?.url {
								self.delegate?.exportView?(self, finishedExportingTo: url)
							}

						case .failure(let errorMessage):
							self.completionCallback?(ExportError.error(errorMessage))
							self.isExporting = false
							self.update()
							alert.messageText = errorMessage
							if let w = self.view.window, w.isVisible {
								alert.beginSheetModal(for: w, completionHandler: nil)
							}
							else if let w = alertWindow {
								alert.beginSheetModal(for: w, completionHandler: nil)
							}
						}
					}
				}
			}
		}
	}
}
