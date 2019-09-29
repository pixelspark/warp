import UIKit
import Eureka
import WarpCore

protocol QBEEditViewControllerDelegate: NSObjectProtocol {
	func editViewController(_: QBEEditViewController, didPerform mutation: DatasetMutation, completion: @escaping () -> ())
}

class QBEEditViewController: FormViewController {
	weak var delegate: QBEEditViewControllerDelegate? = nil

	private var mutableData: MutableDataset? = nil
	private var row: WarpCore.Row? = nil
	private var schema: Schema? = nil
	private var changes: [Column: Value] = [:]

	/** Start editing a row. When row is nil, the form will allow adding a row. */
	func startEditing(row: WarpCore.Row?, dataset: MutableDataset) {
		assertMainThread()

		self.mutableData = nil
		self.row = nil
		self.schema = nil
		self.changes = [:]

		let job = Job(.userInitiated)

		dataset.schema(job) { result in
			switch result {
			case .success(let schema):
				asyncMain {
					self.schema = schema
					self.mutableData = dataset
					self.row = row
					self.update()
				}

			case .failure(let e):
				asyncMain {
					self.showError(message: e) {
						asyncMain {
							self.dismiss(animated: true, completion: nil)
						}
					}
				}
			}
		}
	}

	private func showError(message: String, completion: (() -> ())? = nil) {
		assertMainThread()

		let ua = UIAlertController(title: "Cannot edit this row".localized, message: message, preferredStyle: .alert)
		ua.addAction(UIAlertAction(title: "Dismiss".localized, style: .default, handler: { _ in completion?() }))
		self.present(ua, animated: true)
	}

	/** Rebuild the edit form. */
	private func update() {
		if let schema = self.schema {
			let section = Section()
			let language = QBEAppDelegate.sharedInstance.locale

			for column in schema.columns {
				section.append(TextRow() { tr in
					tr.title = column.name

					if let r = self.row {
						if let v = r[column] {
							tr.value = language.localStringFor(v)
						}
					}

					tr.onChange { _ in
						if let v = tr.value {
							self.changes[column] = Value.string(v)
							self.updateNavigationBar()
						}
					}
				})
			}

			performWithoutAnimation {
				self.form = Form()
				self.form.append(section)
			}

			asyncMain {
				self.form.first?.first?.select(animated: true, scrollPosition: .top)
			}
		}
		else {
			let section = Section()
			section.append(LabelRow() {
				$0.title = "Loading...".localized
			})

			performWithoutAnimation {
				self.form = Form()
				self.form.delegate = self
				self.form.append(section)
			}
		}

		self.updateNavigationBar()
	}

	private func performWithoutAnimation(closureToPerform: () -> Void) {
		UIView.setAnimationsEnabled(false)
		closureToPerform()
		UIView.setAnimationsEnabled(true)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		self.modalPresentationStyle = .formSheet
		self.update()
	}

	private func updateNavigationBar() {
		self.navigationItem.title = ((self.row == nil) ? "Add row" : "Edit row").localized
		self.navigationItem.setRightBarButton(UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.done(_:))), animated: false)

		let revertButton = UIBarButtonItem(barButtonSystemItem: .undo, target: self, action: #selector(self.revert(_:)))
		revertButton.isEnabled = !self.changes.isEmpty

		let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(self.newRow(_:)))
		addButton.isEnabled = (self.mutableData?.canPerformMutation(.insert) ?? false)

		self.navigationItem.leftBarButtonItems = [
			addButton,
			revertButton,
		]

		if UIDevice.current.userInterfaceIdiom == .pad {
			let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(self.apply(_:)))
			saveButton.isEnabled = !self.changes.isEmpty
			self.navigationItem.leftBarButtonItems!.append(saveButton)
		}
	}

	private func popAndPerformMutation(job: Job, callback: @escaping (() -> ())) {
		assertMainThread()

		let schema = self.schema!
		let ids = schema.identifier!
		let md = self.mutableData!

		if let (column, newValue) = changes.popFirst() {
			// Create key set
			let key = ids.mapDictionary { c in
				return (c, self.row![c]!)
			}

			guard let oldValue = self.row![column] else {
				callback()
				return
			}

			let mut = DatasetMutation.update(key: key, column: column, old: oldValue, new: newValue)
			if md.canPerformMutation(mut.kind) {
				md.performMutation(mut, job: job) { result in
					switch result {
					case .failure(let e):
						asyncMain {
							self.showError(message: e)
							self.update()
						}
						callback()

					case .success():
						asyncMain {
							self.row![column] = newValue
							self.delegate?.editViewController(self, didPerform: mut) {
								asyncMain {
									self.popAndPerformMutation(job: job, callback: callback)
								}
							}
						}
					}
				}
			}
			else {
				asyncMain {
					self.showError(message: String(format: "Cannot perform mutation of value in column '%@'.".localized, column.name))
					callback()
				}
				return
			}
		}
		else {
			callback()
		}
	}

	private func persistChanges(completion: @escaping (() -> ())) {
		assertMainThread()

		let job = Job(.userInitiated)

		if let schema = self.schema, let _ = schema.identifier, let md = self.mutableData {
			if self.row != nil {
				// Updating an existing row
				let changes = self.changes

				if changes.isEmpty {
					completion()
					return
				}

				self.changes = [:]
				self.updateNavigationBar()
				popAndPerformMutation(job: job, callback: completion)
			}
			else {
				// Insert a new row
				if changes.isEmpty {
					completion()
					return
				}

				var r = WarpCore.Row(columns: schema.columns)
				for (column, value) in changes {
					r[column] = value
				}

				let mut = DatasetMutation.insert(row: r)
				md.performMutation(mut, job: job) { result in
					switch result {
					case .success():
						asyncMain {
							self.changes = [:]
							self.row = r
							self.update()
							self.delegate?.editViewController(self, didPerform: mut, completion: completion)
						}

					case .failure(let e):
						asyncMain {
							self.showError(message: e)
							completion()
						}
					}
				}
			}
		}
		else {
			completion()
		}
	}

	override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
		if action == #selector(revert(_:)) {
			return !self.changes.isEmpty
		}
		return super.canPerformAction(action, withSender: sender)
	}

	@IBAction func revert(_ sender: AnyObject?) {
		self.changes = [:]
		self.update()
	}

	@IBAction func newRow(_ sender: AnyObject?) {
		if !self.changes.isEmpty {
			self.persistChanges() {
				if self.changes.isEmpty {
					asyncMain {
						self.newRow(sender)
					}
				}
			}
		}
		else {
			self.row = nil
			self.update()
		}
	}

	@IBAction func apply(_ sender: AnyObject?) {
		assertMainThread()
		persistChanges {}
	}

	@IBAction func done(_ sender: AnyObject?) {
		self.persistChanges {
			asyncMain {
				self.dismiss(animated: true)
			}
		}
	}
}
