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
import Eureka

protocol QBESentenceViewControllerDelegate: class {
	func sentenceViewController(_ : QBESentenceViewController, didChangeSentence: QBESentence)
}

fileprivate protocol QBEOptionsViewControllerDelegate: class {
	func optionsView(_ controller: QBEOptionsViewController, changedSelection to: Set<Value>)
}

fileprivate class QBEOptionsViewController: FormViewController {
	var selected: Set<Value> = [] {
		didSet {
			refresh()
		}
	}

	var options: [Value] = [] { didSet {
		loading = false
		refresh()
	} }

	var loading: Bool = true

	var delegate: QBEOptionsViewControllerDelegate? = nil

	override func viewDidLoad() {
		super.viewDidLoad()
		self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(QBEOptionsViewController.cancel(_:)))

		self.navigationItem.leftBarButtonItems = [
			UIBarButtonItem(title: "All".localized, style: .plain, target: self, action: #selector(self.selectAll(_:))),
			UIBarButtonItem(title: "None".localized, style: .plain, target: self, action: #selector(self.selectNone(_:)))
		]

		self.refresh()
	}

	@IBAction override func selectAll(_ sender: Any?) {
		self.selected = Set(self.options)
		self.delegate?.optionsView(self, changedSelection: self.selected)
		refresh()
	}

	@IBAction func selectNone(_ sender: Any?) {
		self.selected = []
		self.delegate?.optionsView(self, changedSelection: self.selected)
		refresh()
	}

	private func refresh() {
		if loading {
			let f = Form()
			let s = Section()
			s.append(LabelRow() {
				$0.title = "Loading...".localized
			})
			f.append(s)
			form = f
		}
		else {
			let section = Section()
			let locale = QBEAppDelegate.sharedInstance.locale!

			options.sorted(by: { locale.localStringFor($0) < locale.localStringFor($1) }).forEach { value in
				let cr = CheckRow()
				cr.title = locale.localStringFor(value)
				cr.value = self.selected.contains(value)
				cr.onChange { cr in
					if self.selected.contains(value) {
						self.selected.remove(value)
						cr.value = false
					}
					else {
						self.selected.insert(value)
						cr.value = true
					}
					self.delegate?.optionsView(self, changedSelection: self.selected)
				}
				section.append(cr)
			}

			let f = Form()
			f.append(section)
			form = f
		}
	}

	@IBAction func cancel(_ sender: AnyObject) {
		self.dismiss(animated: true, completion: nil)
	}
}

class QBESentenceViewController: UIViewController, UIDocumentPickerDelegate, QBEFormulaViewControllerDelegate {
	@IBOutlet var stackView: UIStackView!
	weak var delegate: QBESentenceViewControllerDelegate? = nil
	private var editingToken: QBESentenceToken? = nil

	var sentence: QBESentence? { didSet {
		if let _ = self.stackView {
			self.updateView()
		}
	} }

	override func viewDidLoad() {
		self.updateView()
	}

	override func viewWillAppear(_ animated: Bool) {
		self.updateView()
	}

	private func updateView() {
		asyncMain {
			let trans = CATransition()
			trans.duration = 0.3
			trans.type = kCATransitionPush;
			trans.subtype = kCATransitionFromBottom;
			self.view.layer.add(trans, forKey: "push")

			let views = self.stackView.arrangedSubviews
			views.forEach { self.stackView!.removeArrangedSubview($0); }
			views.forEach { $0.removeFromSuperview() }
			assert(self.stackView.arrangedSubviews.isEmpty)
			self.stackView.invalidateIntrinsicContentSize()
			self.stackView.setNeedsLayout()

			if let s = self.sentence {
				let views: [UIView] = s.tokens.enumerated().map { (idx, token) in
					let view: UIView
					if let x = token as? QBESentenceLabelToken {
						let label = UILabel()
						label.text = x.label
						label.textColor = UIColor.darkGray
						label.sizeToFit()
						view = label
					}
					else if let x = token as? QBESentenceTextToken {
						let field = UITextField()
						field.text = x.label
						field.placeholder = x.label.isEmpty ? "(tap here to type)".localized : "...".localized
						field.textColor = UIColor.blue
						field.autocapitalizationType = .none

						field.addTarget(self, action: #selector(self.textFieldChanged(_:)), for: .editingChanged)
						field.addTarget(self, action: #selector(self.textFieldEndEditing(_:)), for: .editingDidEnd)
						field.addTarget(self, action: #selector(self.textFieldEndEditing(_:)), for: .editingDidEndOnExit)
						field.sizeToFit()
						view = field
					}
					else {
						let title = token.label.isEmpty ? "(select...)".localized : token.label
						let button = UIButton(type: UIButtonType.custom)
						button.setTitle(title, for: .normal)
						button.setTitleColor(UIColor.blue, for: .normal)
						button.addTarget(self, action: #selector(self.tokenTapped(_:)), for: .touchUpInside)
						view = button
					}
					
					view.tag = idx
					return view
				}

				views.forEach {
					$0.sizeToFit()
					self.stackView.addArrangedSubview($0)
				}
				self.stackView.invalidateIntrinsicContentSize()
				self.stackView.setNeedsLayout()
				self.stackView.layoutIfNeeded()
			}
		}
	}

	@IBAction func textFieldEndEditing(_ sender: UITextField) {
		if let s = self.sentence, sender.tag < s.tokens.count, let token = s.tokens[sender.tag] as? QBESentenceTextToken {
			if !token.change(sender.text ?? "") {
				sender.text = token.label
				self.textFieldChanged(sender)
			}
			else {
				self.delegate?.sentenceViewController(self, didChangeSentence: s)
			}
		}
	}

	@IBAction func textFieldChanged(_ sender: UITextField) {
		self.stackView.setNeedsUpdateConstraints()
		sender.invalidateIntrinsicContentSize()
		sender.sizeToFit()

		UIView.animate(withDuration: 0.1) { 
			self.stackView.updateConstraints()
		}
	}

	@IBAction func tokenTapped(_ sender: UIView) {
		if let s = self.sentence, sender.tag < s.tokens.count {
			let token = s.tokens[sender.tag]
			self.editingToken = token

			if let token = token as? QBESentenceOptionsToken {
				let uac = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

				if token.options.count == 0 {
					uac.message = "There are currently no options available.".localized

					uac.addAction(UIAlertAction(title: "OK".localized, style: .cancel, handler: nil))
				}
				else {
					var sortedTokens = OrderedDictionary(dictionaryInAnyOrder: token.options)
					sortedTokens.sortPairsInPlace({ (a, b) -> Bool in
						return a.value < b.value
					})

					sortedTokens.forEach { (k, v) in
						uac.addAction(UIAlertAction(title: v, style: .default, handler: { (act) in
							token.select(k)
							self.delegate?.sentenceViewController(self, didChangeSentence: s)
						}))
					}

					uac.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel, handler: nil))
				}

				uac.popoverPresentationController?.sourceView = sender
				uac.popoverPresentationController?.sourceRect = sender.bounds
				self.present(uac, animated: true, completion: nil)
			}
			else if let token = token as? QBESentenceDynamicOptionsToken {
				let uac = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
				token.optionsProvider { result in
					asyncMain {
						switch result {
						case .success(let options):
							if options.count == 0 {
								uac.message = "There are currently no options available.".localized
								uac.addAction(UIAlertAction(title: "OK".localized, style: .cancel, handler: nil))
							}
							else {
								options.sorted().forEach { v in
									uac.addAction(UIAlertAction(title: v, style: .default, handler: { (act) in
										token.select(v)
										self.delegate?.sentenceViewController(self, didChangeSentence: s)
									}))
								}
								uac.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel, handler: nil))
							}

							uac.popoverPresentationController?.sourceView = sender
							uac.popoverPresentationController?.sourceRect = sender.bounds
							self.present(uac, animated: true, completion: nil)

						case .failure(let e):
							let alert = UIAlertController(title: "Could not load".localized, message: e, preferredStyle: .alert)
							let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default) { action in
							}
							alert.addAction(alertAction)
							self.present(alert, animated: true, completion: nil)
						}
					}
				}
			}
			else if let token = token as? QBESentenceSetToken {
				let oc = QBEOptionsViewController(nibName: nil, bundle: nil)
				oc.selected = Set(token.value.map { return Value($0) })

				token.provider { result in
					asyncMain {
						switch result {
						case .failure(let e):
							let alert = UIAlertController(title: "Could not load".localized, message: e, preferredStyle: .alert)
							let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default)
							alert.addAction(alertAction)
							self.present(alert, animated: true, completion: nil)

						case .success(let options):
							oc.options = options.map { return Value($0) }
						}
					}
				}

				class TokenOptionsDelegate: QBEOptionsViewControllerDelegate {
					let token: QBESentenceSetToken
					var view: QBESentenceViewController!

					init(_ token: QBESentenceSetToken, view: QBESentenceViewController) {
						self.token = token
						self.view = view
					}

					func optionsView(_ controller: QBEOptionsViewController, changedSelection to: Set<Value>) {
						self.token.select(Set(to.map { return $0.stringValue! }))
						view.delegate?.sentenceViewController(view, didChangeSentence: view.sentence!)
					}
				}

				let dlg = TokenOptionsDelegate(token, view: self)
				oc.delegate = dlg
				let nav = UINavigationController(rootViewController: oc)
				nav.preferredContentSize = CGSize(width: 320, height: 320)
				nav.modalPresentationStyle = .popover
				nav.popoverPresentationController?.sourceView = sender
				nav.popoverPresentationController?.sourceRect = sender.bounds
				self.present(nav, animated: true)
			}
			else if let token = token as? QBESentenceFileToken {
				let picker = UIDocumentPickerViewController(documentTypes: token.allowedFileTypes, in: .open)
				picker.delegate = self
				self.present(picker, animated: true, completion: nil)
			}
			else if let token = token as? QBESentenceFormulaToken {
				let fc = self.storyboard?.instantiateViewController(withIdentifier: "formula") as! QBEFormulaViewController
				fc.expression = token.expression
				fc.delegate = self
				let nav = UINavigationController(rootViewController: fc)
				nav.preferredContentSize = CGSize(width: 640, height: 240)
				nav.modalPresentationStyle = .popover
				nav.popoverPresentationController?.sourceView = sender
				nav.popoverPresentationController?.sourceRect = sender.bounds
				self.present(nav, animated: true)
			}
			else {
				let uac = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
				uac.message = "This setting cannot be changed on iOS. Use the Mac version of Warp to change it.".localized
				uac.addAction(UIAlertAction(title: "OK".localized, style: .cancel, handler: nil))
				uac.popoverPresentationController?.sourceView = sender
				uac.popoverPresentationController?.sourceRect = sender.bounds
				self.present(uac, animated: true, completion: nil)
			}
		}
	}

	func formula(_ controller: QBEFormulaViewController, didChangeExpression to: Expression) {
		if let token = self.editingToken as? QBESentenceFormulaToken {
			token.change(to)
			self.delegate?.sentenceViewController(self, didChangeSentence: self.sentence!)
		}
	}

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
		if let token = self.editingToken as? QBESentenceFileToken {
			token.change(QBEFileReference.absolute(url))
			self.editingToken = nil
			self.delegate?.sentenceViewController(self, didChangeSentence: self.sentence!)
		}
	}
}
