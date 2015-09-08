import Foundation
import WarpCore

protocol QBEExportViewDelegate: NSObjectProtocol {
	func exportView(view: QBEExportViewController, didAddStep: QBEExportStep)
}

class QBEExportViewController: NSViewController, QBEJobDelegate, QBESuggestionsViewDelegate {
	var step: QBEExportStep?
	var locale: QBELocale = QBELocale()
	weak var delegate: QBEExportViewDelegate? = nil

	@IBOutlet var progressView: NSProgressIndicator?
	@IBOutlet var backgroundButton: NSButton?
	@IBOutlet var exportButton: NSButton?
	@IBOutlet var addAsStepButton: NSButton?

	private var sentenceEditor: QBESentenceViewController!
	private var isExporting: Bool = false

	@IBAction func addAsStep(sender: NSObject) {
		if let s = self.step {
			delegate?.exportView(self, didAddStep: s)
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
			self.sentenceEditor?.configure(s, delegate: self)
		}
	}

	func suggestionsViewDidCancel(view: NSViewController) {
	}

	func suggestionsView(view: NSViewController, previewStep: QBEStep?) {
	}

	func suggestionsView(view: NSViewController, didSelectStep: QBEStep) {
	}

	func suggestionsView(view: NSViewController, didSelectAlternativeStep: QBEStep) {
	}

	var currentStep: QBEStep? { get { return self.step} }
	var undo: NSUndoManager? { get { return nil } }

	private func update() {
		self.progressView?.hidden = !isExporting
		self.backgroundButton?.hidden = !isExporting
		self.addAsStepButton?.enabled = !isExporting
		self.exportButton?.enabled = !isExporting
	}

	@IBAction func continueInBackground(sender: NSObject) {
		self.dismissController(sender)
	}

	@IBAction func exportOnce(sender: NSObject) {
		let alertWindow = self.presentingViewController?.view.window
		let job = QBEJob(.UserInitiated)
		job.addObserver(self)
		isExporting = true
		update()
		// What type of file are we exporting?
		job.async {
			if let cs = self.step {
				cs.write(job) { (fallibleData: QBEFallible<QBEData>) -> () in
					QBEAsyncMain {
						let alert = NSAlert()

						switch fallibleData {
						case .Success(_):
							self.dismissController(sender)

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