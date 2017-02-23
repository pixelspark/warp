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
	private var columns: OrderedSet<Column> = []
	private var identifiers: Set<Column>? = nil
	private var changes: [Column: Value] = [:]

	/** Start editing a row. When row is nil, the form will allow adding a row. */
	func startEditing(row: WarpCore.Row?, dataset: MutableDataset) {
		assertMainThread()

		self.mutableData = nil
		self.row = nil
		self.columns = []
		self.changes = [:]

		let job = Job(.userInitiated)

		dataset.identifier(job) { result in
			switch result {
			case .success(let identifiers):
				dataset.columns(job) { result in
					switch result {
					case .success(let columns):
						asyncMain {
							self.identifiers = identifiers
							self.mutableData = dataset
							self.row = row
							self.columns = columns
							self.update()
						}

					case .failure(let e):
						asyncMain {
							self.showError(message: e)
						}
					}
				}
			case .failure(let e):
				asyncMain {
					self.showError(message: e)
				}
			}
		}
	}

	private func showError(message: String) {
		assertMainThread()

		let ua = UIAlertController(title: "Cannot edit this row".localized, message: message, preferredStyle: .alert)
		ua.addAction(UIAlertAction(title: "Dismiss".localized, style: .default, handler: nil))
		self.present(ua, animated: true)
	}

	/** Rebuild the edit form. */
	private func update() {
		let section = Section()
		let language = QBEAppDelegate.sharedInstance.locale

		for column in self.columns {
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
		self.updateNavigationBar()

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

	private func updateNavigationBar() {
		self.navigationItem.title = ((self.row == nil) ? "Add row" : "Edit row").localized
		self.navigationItem.setRightBarButton(UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.done(_:))), animated: false)

		let revertButton = UIBarButtonItem(barButtonSystemItem: .undo, target: self, action: #selector(self.revert(_:)))
		revertButton.isEnabled = !self.changes.isEmpty

		let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(self.newRow(_:)))
		addButton.isEnabled = self.row != nil && (self.mutableData?.canPerformMutation(DatasetMutation.insert(row: Row())) ?? false)

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

	private func persistChanges(completion: (() -> ())? = nil) {
		let job = Job(.userInitiated)

		if let ids = self.identifiers, let md = self.mutableData {
			if self.row != nil {
				// Updating an existing row
				var changes = self.changes

				if changes.isEmpty {
					completion?()
					return
				}

				self.changes = [:]
				self.updateNavigationBar()

				func popAndPerformMutation(callback: (() -> ())? = nil) {
					assertMainThread()

					if let (column, newValue) = changes.popFirst() {
						// Create key set
						let key = ids.mapDictionary { c in
							return (c, self.row![c])
						}

						let mut = DatasetMutation.update(key: key, column: column, old: self.row![column], new: newValue)
						if md.canPerformMutation(mut) {
							md.performMutation(mut, job: job) { result in
								switch result {
								case .failure(let e):
									asyncMain {
										self.showError(message: e)
										self.update()
									}
									callback?()

								case .success():
									asyncMain {
										self.row![column] = newValue
										self.delegate?.editViewController(self, didPerform: mut) {
											asyncMain {
												popAndPerformMutation(callback: callback)
											}
										}
									}
								}
							}
						}
						else {
							asyncMain {
								self.showError(message: String(format: "Cannot perform mutation of value in column '%@'.".localized, column.name))
							}
							return
						}
					}
				}
				popAndPerformMutation(callback: completion)
			}
			else {
				// Insert a new row
				if changes.isEmpty {
					completion?()
					return
				}

				var r = WarpCore.Row(columns: self.columns)
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
							completion?()
						}

					case .failure(let e):
						asyncMain {
							self.showError(message: e)
							completion?()
						}
					}
				}
			}
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
		self.changes = [:]
		self.row = nil
		self.update()
	}

	@IBAction func apply(_ sender: AnyObject?) {
		assertMainThread()
		persistChanges()
	}

	@IBAction func done(_ sender: AnyObject?) {
		self.persistChanges {
			asyncMain {
				self.dismiss(animated: true)
			}
		}
	}
}
