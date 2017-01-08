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

class QBEChainTabletViewController: UIViewController, QBEStepsViewControllerDelegate, QBESentenceViewControllerDelegate, QBEConfigurableFormViewControllerDelegate, QBEExportViewControllerDelegate, QBEDataViewControllerDelegate {
	private var stepsViewController: QBEStepsViewController? = nil
	private var sentenceViewController: QBESentenceViewController? = nil
	private var dataViewController: QBEDataViewController? = nil

	@IBOutlet var fullDataToggle: UIBarButtonItem! = nil
	@IBOutlet var configureToggle: UIBarButtonItem! = nil
	private var shareButton: UIBarButtonItem? = nil

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
					s.exampleDataset(job, maxInputRows: 10000, maxOutputRows: 100, callback: callback)
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

	func exportViewController(_: QBEExportViewController, shareFileAt url: URL, callback: @escaping () -> ()) {
		let sc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
		sc.modalPresentationStyle = .popover
		sc.popoverPresentationController?.barButtonItem = self.shareButton
		sc.completionWithItemsHandler = { _,_,_,_ in
			callback()
		}
		self.present(sc, animated: false)
	}

	@IBAction func share(_ sender: UIBarButtonItem) {
		self.shareButton = sender // UGLY
		let exportForm = QBEExportViewController()
		exportForm.source = self.tablet!.chain
		exportForm.delegate = self
		let nav = UINavigationController(rootViewController: exportForm)

		if UIDevice.current.userInterfaceIdiom == .pad {
			nav.modalPresentationStyle = .popover
			nav.popoverPresentationController?.barButtonItem = sender
		}
		self.present(nav, animated: true, completion: nil)
	}

	@IBAction func configureStep(_ sender: AnyObject) {
		if let cs = currentStep as? QBEFormConfigurable {
			let configureForm = QBEConfigurableFormViewController()
			configureForm.configurable = cs
			configureForm.delegate = self

			let nav = UINavigationController(rootViewController: configureForm)

			if UIDevice.current.userInterfaceIdiom == .pad {
				nav.modalPresentationStyle = .popover
				nav.popoverPresentationController?.barButtonItem = self.configureToggle
			}
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

	func dataView(_ controller: QBEDataViewController, filter column: Column, for value: Value) {
		if let fs = self.currentStep as? QBEFilterSetStep {
			if let currentValues = fs.filterSet[column] {
				var nv = currentValues.selectedValues
				nv.insert(value)
				fs.filterSet[column] = FilterSet(values: nv)
			}
			else {
				fs.filterSet[column] = FilterSet(values: [value])
			}
			self.updateView()
			self.refreshData()
			self.tablet?.document?.updateChangeCount(.done)
		}
		else {
			let fs = QBEFilterSetStep()
			fs.filterSet[column] = FilterSet(values: [value])
			self.add(step: fs)
		}
	}

	private func add(step: QBEStep) {
		if let c = tablet?.chain {
			let after = currentStep ?? c.head

			// Can we merge?
			if let a = after {
				let previous = a.previous
				switch step.mergeWith(a) {
				case .advised(let merged), .possible(let merged):
					c.remove(step: a)
					c.insertStep(merged, afterStep: previous)
					self.currentStep = merged

				case .cancels:
					c.remove(step: a)
					self.currentStep = previous

				case .impossible:
					c.insertStep(step, afterStep: a)
					self.currentStep = step
					break
				}
			}
			else {
				c.insertStep(step, afterStep: nil)
				self.currentStep = step
			}


			self.tablet?.document?.updateChangeCount(.done)
			self.stepsViewController?.refresh()
			self.updateView()
			self.refreshData()
		}
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
			dest.delegate = self
		}
		else {
			fatalError("Unreachable")
		}
	}
}
