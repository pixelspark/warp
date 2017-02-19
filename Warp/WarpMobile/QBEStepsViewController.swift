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

protocol QBEStepsViewControllerDelegate: class {
	func stepsViewController(_ : QBEStepsViewController, didSelectStep: QBEStep?)
	func stepsViewController(_ : QBEStepsViewController, didChangeChain: QBEChain)
}

class QBEStepsViewController: UICollectionViewController, QBEStepsViewCellDelegate, QBEConfigurableFormViewControllerDelegate, UIDocumentPickerDelegate {
	weak var delegate: QBEStepsViewControllerDelegate? = nil

	static let stepsSection = 0
	var chain: QBEChain? { didSet {
		if chain != oldValue {
			self.updateView()
		}
	} }

	var selectedStep: QBEStep? { didSet {
		self.updateSelection()
	} }

	override func numberOfSections(in collectionView: UICollectionView) -> Int {
		return 1;
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		self.collectionView?.contentInset = UIEdgeInsets()
		self.automaticallyAdjustsScrollViewInsets = false
		self.edgesForExtendedLayout = []
	}

	override func viewWillAppear(_ animated: Bool) {
		self.collectionView?.allowsSelection = true
		self.collectionView?.allowsMultipleSelection = false
		super.viewWillAppear(animated)
		self.updateView()
	}

	func refresh() {
		self.collectionView?.reloadData()
		self.updateSelection()
	}

	private func updateSelection() {
		if let cs = self.selectedStep, let idx = self.chain?.steps.index(of: cs) {
			self.collectionView?.selectItem(at: IndexPath(indexes: [QBEStepsViewController.stepsSection, idx]), animated: false, scrollPosition: .centeredHorizontally)
		}
	}

	private func updateView() {
		UIView.animate(withDuration: 0.2) {
			self.collectionView?.reloadData()
			if let cs = self.selectedStep, let idx = self.chain?.steps.index(of: cs) {
				self.collectionView?.selectItem(at: IndexPath(indexes: [QBEStepsViewController.stepsSection, idx]), animated: false, scrollPosition: .centeredHorizontally)
			}
		}
	}

	override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		if section == QBEStepsViewController.stepsSection {
			return (self.chain?.steps.count ?? 0) + 1
		}
		fatalError("Unreachable")
	}

	override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		if indexPath.section == QBEStepsViewController.stepsSection {
			if let c = chain, indexPath.row < c.steps.count {
				let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "stepCell", for: indexPath) as! QBEStepsViewCell
				if indexPath.row == 0 {
					cell.leftArrowImageView?.isHidden = true
				}
				cell.delegate = self
				cell.step = chain?.steps[indexPath.row]
				return cell
			}
			else {
				return collectionView.dequeueReusableCell(withReuseIdentifier: "addStepCell", for: indexPath)
			}
		}
		else {
			fatalError("Unreachable")
		}
	}

	func stepsViewCell(_: QBEStepsViewCell, removeStep step: QBEStep) {
		if let c = chain {
			c.remove(step: step)
			self.updateView()
			self.delegate?.stepsViewController(self, didChangeChain: c)

		}
	}

	func stepsViewCell(_: QBEStepsViewCell, configureStep step: QBEStep) {
		if let step = step as? QBEFormConfigurableStep, let c = chain {
			self.configure(step: step) {
				self.delegate?.stepsViewController(self, didChangeChain: c)
			}
		}
	}

	func configurableFormViewController(_: QBEConfigurableFormViewController, hasChangedConfigurable: QBEFormConfigurable) {
		if let c = chain {
			self.delegate?.stepsViewController(self, didChangeChain: c)
		}
	}

	private func configure(step: QBEFormConfigurableStep, completion: (() -> ())? = nil) {
		let configureForm = QBEConfigurableFormViewController()
		configureForm.configurable = step
		configureForm.delegate = self

		let nav = UINavigationController(rootViewController: configureForm)
		nav.modalPresentationStyle = .formSheet
		self.present(nav, animated: true, completion: completion)
	}

	private func add(step: QBEStep, configure: Bool = true) {
		if let c = chain {
			if configure, let cf = step as? QBEFormConfigurableStep, cf.shouldConfigure {
				self.configure(step: cf) {
					self.add(step: step, configure: false)
				}
			}
			else {
				c.insertStep(step, afterStep: c.head)
				self.updateView()
				self.delegate?.stepsViewController(self, didChangeChain: c)
				self.delegate?.stepsViewController(self, didSelectStep: step)
			}
		}
	}

	private func addFileStep() {
		let picker = UIDocumentPickerViewController(documentTypes: QBEFactory.sharedInstance.supportedFileTypes, in: .open)
		picker.delegate = self
		self.present(picker, animated: true, completion: nil)
	}

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
		if let reader = QBEFactory.sharedInstance.stepForReadingFile(url) {
			self.add(step: reader)
		}
		else {
			let uac = UIAlertController(title: "Could not open file".localized, message: "This file type is not supported.".localized, preferredStyle: .alert)
			uac.addAction(UIAlertAction(title: "Dismiss".localized, style: .cancel, handler: nil))
			self.present(uac, animated: true, completion: nil)
		}
	}

	private func showAddStepMenu(at frame: CGRect, in view: UIView) {
		let uac = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

		if self.chain!.head == nil {
			// Show steps that can be first
			uac.addAction(UIAlertAction(title: "Generate a sequence".localized, style: .default, handler: { act in
				self.add(step: QBESequencerStep(pattern: "[a-z]{2}", column: Column("Value".localized)))
			}))

			uac.addAction(UIAlertAction(title: "Load data from RethinkDB".localized, style: .default, handler: { act in
				self.add(step: QBERethinkSourceStep())
			}))

			uac.addAction(UIAlertAction(title: "Load data from PostgreSQL".localized, style: .default, handler: { act in
				self.add(step: QBEPostgresSourceStep())
			}))

			uac.addAction(UIAlertAction(title: "Load data from MySQL".localized, style: .default, handler: { act in
				self.add(step: QBEMySQLSourceStep())
			}))

			uac.addAction(UIAlertAction(title: "Load data from a file".localized, style: .default, handler: { act in
				self.addFileStep()
			}))
		}
		else {
			let actions: [UIAlertAction] = [
				UIAlertAction(title: "Limit the number of rows".localized, style: .default, handler: { act in
					self.add(step: QBELimitStep())
				}),

				UIAlertAction(title: "Make columnar".localized, style: .default, handler: { act in
					self.add(step: QBEFlattenStep())
				}),

				UIAlertAction(title: "Remove duplicate rows".localized, style: .default, handler: { act in
					self.add(step: QBEDistinctStep())
				}),

				UIAlertAction(title: "Randomly select rows".localized, style: .default, handler: { act in
					self.add(step: QBERandomStep())
				}),

				UIAlertAction(title: "Search for text".localized, style: .default, handler: { act in
					self.add(step: QBESearchStep())
				}),

				UIAlertAction(title: "Skip the first rows".localized, style: .default, handler: { act in
					self.add(step: QBEOffsetStep())
				}),

				UIAlertAction(title: "Select column(s)".localized, style: .default, handler: { act in
					self.add(step: QBEColumnsStep())
				}),

				UIAlertAction(title: "Switch rows/columns".localized, style: .default, handler: { act in
					self.add(step: QBETransposeStep())
				}),

				UIAlertAction(title: "Calculate a new column".localized, style: .default, handler: { act in
					self.add(step: QBECalculateStep(previous: nil, targetColumn: Column("New column".localized), function: Comparison(first: Literal(Value(1)), second: Literal(Value(1)), type: .addition)))
				}),

				UIAlertAction(title: "Load related data".localized, style: .default, handler: { act in
					self.showJoinDataMenu(at: frame, in: view)
				})
			]

			actions.sorted(by: { $0.title! < $1.title! }).forEach { item in
				uac.addAction(item)
			}
		}

		uac.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel, handler: { act in
		}))

		uac.popoverPresentationController?.sourceView = view
		uac.popoverPresentationController?.sourceRect = frame
		self.present(uac, animated: true, completion: nil)
	}

	private func showJoinDataMenu(at frame: CGRect, in view: UIView){
		if let c = chain, let head = c.head {
			let job = Job(.userInitiated)
			head.related(job: job) { result in
				switch result {
				case .success(let related):
					asyncMain {
						let uac = UIAlertController(title: "Load related data".localized, message: (related.count > 0) ? nil : "Could not find related data sets".localized, preferredStyle: .actionSheet)

						if related.count > 0 {
							for relatedData in related {
								switch relatedData {
								case .joinable(step: let step, type: let type, condition: let condition):
									let title = step.sentence(QBEAppDelegate.sharedInstance.locale, variant: .read).stringValue
									uac.addAction(UIAlertAction(title: title, style: .default, handler: { action in
										let js = QBEJoinStep()
										js.condition = condition
										js.joinType = type
										js.right = QBEChain(head: step)
										self.add(step: js)
									}))
								}
							}
						}

						uac.addAction(UIAlertAction(title: "Custom...".localized, style: .default, handler: { action in
							let js = QBEJoinStep()
							js.condition = Literal(Value(false))
							js.joinType = .leftJoin
							js.right = QBEChain(head: nil)
							self.add(step: js)
						}))

						uac.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel, handler: nil))
						uac.popoverPresentationController?.sourceView = view
						uac.popoverPresentationController?.sourceRect = frame
						self.present(uac, animated: true, completion: nil)
					}


				case .failure(let e):
					asyncMain {
						let uac = UIAlertController(title: "Could not find related data sets".localized, message: e, preferredStyle: .alert)
						uac.addAction(UIAlertAction(title: "Dismiss".localized, style: .cancel, handler: nil))
						uac.popoverPresentationController?.sourceView = view
						uac.popoverPresentationController?.sourceRect = frame
						self.present(uac, animated: true, completion: nil)
					}
				}
			}
		}
	}

	override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		if indexPath.section == QBEStepsViewController.stepsSection {
			if let c = chain, indexPath.row < c.steps.count {
				let step = c.steps[indexPath.row]
				self.selectedStep = step
				self.delegate?.stepsViewController(self, didSelectStep: step)
			}
			else {
				if let c = chain {
					asyncMain {
						if c.head != nil {
							collectionView.selectItem(at: IndexPath(indexes: [indexPath.section, c.steps.count - 1]), animated: false, scrollPosition: .centeredHorizontally)
						}
					}
					
					// Add popover
					if let cell = collectionView.cellForItem(at: indexPath) {
						self.showAddStepMenu(at: cell.frame, in: collectionView)
					}
				}
			}
		}
	}
}

protocol QBEStepsViewCellDelegate: class {
	func stepsViewCell(_ : QBEStepsViewCell, removeStep: QBEStep)
	func stepsViewCell(_ : QBEStepsViewCell, configureStep: QBEStep)
}

class QBEStepsViewCell: UICollectionViewCell {
	@IBOutlet var leftArrowImageView: UIImageView? = nil
	@IBOutlet var imageView: UIImageView? = nil
	weak var delegate: QBEStepsViewCellDelegate? = nil
	var step: QBEStep? = nil {
		didSet {
			self.updateView()
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		self.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(self.longPress(_:))))
	}

	override func prepareForReuse() {
		self.imageView?.image = nil
		self.step = nil
		self.isSelected = false
		self.isHighlighted = false
		self.leftArrowImageView?.isHidden = false
	}

	override var isSelected: Bool {
		didSet {
			self.updateView()
		}
	}

	override var isHighlighted: Bool {
		didSet {
			self.updateView()
		}
	}

	@IBAction func longPress(_ sender: UILongPressGestureRecognizer) {
		if sender.state == .began {
			if self.becomeFirstResponder() {
				self.showMenu()
			}
		}
	}

	private func showMenu() {
		let mc = UIMenuController.shared

		mc.menuItems = [
			UIMenuItem(title: "Remove".localized, action: #selector(QBEStepsViewCell.removeStep(_:))),
		]

		if step is QBEFormConfigurable {
			mc.menuItems!.append(UIMenuItem(title: "Settings".localized, action: #selector(QBEStepsViewCell.configureStep(_:))))
		}

		mc.setTargetRect(self.bounds, in: self)
		mc.setMenuVisible(true, animated: true)
	}

	override var canBecomeFirstResponder: Bool { return true }

	override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
		if action == #selector(QBEStepsViewCell.removeStep(_:)) {
			return true
		}
		else if action == #selector(QBEStepsViewCell.configureStep(_:)) {
			return step is QBEFormConfigurableStep
		}
		return false
	}

	@IBAction func removeStep(_ sender: NSObject) {
		if let step = step {
			self.delegate?.stepsViewCell(self, removeStep: step)
		}
	}

	@IBAction func configureStep(_ sender: NSObject) {
		if let step = step {
			self.delegate?.stepsViewCell(self, configureStep: step)
		}
	}

	private func updateView() {
		self.contentView.backgroundColor = self.isHighlighted ? UIColor.blue :  (self.isSelected ? UIColor(white: 0.95, alpha: 1.0)  : UIColor.clear)
		if let s = step, let imageName = QBEFactory.sharedInstance.iconForStep(s), let image = UIImage(named: imageName) {
			self.imageView?.image = image
		}
		else {
			self.imageView?.image = nil
		}
	}
}
