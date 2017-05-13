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

class QBEUploadViewController: NSViewController, QBESentenceViewDelegate, JobDelegate, QBEColumnMappingDelegate {
	private var targetSentenceViewController: QBESentenceViewController? = nil
	@IBOutlet private var progressBar: NSProgressIndicator?
	@IBOutlet private var okButton: NSButton?
	@IBOutlet private var removeBeforeUpload: NSButton?
	@IBOutlet private var columnMappingButton: NSButton?
	@IBOutlet private var alterButton: NSButton?

	var afterSuccessfulUpload: (() -> ())? = nil
	var mapping: ColumnMapping? = nil
	private var sourceStep: QBEStep? = nil
	var retryUploadAfterMapping = false

	private var targetStep: QBEStep? { didSet {
		initializeView()
	} }

	var uploadJob: Job? = nil

	private var targetMutableDataset: MutableDataset? = nil

	public func setup(job: Job, source: QBEStep, target: QBEStep, callback: @escaping (Fallible<Void>) -> ()) {
		self.sourceStep = source
		self.targetStep = target

		targetStep?.mutableDataset(job) { result in
			switch result {
			case .success(let md):
				asyncMain {
					self.targetMutableDataset = md
					callback(.success())
				}

			case .failure(let e):
				callback(.failure(e))
			}
		}
	}

	private func initializeView() {
		assertMainThread()
		if let s = targetStep {
			self.targetSentenceViewController?.startConfiguring(s, variant: .write, delegate: self)
		}
	}

	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		if segue.identifier == "targetSentenceView" {
			self.targetSentenceViewController = segue.destinationController as? QBESentenceViewController
		}
		else {
			fatalError("Unknown segue")
		}
	}

	override func viewWillAppear() {
		self.initializeView()
		self.updateView()
		super.viewWillAppear()
	}

	var needsColumnMapping: Bool {
		if let s = targetMutableDataset {
			return s.warehouse.hasFixedColumns
		}
		return false
	}

	var canPerformUpload: Bool = false { didSet {
		if oldValue != canPerformUpload {
			asyncMain {
				self.updateView()
			}
		}
	} }

	var canPerformTruncateBeforeUpload: Bool = false { didSet {
		if oldValue != canPerformTruncateBeforeUpload {
			asyncMain {
				self.updateView()
			}
		}
	} }

	@IBAction func updateFromInterface(_ sender: NSObject) {
		self.updateView()
	}

	private func updateView() {
		self.progressBar?.isHidden = self.uploadJob == nil
		self.progressBar?.isIndeterminate = true
		self.okButton?.isEnabled = self.canPerformUpload && self.uploadJob == nil
		self.targetSentenceViewController?.enabled = self.uploadJob == nil
		self.removeBeforeUpload?.isEnabled = self.canPerformTruncateBeforeUpload && self.uploadJob == nil
		self.columnMappingButton?.isEnabled = self.uploadJob == nil && needsColumnMapping && !shouldAlter
		self.alterButton?.isEnabled = self.uploadJob == nil && canAlter

		if self.uploadJob == nil {
			self.progressBar?.stopAnimation(nil)
			if let source = sourceStep {
				let job = Job(.userInitiated)

				if let mutableDataset = targetMutableDataset {
					source.fullDataset(job) { data in
						switch data {
						case .success(let fd):
							// FIXME add mapping (second [:])
							let mutation = DatasetMutation.import(data: fd, withMapping: [:])
							self.canPerformUpload = mutableDataset.canPerformMutation(mutation.kind)
							self.canPerformTruncateBeforeUpload = mutableDataset.canPerformMutation(.truncate)

							// Get the source column names
							fd.columns(job) { result in
								switch result {
								case .success(let columns):
									/* Put the source table definition on the 'table definition pasteboard'. The 'alter table'
									view controller will try to read from the pasteboard, and use the column names given there
									as default table definition when creating a new table. */
									// TODO: can we get identifier information from the source data set?
									let def = Schema(columns: columns, identifier: nil)
									let pb = NSPasteboard(name: def.pasteboardName)
									pb.setData(NSKeyedArchiver.archivedData(withRootObject: Coded(def)), forType: def.pasteboardName)

								case .failure(_):
									break
								}
							}

						case .failure(_):
							self.canPerformUpload = false
							self.canPerformTruncateBeforeUpload = false
						}
					}
				}
			}
			else {
				self.canPerformUpload = false
				self.canPerformTruncateBeforeUpload = false
			}
		}
	}

	private func performUpload(_ data: Dataset, destination: MutableDataset) {
		// FIXME add mapping (second [:])
		let mutation = DatasetMutation.import(data: data, withMapping: self.mapping ?? [:])
		if destination.canPerformMutation(mutation.kind) {
			asyncMain {
				self.updateView()
			}

			self.uploadJob!.async {
				destination.performMutation(mutation, job: self.uploadJob!) { result in
					switch result {
					case .success(_):
						self.afterSuccessfulUpload?()
						asyncMain {
							self.dismiss(nil)
						}
						break

					case .failure(let e):
						asyncMain {
							self.abortUploadWithError(e)
						}
						break
					}
				}
			}
		}
	}

	private func performTruncate(_ perform: Bool, destination: MutableDataset, callback: @escaping (Fallible<Void>) -> ()) {
		if perform {
			destination.performMutation(.truncate, job: self.uploadJob!) { res in
				switch res {
				case .success(_):
					callback(.success())

				case .failure(let e):
					asyncMain {
						self.abortUploadWithError(e)
					}
				}
			}
		}
		else {
			callback(.success())
		}
	}

	private func performAlter(_ perform: Bool, sourceDataset: Dataset, destination: MutableDataset, callback: @escaping (Fallible<Bool>) -> ()) {
		if perform {
			// See which columns are already at the destination
			destination.schema(self.uploadJob!) { result in
				switch result {
				case .success(let destinationSchema):
					var newSchema = destinationSchema

					// Find out what columns are in the source data set
					sourceDataset.columns(self.uploadJob!) { result in
						switch result {
						case .success(let sourceColumns):
							newSchema.change(columns: sourceColumns)

							// Update the destination schema
							destination.performMutation(.alter(newSchema), job: self.uploadJob!) { res in
								switch res {
								case .success(_):
									self.mapping = sourceColumns.mapDictionary { return ($0,$0) }
									callback(.success(true))
								case .failure(let e):
									callback(.failure(e))
								}
							}

						case .failure(let e): callback(.failure(e))
						}
					}

				case .failure(let e):
					return callback(.failure(e))
				}
			}
		}
		else {
			performCheck(destination, source: sourceDataset, callback: callback)
		}
	}

	// Callback returns 'false' if the mapping is incomplete.
	private func performCheck(_ destination: MutableDataset, source: Dataset, callback: @escaping (Fallible<Bool>) -> ()) {
		if !destination.warehouse.hasFixedColumns {
			// The target is a NoSQL database, we can insert whatever record we want
			callback(.success(true))
			return
		}

		// Check whether the source and destination columns match
		destination.data(self.uploadJob!) { result in
			switch result {
			case .success(let destDataset):
				destDataset.columns(self.uploadJob!) { result in
					switch result {
					case .success(let cols):
						// Are all destination columns present in the mapping?
						if self.mapping == nil || !Set(cols).isSubset(of: Set(self.mapping!.keys)) {
							callback(.success(false))
							return
						}

						callback(.success(true))

					case .failure(_):
						// Supposedly the destination data set does not exist yet
						callback(.success(true))
					}
				}

			case .failure(_):
				// Supposedly the destination data set does not exist yet
				callback(.success(true))
			}
		}
	}

	private func abortUploadWithError(_ message: String) {
		assertMainThread()

		self.canPerformUpload = false
		self.uploadJob = nil
		self.updateView()

		let alert = NSAlert()
		alert.alertStyle = NSAlertStyle.critical
		alert.informativeText = message
		alert.messageText = NSLocalizedString("Could not upload data", comment: "")
		if let w = self.view.window {
			alert.beginSheetModal(for: w, completionHandler: nil)
		}
	}

	@IBAction func editColumnMapping(_ sender: NSObject) {
		self.editColumnMapping(andUploadAfterMapping: false)
	}

	private func editColumnMapping(andUploadAfterMapping: Bool = false) {
		let job = Job(.userInitiated)
		self.retryUploadAfterMapping = andUploadAfterMapping

		// Get source and destination columns
		if let destination = self.targetMutableDataset, let source = self.sourceStep {
			// Fetch destination columns
			destination.data(job) { result in
				switch result {
				case .success(let destDataset):
					destDataset.columns(job) { result in
						switch result {
						case .success(let destinationColumns):
							// Fetch source columns
							source.fullDataset(job) { result in
								switch result {
								case .success(let sourceDataset):
									sourceDataset.columns(job) { result in
										switch result {
										case .success(let sourceColumns):
											// Make a default mapping if none exists yet
											if self.mapping == nil {
												self.mapping = [:]
												for column in Set(sourceColumns).intersection(Set(destinationColumns)) {
													self.mapping![column] = column
												}

												for column in Set(destinationColumns).subtracting(Set(sourceColumns)) {
													self.mapping![column] = Column("")
												}
											}

											// Make sure all destination columns appear in this mapping
											for col in destinationColumns {
												if self.mapping![col] == nil  {
													self.mapping![col] = Column("")
												}
											}

											// Make sure no destination columns that do not exist appear
											for (key, _) in self.mapping! {
												if !destinationColumns.contains(key) {
													self.mapping!.removeValue(forKey: key)
												}
											}

											job.log("MAP=\(self.mapping!)")

											asyncMain {
												if let vc = self.storyboard?.instantiateController(withIdentifier: "columnMapping") as? QBEColumnMappingViewController {
													vc.mapping = self.mapping!
													vc.sourceColumns = sourceColumns
													vc.delegate = self
													self.presentViewControllerAsSheet(vc)
												}
											}

										case .failure(let e):
											job.log("Error: \(e)")
										}
									}

								case .failure(let e):
									job.log("Error: \(e)")
								}
							}

						case .failure(let e):
							job.log("Error: \(e)")
						}
					}

				case .failure(let e):
					job.log("Error: \(e)")
				}
			}
		}
	}

	var canAlter: Bool {
		if let md = self.targetMutableDataset {
			return md.canPerformMutation(.alter) && md.warehouse.hasFixedColumns
		}
		return false
	}

	var shouldAlter: Bool {
		return canAlter && (self.alterButton?.state ?? NSOffState) == NSOnState
	}

	@IBAction func create(_ sender: NSObject) {
		self.startUpload()
	}

	private func startUpload() {
		assert(uploadJob == nil, "Cannot start two uploads at the same time")

		if let source = sourceStep, let mutableDataset = targetMutableDataset, canPerformUpload {
			let shouldTruncate = self.removeBeforeUpload?.state == NSOnState && self.canPerformTruncateBeforeUpload
			self.uploadJob = Job(.userInitiated)
			self.uploadJob!.addObserver(self)
			self.progressBar?.doubleValue = 0.0
			self.progressBar?.isIndeterminate = true
			self.progressBar?.startAnimation(self)
			updateView()

			source.fullDataset(uploadJob!) { data in
				switch data {
				case .success(let fd):
					// TODO: make this into a transaction somehow
					self.performAlter(self.shouldAlter, sourceDataset: fd, destination: mutableDataset) { result in
						switch result {
						case .success(let mappingComplete):
							if !mappingComplete {
								asyncMain {
									self.uploadJob = nil
									self.updateView()
									self.editColumnMapping(andUploadAfterMapping: true)
								}
							}
							else {
								self.performTruncate(shouldTruncate, destination: mutableDataset) { result in
									switch result  {
									case .success(_):
										self.performUpload(fd, destination: mutableDataset)

									case .failure(let e):
										asyncMain {
											self.abortUploadWithError(e)
										}
									}
								}
							}
						case .failure(let e):
							asyncMain {
								self.abortUploadWithError(e)
							}
						}
					}

				case .failure(let e):
					asyncMain {
						self.abortUploadWithError(e)
					}
				}
			}
		}
	}

	@IBAction func cancel(_ sender: NSObject) {
		if let uj = self.uploadJob {
			uj.cancel()
		}
		self.dismiss(sender)
	}

	var locale: Language { get { return QBEAppDelegate.sharedInstance.locale } }

	func columnMappingView(_ view: QBEColumnMappingViewController, didChangeMapping: ColumnMapping) {
		self.mapping = didChangeMapping

		if retryUploadAfterMapping {
			retryUploadAfterMapping = false
			self.uploadJob = nil
			self.startUpload()
		}
	}

	func sentenceView(_ view: QBESentenceViewController, didChangeConfigurable: QBEConfigurable) {
		self.updateView()
	}

	@objc func job(_ job: AnyObject, didProgress: Double) {
		asyncMain {
			self.progressBar?.isIndeterminate = false
			self.progressBar?.stopAnimation(nil)
			self.progressBar?.minValue = 0.0
			self.progressBar?.maxValue = 1.0
			self.progressBar?.doubleValue = didProgress
		}
	}
}
