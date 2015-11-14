import Foundation
import WarpCore

class QBEUploadViewController: NSViewController, QBESentenceViewDelegate, QBEJobDelegate {
	private var targetSentenceViewController: QBESentenceViewController? = nil
	private var sourceSentenceViewController: QBESentenceViewController? = nil
	@IBOutlet private var progressBar: NSProgressIndicator?
	@IBOutlet private var okButton: NSButton?
	@IBOutlet private var removeBeforeUpload: NSButton?

	var afterSuccessfulUpload: (() -> ())? = nil

	var sourceStep: QBEStep? { didSet {
		initializeView()
	} }

	var targetStep: QBEStep? { didSet {
		initializeView()
	} }

	var uploadJob: QBEJob? = nil

	private func initializeView() {
		if let s = targetStep {
			self.targetSentenceViewController?.configure(s, variant: .Write, delegate: self)
		}
		if let s = sourceStep {
			self.sourceSentenceViewController?.configure(s, variant: .Read, delegate: self)
		}
	}

	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier == "sourceSentenceView" {
			self.sourceSentenceViewController = segue.destinationController as? QBESentenceViewController
		}
		else if segue.identifier == "targetSentenceView" {
			self.targetSentenceViewController = segue.destinationController as? QBESentenceViewController
		}
	}

	override func viewWillAppear() {
		self.initializeView()
		self.updateView()
		super.viewWillAppear()
	}

	var canPerformUpload: Bool = false { didSet {
		if oldValue != canPerformUpload {
			QBEAsyncMain {
				self.updateView()
			}
		}
	} }

	var canPerformTruncateBeforeUpload: Bool = false { didSet {
		if oldValue != canPerformTruncateBeforeUpload {
			QBEAsyncMain {
				self.updateView()
			}
		}
	} }

	private func updateView() {
		self.progressBar?.hidden = self.uploadJob == nil
		self.progressBar?.indeterminate = true
		self.okButton?.enabled = self.canPerformUpload && self.uploadJob == nil
		self.sourceSentenceViewController?.enabled = self.uploadJob == nil
		self.targetSentenceViewController?.enabled = self.uploadJob == nil
		self.removeBeforeUpload?.enabled = self.canPerformTruncateBeforeUpload && self.uploadJob == nil

		if self.uploadJob == nil {
			self.progressBar?.stopAnimation(nil)
			if let source = sourceStep, let mutableData = targetStep?.mutableData {
				let job = QBEJob(.UserInitiated)
				source.fullData(job) { data in
					switch data {
					case .Success(let fd):
						// FIXME add mapping (second [:])
						let mutation = QBEDataMutation.Insert(fd, [:])
						self.canPerformUpload = mutableData.canPerformMutation(mutation)
						self.canPerformTruncateBeforeUpload = mutableData.canPerformMutation(.Truncate)

					case .Failure(_):
						self.canPerformUpload = false
						self.canPerformTruncateBeforeUpload = false
					}
				}
			}
			else {
				self.canPerformUpload = false
				self.canPerformTruncateBeforeUpload = false
			}
		}
	}

	private func performUpload(data: QBEData, destination: QBEMutableData) {
		// FIXME add mapping (second [:])
		let mutation = QBEDataMutation.Insert(data, [:])
		if destination.canPerformMutation(mutation) {
			QBEAsyncMain {
				self.updateView()
			}

			self.uploadJob!.async {
				destination.performMutation(mutation, job: self.uploadJob!) { result in
					switch result {
					case .Success(_):
						self.afterSuccessfulUpload?()
						QBEAsyncMain {
							self.dismissController(nil)
						}
						break

					case .Failure(let e):
						QBEAsyncMain {
							self.abortUploadWithError(e)
						}
						break
					}
				}
			}
		}
	}

	private func performTruncate(perform: Bool, destination: QBEMutableData, callback: (QBEFallible<Void>) -> ()) {
		if perform {
			destination.performMutation(.Truncate, job: self.uploadJob!) { res in
				switch res {
				case .Success(_):
					callback(.Success())

				case .Failure(let e):
					QBEAsyncMain {
						self.abortUploadWithError(e)
					}
				}
			}
		}
		else {
			callback(.Success())
		}
	}

	private func abortUploadWithError(message: String) {
		QBEAssertMainThread()

		self.canPerformUpload = false
		self.uploadJob = nil
		self.updateView()

		let alert = NSAlert()
		alert.alertStyle = NSAlertStyle.CriticalAlertStyle
		alert.informativeText = message
		alert.messageText = NSLocalizedString("Could not upload data", comment: "")
		if let w = self.view.window {
			alert.beginSheetModalForWindow(w, completionHandler: nil)
		}
	}

	@IBAction func create(sender: NSObject) {
		assert(uploadJob == nil, "Cannot start two uploads at the same time")

		if let source = sourceStep, let mutableData = targetStep?.mutableData where canPerformUpload {
			let shouldTruncate = self.removeBeforeUpload?.state == NSOnState && self.canPerformTruncateBeforeUpload
			self.uploadJob = QBEJob(.UserInitiated)
			self.uploadJob!.addObserver(self)
			self.progressBar?.doubleValue = 0.0
			self.progressBar?.indeterminate = true
			self.progressBar?.startAnimation(sender)
			updateView()

			source.fullData(uploadJob!) { data in
				switch data {
				case .Success(let fd):
					// TODO: make this into a transaction somehow
					self.performTruncate(shouldTruncate, destination: mutableData) { result in
						switch result  {
						case .Success(_):
							self.performUpload(fd, destination: mutableData)

						case .Failure(let e):
							QBEAsyncMain {
								self.abortUploadWithError(e)
							}
						}
					}

				case .Failure(let e):
					QBEAsyncMain {
						self.abortUploadWithError(e)
					}
				}
			}
		}
	}

	@IBAction func cancel(sender: NSObject) {
		if let uj = self.uploadJob {
			uj.cancel()
		}
		self.dismissController(sender)
	}

	var locale: QBELocale { get { return QBEAppDelegate.sharedInstance.locale } }

	func sentenceView(view: QBESentenceViewController, didChangeStep: QBEStep) {
		self.updateView()
	}

	@objc func job(job: AnyObject, didProgress: Double) {
		QBEAsyncMain {
			self.progressBar?.indeterminate = false
			self.progressBar?.stopAnimation(nil)
			self.progressBar?.minValue = 0.0
			self.progressBar?.maxValue = 1.0
			self.progressBar?.doubleValue = didProgress
		}
	}
}