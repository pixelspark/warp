import UIKit
import WarpCore

protocol QBEStepsViewControllerDelegate: class {
	func stepsViewController(_ : QBEStepsViewController, didSelectStep: QBEStep?)
	func stepsViewController(_ : QBEStepsViewController, didChangeChain: QBEChain)
}

class QBEStepsViewController: UICollectionViewController, QBEStepsViewCellDelegate, QBEConfigurableFormViewControllerDelegate {
	weak var delegate: QBEStepsViewControllerDelegate? = nil

	static let stepsSection = 0
	var chain: QBEChain? { didSet {
		if chain != oldValue {
			self.updateView()
		}
	} }

	var selectedStep: QBEStep? { didSet {
		if let cs = self.selectedStep, let idx = self.chain?.steps.index(of: cs) {
			self.collectionView?.selectItem(at: IndexPath(indexes: [QBEStepsViewController.stepsSection, idx]), animated: false, scrollPosition: .centeredHorizontally)
		}
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
		nav.modalPresentationStyle = .pageSheet
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

	override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		if indexPath.section == QBEStepsViewController.stepsSection {
			if let c = chain, indexPath.row < c.steps.count {
				let step = c.steps[indexPath.row]
				self.selectedStep = step
				self.delegate?.stepsViewController(self, didSelectStep: step)
			}
			else {
				if let c = chain {
					// Add popover
					if let cell = collectionView.cellForItem(at: indexPath) {
						let uac = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

						if c.head == nil {
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
						}
						else {
							uac.addAction(UIAlertAction(title: "Limit the number of rows".localized, style: .default, handler: { act in
								self.add(step: QBELimitStep())
							}))

							uac.addAction(UIAlertAction(title: "Remove duplicate rows".localized, style: .default, handler: { act in
								self.add(step: QBEDistinctStep())
							}))

							uac.addAction(UIAlertAction(title: "Randomly select rows".localized, style: .default, handler: { act in
								self.add(step: QBERandomStep())
							}))

							uac.addAction(UIAlertAction(title: "Search for text".localized, style: .default, handler: { act in
								self.add(step: QBESearchStep())
							}))

							uac.addAction(UIAlertAction(title: "Skip the first rows".localized, style: .default, handler: { act in
								self.add(step: QBEOffsetStep())
							}))

							uac.addAction(UIAlertAction(title: "Switch rows/columns".localized, style: .default, handler: { act in
								self.add(step: QBETransposeStep())
							}))
						}

						if UIDevice.current.userInterfaceIdiom == .phone {
							uac.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel, handler: { act in
							}))
						}

						uac.popoverPresentationController?.sourceView = self.collectionView
						uac.popoverPresentationController?.sourceRect = cell.frame
						self.present(uac, animated: true, completion: nil)
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
			UIMenuItem(title: "Settings".localized, action: #selector(QBEStepsViewCell.configureStep(_:))),
		]

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
