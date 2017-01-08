/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import UIKit
import Eureka
import WarpCore

class QBEJobProgressViewController: JobDelegate {
	let job: Job
	let alertController: UIAlertController

	init(job: Job, title: String) {
		self.job = job
		self.alertController = UIAlertController(title: title, message: "-%", preferredStyle: .alert)
		self.alertController.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel, handler: { _ in
			self.job.cancel()
			self.dismiss()
		}))

		self.job.addObserver(self)
	}

	deinit {
		self.dismiss()
	}

	func dismiss() {
		self.alertController.dismiss(animated: true, completion: nil)
	}

	func job(_ job: AnyObject, didProgress progress: Double) {
		asyncMain {
			self.alertController.message = "\(Int(progress * 100.0))%"
		}
	}
}

protocol QBEConfigurableFileWriter: QBEFileWriter, QBEFormConfigurable {
}

extension QBECSVWriter: QBEConfigurableFileWriter {
	var form: Form {
		let form = Form()

		form +++ Section("Format".localized)
			<<< TextRow(){ row in
				row.title = "Field separator".localized
				row.value = String(Character(UnicodeScalar(self.separatorCharacter)!))
				row.onChange {
					if let v = $0.value, !v.isEmpty {
						self.separatorCharacter = v.utf16[v.utf16.startIndex]
						row.value = String(Character(UnicodeScalar(self.separatorCharacter)!))
					}
				}
				row.cellSetup({ (cell, row) in
					cell.textField.autocapitalizationType = .none
				})
			}

		return form
	}
}

protocol QBEExportViewControllerDelegate: class {
	func exportViewController(_: QBEExportViewController, shareFileAt url: URL, callback: @escaping () -> ())
}

class QBEExportViewController: FormViewController {
	var exporter: QBEConfigurableFileWriter! = nil
	var configurable: QBEFormConfigurable! = nil
	var source: QBEChain! = nil
	var fileName: String! = nil
	var fileExtension = "csv"
	weak var delegate: QBEExportViewControllerDelegate? = nil

	fileprivate let workerQueue: OperationQueue = {
		let workerQueue = OperationQueue()
		workerQueue.name = "nl.pixelspark.Warp.QBEExportViewController.WorkerQueue"
		workerQueue.maxConcurrentOperationCount = 1
		return workerQueue
	}()

	override func viewDidLoad() {
		self.exporter = QBECSVWriter(locale: QBEAppDelegate.sharedInstance.locale, title: nil)

		super.viewDidLoad()
		self.fileName = "Exported data".localized
		self.modalPresentationStyle = .formSheet

		self.navigationItem.title = "Export to file".localized
		self.navigationItem.setRightBarButtonItems([
			UIBarButtonItem(title: "Save".localized, style: .done, target: self, action: #selector(self.save(_:))),
			UIBarButtonItem(title: "Share".localized, style: .plain, target: self, action: #selector(self.share(_:))),
		], animated: false)

		self.navigationItem.setLeftBarButton(UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancel(_:))), animated: false)

		form = Form()

		form += Form() +++ Section("Export to".localized)
			<<< TextRow() { row in
				row.title = "File name".localized
				row.value = "Exported data".localized
				row.onChange({ (tr) in
					self.fileName = tr.value
				})
				return
			}

		form += exporter.form
		form.delegate = self
	}

	@IBAction func cancel(_ sender: AnyObject?) {
		self.dismiss(animated: true)
	}

	private func reportError(_ error: String) {
		asyncMain {
			let uac = UIAlertController(title: "Could not export data".localized, message: error, preferredStyle: .alert)
			uac.addAction(UIAlertAction(title: "Dismiss".localized, style: .default, handler: nil))
			self.present(uac, animated: true, completion: nil)
		}
	}

	private func placeFile(source: URL, completion: @escaping ((Fallible<Void>) -> ())) {
		let fileManager = FileManager()
		guard let baseURL = fileManager.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").appendingPathComponent(self.fileName) else {
			completion(.failure("Please enable iCloud Drive in Settings to use this app".localized))
			return
		}

		// Find a file name that does not exist yet
		var target = baseURL.appendingPathExtension(fileExtension)
		var nameSuffix = 2
		while (target as NSURL).checkPromisedItemIsReachableAndReturnError(nil) {
			target = URL(fileURLWithPath: baseURL.path + "-\(nameSuffix).\(self.fileExtension)")
			nameSuffix += 1
		}

		// All good
		let writeIntent = NSFileAccessIntent.writingIntent(with: target, options: .forReplacing)
		let readIntent = NSFileAccessIntent.writingIntent(with: source, options: .forMoving)

		NSFileCoordinator().coordinate(with: [writeIntent, readIntent], queue: self.workerQueue) { err in
			guard err == nil else {
				completion(.failure(err!.localizedDescription))
				return
			}

			do {
				try fileManager.moveItem(at: readIntent.url, to: writeIntent.url)
				completion(.success())
			}
			catch {
				completion(.failure(error.localizedDescription))
				return
			}
		}
	}

	private func pathForTemporaryFile() -> URL {
		let basePath = (NSTemporaryDirectory() as NSString)
		var target = URL(fileURLWithPath: basePath.appendingPathComponent(self.fileName + "." + self.fileExtension))
		var nameSuffix = 2
		while (target as NSURL).checkPromisedItemIsReachableAndReturnError(nil) {
			target = URL(fileURLWithPath: basePath.appendingPathComponent(self.fileName + "-\(nameSuffix)." + self.fileExtension))
			nameSuffix += 1
		}

		return target
	}

	private func exportToTempFile(completion: @escaping ((Fallible<URL>) -> ())) {
		if let s = self.source.head {
			let locale = QBEAppDelegate.sharedInstance.locale
			let job = Job(.userInitiated)

			let jc = QBEJobProgressViewController(job: job, title: "Exporting to file...".localized)
			self.present(jc.alertController, animated: true, completion: nil)

			s.fullDataset(job) { result in
				switch result {
				case .success(let dataset):
					let tempURL = self.pathForTemporaryFile()
					self.exporter.writeDataset(dataset, toFile: tempURL, locale: locale, job: job, callback: { result in
						switch result {
						case .success():
							asyncMain {
								jc.dismiss()
							}
							completion(.success(tempURL))

						case .failure(let e):
							asyncMain {
								jc.dismiss()
							}
							return completion(.failure(e))
						}
					})
				case .failure(let e):
					asyncMain {
						jc.dismiss()
					}
					return completion(.failure(e))
				}
			}
		}
	}

	@IBAction func save(_ sender: AnyObject?) {
		self.exportToTempFile { result in
			switch result {
			case .success(let tempURL):
				self.placeFile(source: tempURL, completion: { result in
					switch result {
					case .success:
						asyncMain {
							self.dismiss(animated: true)
						}
					case .failure(let e):
						self.reportError(e)
					}
				})

			case .failure(let e):
				self.reportError(e)
			}
		}
	}

	@IBAction func share(_ sender: AnyObject?) {
		self.exportToTempFile { result in
			switch result {
			case .success(let tempURL):
				asyncMain {
					self.dismiss(animated: false) {
						self.delegate?.exportViewController(self, shareFileAt: tempURL, callback: {
							do {
								try FileManager.default.removeItem(at: tempURL)
							}
							catch {
								self.reportError(error.localizedDescription)
							}
						})
					}

				}
			case .failure(let e):
				self.reportError(e)
			}
		}
	}
}
