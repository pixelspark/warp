import Foundation
import WarpCore

class QBEUploadViewController: NSViewController, QBESentenceViewDelegate, QBEJobDelegate, QBEColumnMappingDelegate {
	private var targetSentenceViewController: QBESentenceViewController? = nil
	private var sourceSentenceViewController: QBESentenceViewController? = nil
	@IBOutlet private var progressBar: NSProgressIndicator?
	@IBOutlet private var okButton: NSButton?
	@IBOutlet private var removeBeforeUpload: NSButton?
	@IBOutlet private var columnMappingButton: NSButton?
	@IBOutlet private var alterButton: NSButton?

	var afterSuccessfulUpload: (() -> ())? = nil
	var mapping: QBEColumnMapping? = nil

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

	var needsColumnMapping: Bool {
		if let s = targetStep?.mutableData {
			return s.warehouse.hasFixedColumns
		}
		return false
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

	@IBAction func updateFromInterface(sender: NSObject) {
		self.updateView()
	}

	private func updateView() {
		self.progressBar?.hidden = self.uploadJob == nil
		self.progressBar?.indeterminate = true
		self.okButton?.enabled = self.canPerformUpload && self.uploadJob == nil
		self.sourceSentenceViewController?.enabled = self.uploadJob == nil
		self.targetSentenceViewController?.enabled = self.uploadJob == nil
		self.removeBeforeUpload?.enabled = self.canPerformTruncateBeforeUpload && self.uploadJob == nil
		self.columnMappingButton?.enabled = self.uploadJob == nil && needsColumnMapping && !shouldAlter
		self.alterButton?.enabled = self.uploadJob == nil && canAlter

		if self.uploadJob == nil {
			self.progressBar?.stopAnimation(nil)
			if let source = sourceStep, let mutableData = targetStep?.mutableData {
				let job = QBEJob(.UserInitiated)
				source.fullData(job) { data in
					switch data {
					case .Success(let fd):
						// FIXME add mapping (second [:])
						let mutation = QBEDataMutation.Import(data: fd, withMapping: [:])
						self.canPerformUpload = mutableData.canPerformMutation(mutation)
						self.canPerformTruncateBeforeUpload = mutableData.canPerformMutation(.Truncate)

						// Get the source column names
						fd.columnNames(job) { result in
							switch result {
							case .Success(let columnNames):
								/* Put the source table definition on the 'table definition pasteboard'. The 'alter table'
								view controller will try to read from the pasteboard, and use the column names given there
								as default table definition when creating a new table. */
								let def = QBEDataDefinition(columnNames: columnNames)
								let pb = NSPasteboard(name: QBEDataDefinition.pasteboardName)
								pb.setData(NSKeyedArchiver.archivedDataWithRootObject(def), forType: QBEDataDefinition.pasteboardName)

							case .Failure(_):
								break
							}
						}

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
		let mutation = QBEDataMutation.Import(data: data, withMapping: self.mapping ?? [:])
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

	private func performAlter(perform: Bool, sourceData: QBEData, destination: QBEMutableData, callback: (QBEFallible<Bool>) -> ()) {
		if perform {
			sourceData.columnNames(self.uploadJob!) { result in
				switch result {
				case .Success(let sourceColumns):
					destination.performMutation(.Alter(QBEDataDefinition(columnNames: sourceColumns)), job: self.uploadJob!) { res in
						switch res {
						case .Success(_):
							self.mapping = sourceColumns.mapDictionary { return ($0,$0) }
							callback(.Success(true))
						case .Failure(let e): callback(.Failure(e))
						}
					}

				case .Failure(let e): callback(.Failure(e))
				}
			}
		}
		else {
			performCheck(destination, source: sourceData, callback: callback)
		}
	}

	// Callback returns 'false' if the mapping is incomplete.
	private func performCheck(destination: QBEMutableData, source: QBEData, callback: (QBEFallible<Bool>) -> ()) {
		if !destination.warehouse.hasFixedColumns {
			// The target is a NoSQL database, we can insert whatever record we want
			callback(.Success(true))
			return
		}

		// Check whether the source and destination columns match
		destination.data(self.uploadJob!) { result in
			switch result {
			case .Success(let destData):
				destData.columnNames(self.uploadJob!) { result in
					switch result {
					case .Success(let cols):
						// Are all destination columns present in the mapping?
						if self.mapping == nil || !Set(cols).isSubsetOf(self.mapping!.keys) {
							callback(.Success(false))
							return
						}

						callback(.Success(true))

					case .Failure(_):
						// Supposedly the destination data set does not exist yet
						callback(.Success(true))
					}
				}

			case .Failure(_):
				// Supposedly the destination data set does not exist yet
				callback(.Success(true))
			}
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

	@IBAction func editColumnMapping(sender: NSObject) {
		let job = QBEJob(.UserInitiated)

		// Get source and destination columns
		if let destination = self.targetStep?.mutableData, let source = self.sourceStep {
			// Fetch destination columns
			destination.data(job) { result in
				switch result {
				case .Success(let destData):
					destData.columnNames(job) { result in
						switch result {
						case .Success(let destinationColumns):
							// Fetch source columns
							source.fullData(job) { result in
								switch result {
								case .Success(let sourceData):
									sourceData.columnNames(job) { result in
										switch result {
										case .Success(let sourceColumns):
											job.log("SRC=\(sourceColumns) DST=\(destinationColumns)")
											// Make a default mapping if none exists yet
											if self.mapping == nil {
												self.mapping = [:]
												for column in Set(sourceColumns).intersect(Set(destinationColumns)) {
													self.mapping![column] = column
												}

												for column in Set(destinationColumns).subtract(Set(sourceColumns)) {
													self.mapping![column] = QBEColumn("")
												}
											}

											// Make sure all destination columns appear in this mapping
											for col in destinationColumns {
												if self.mapping![col] == nil  {
													self.mapping![col] = QBEColumn("")
												}
											}

											job.log("MAP=\(self.mapping!)")

											QBEAsyncMain {
												if let vc = self.storyboard?.instantiateControllerWithIdentifier("columnMapping") as? QBEColumnMappingViewController {
													vc.mapping = self.mapping!
													vc.sourceColumns = sourceColumns
													vc.delegate = self
													self.presentViewControllerAsSheet(vc)
												}
											}

										case .Failure(let e):
											job.log("Error: \(e)")
										}
									}

								case .Failure(let e):
									job.log("Error: \(e)")
								}
							}

						case .Failure(let e):
							job.log("Error: \(e)")
						}
					}

				case .Failure(let e):
					job.log("Error: \(e)")
				}
			}
		}
	}

	var canAlter: Bool {
		if let md = self.targetStep?.mutableData {
			return md.canPerformMutation(.Alter(QBEDataDefinition(columnNames: [QBEColumn("dummy")]))) && md.warehouse.hasFixedColumns
		}
		return false
	}

	var shouldAlter: Bool {
		return canAlter && (self.alterButton?.state ?? NSOffState) == NSOnState
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
					self.performAlter(self.shouldAlter, sourceData: fd, destination: mutableData) { result in
						switch result {
						case .Success(let mappingComplete):
							if !mappingComplete {
								QBEAsyncMain {
									self.uploadJob = nil
									self.updateView()
									self.editColumnMapping(sender)
								}
							}
							else {
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
							}
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

	func columnMappingView(view: QBEColumnMappingViewController, didChangeMapping: QBEColumnMapping) {
		self.mapping = didChangeMapping
	}

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