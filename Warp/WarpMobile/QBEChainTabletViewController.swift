import UIKit
import WarpCore

class QBEChainTabletViewController: UIViewController, QBEStepsViewControllerDelegate, QBESentenceViewControllerDelegate, QBEConfigurableFormViewControllerDelegate {
	private var stepsViewController: QBEStepsViewController? = nil
	private var sentenceViewController: QBESentenceViewController? = nil
	private var dataViewController: QBEDataViewController? = nil

	@IBOutlet var fullDataToggle: UIBarButtonItem! = nil
	@IBOutlet var configureToggle: UIBarButtonItem! = nil

	var tablet: QBEChainTablet? = nil { didSet {
		if tablet != oldValue {
			self.currentStep = tablet?.chain.head
			self.updateView()
		}
	} }

	var currentStep: QBEStep? = nil { didSet {
		self.stepsViewController?.selectedStep = currentStep
	} }

	var currentData: Future<Fallible<Dataset>>? = nil
	var useFullData = false

	override var canBecomeFirstResponder: Bool {
		return true
	}

	private func refreshData(fullData: Bool = false) {
		self.currentData?.cancel()
		self.useFullData = fullData
		self.updateToolbarItems()

		currentData = Future<Fallible<Dataset>>({ [weak self] (job: Job, callback: @escaping (Fallible<Dataset>) -> ()) -> Void in
			if let s = self?.currentStep {
				if fullData {
					s.fullDataset(job, callback: callback)
				}
				else {
					s.exampleDataset(job, maxInputRows: 100, maxOutputRows: 100, callback: callback)
				}
			}
			else {
				callback(.success(StreamDataset(source: ErrorStream("Click + to add data".localized))))
			}
		})

		self.dataViewController?.data = nil
		currentData?.get(Job(.userInitiated), { (result) in
			asyncMain {
				switch result {
				case .success(let data):
					self.dataViewController?.data = data

				case .failure(let e):
					self.dataViewController?.data = StreamDataset(source: ErrorStream(e))
				}
			}
		})
	}

	override func viewWillAppear(_ animated: Bool) {
		self.currentStep = tablet?.chain.head
		self.updateView()
		super.viewWillAppear(animated)
	}

	func configurableFormViewController(_: QBEConfigurableFormViewController, hasChangedConfigurable: QBEFormConfigurable) {
		self.updateView()
	}

	@IBAction func configureStep(_ sender: AnyObject) {
		if let cs = currentStep as? QBEFormConfigurable {
			let configureForm = QBEConfigurableFormViewController()
			configureForm.configurable = cs
			configureForm.delegate = self

			let nav = UINavigationController(rootViewController: configureForm)
			nav.modalPresentationStyle = .pageSheet
			self.present(nav, animated: true, completion: nil)
		}
	}

	private func updateToolbarItems() {
		self.fullDataToggle.image = UIImage(named: self.useFullData ? "BigIcon" : "SmallIcon")
		self.configureToggle.isEnabled = self.currentStep is QBEFormConfigurable
	}

	private func updateView() {
		self.stepsViewController?.chain = self.tablet?.chain
		self.stepsViewController?.selectedStep = currentStep
		self.sentenceViewController?.sentence = currentStep?.sentence(QBEAppDelegate.sharedInstance.locale, variant: .read)
		self.refreshData()
		self.updateToolbarItems()
	}

	@IBAction func toggleFullDataset(_ sender: AnyObject) {
		self.refreshData(fullData: !useFullData)
		self.updateToolbarItems()
	}

	func stepsViewController(_: QBEStepsViewController, didSelectStep step: QBEStep?) {
		self.currentStep = step
		self.updateView()
		self.refreshData()
	}

	func sentenceViewController(_: QBESentenceViewController, didChangeSentence: QBESentence) {
		self.updateView()
		self.refreshData()
		self.tablet?.document?.updateChangeCount(.done)
	}

	func stepsViewController(_: QBEStepsViewController, didChangeChain chain: QBEChain) {
		if let cs = self.currentStep {
			if !chain.steps.contains(cs) {
				self.currentStep = chain.head
			}
		}
		self.updateView()
		self.tablet?.document?.updateChangeCount(.done)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "steps", let dest = segue.destination as? QBEStepsViewController {
			self.stepsViewController = dest
			dest.delegate = self
		}
		else if segue.identifier == "sentence", let dest = segue.destination as? QBESentenceViewController {
			self.sentenceViewController = dest
			dest.delegate = self
		}
		else if segue.identifier == "data", let dest = segue.destination as? QBEDataViewController {
			self.dataViewController = dest
		}
		else {
			fatalError("Unreachable")
		}
	}
}
