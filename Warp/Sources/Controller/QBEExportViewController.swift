import Foundation
import WarpCore

@objc protocol QBEExportViewDelegate: NSObjectProtocol {
	optional func exportView(view: QBEExportViewController, didAddStep: QBEExportStep)
	optional func exportView(view: QBEExportViewController, finishedExportingTo: NSURL)
}

class QBEExportViewController: NSViewController, JobDelegate, QBESentenceViewDelegate {
	var step: QBEExportStep?
	var locale: Locale = Locale()
	weak var delegate: QBEExportViewDelegate? = nil

	@IBOutlet var progressView: NSProgressIndicator?
	@IBOutlet var backgroundButton: NSButton?
	@IBOutlet var exportButton: NSButton?
	@IBOutlet var addAsStepButton: NSButton?

	private var sentenceEditor: QBESentenceViewController!
	private var isExporting: Bool = false
	private var notifyUser = false
	private var job: Job? = nil

	@IBAction func addAsStep(sender: NSObject) {
		if let s = self.step {
			delegate?.exportView?(self, didAddStep: s)
		}
		self.dismissController(sender)
	}

	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier == "sentenceEditor" {
			self.sentenceEditor = segue.destinationController as? QBESentenceViewController
		}
	}

	func job(job: AnyObject, didProgress: Double) {
		self.progressView?.doubleValue = didProgress * 1000.0
	}

	override func viewWillAppear() {
		super.viewWillAppear()
		update()
		if let s = step {
			self.sentenceEditor?.configure(s, variant: .Write, delegate: self)
		}
	}

	func sentenceView(view: QBESentenceViewController, didChangeConfigurable: QBEConfigurable) {
		// TODO check if export is possible
	}

	private func update() {
		self.progressView?.hidden = !isExporting
		self.backgroundButton?.hidden = !isExporting
		self.addAsStepButton?.enabled = !isExporting
		self.addAsStepButton?.hidden = self.delegate == nil || !(self.delegate?.respondsToSelector(Selector("exportView:didAddStep:")) ?? true)
		self.exportButton?.enabled = !isExporting
	}

	@IBAction func continueInBackground(sender: NSObject) {
		if let j = job {
			if let url = self.step?.file?.url?.lastPathComponent {
				let jobName = String(format: NSLocalizedString("Export data to '%@'", comment: ""), url)
				QBEAppDelegate.sharedInstance.jobsManager.addJob(j, description: jobName)
			}

		}
		self.notifyUser = true
		self.dismissController(sender)
	}

	@IBAction func exportOnce(sender: NSObject) {
		let alertWindow = self.presentingViewController?.view.window
		let job = Job(.UserInitiated)
		self.job = job
		job.addObserver(self)
		isExporting = true
		update()
		// What type of file are we exporting?
		job.async {
			if let cs = self.step {
				cs.write(job) { (fallibleData: Fallible<Data>) -> () in
					asyncMain {
						let alert = NSAlert()

						switch fallibleData {
						case .Success(_):
							self.dismissController(sender)
							if self.notifyUser {
								let un = NSUserNotification()
								un.soundName = NSUserNotificationDefaultSoundName
								un.deliveryDate = NSDate()
								un.title = NSLocalizedString("Export completed", comment: "")
								if let url = self.step?.file?.url?.lastPathComponent {
									un.informativeText = String(format: NSLocalizedString("The data has been saved to '%@'", comment: ""), url)
								}
								NSUserNotificationCenter.defaultUserNotificationCenter().scheduleNotification(un)
							}

							if let url = self.step?.file?.url {
								self.delegate?.exportView?(self, finishedExportingTo: url)
							}

						case .Failure(let errorMessage):
							self.isExporting = false
							self.update()
							alert.messageText = errorMessage
							if let w = self.view.window where w.visible {
								alert.beginSheetModalForWindow(w, completionHandler: nil)
							}
							else if let w = alertWindow {
								alert.beginSheetModalForWindow(w, completionHandler: nil)
							}
						}
					}
				}
			}
		}
	}
}