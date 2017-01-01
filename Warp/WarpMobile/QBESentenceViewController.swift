import UIKit
import WarpCore

protocol QBESentenceViewControllerDelegate: class {
	func sentenceViewController(_ : QBESentenceViewController, didChangeSentence: QBESentence)
}

class QBESentenceViewController: UIViewController {
	@IBOutlet var stackView: UIStackView!
	weak var delegate: QBESentenceViewControllerDelegate? = nil

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
						field.placeholder = "(tap here to type)".localized
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

			if let token = token as? QBESentenceOptionsToken {
				let uac = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
				token.options.forEach { (k, v) in
					uac.addAction(UIAlertAction(title: v, style: .default, handler: { (act) in
						token.select(k)
						self.delegate?.sentenceViewController(self, didChangeSentence: s)
					}))
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
							options.forEach { v in
								uac.addAction(UIAlertAction(title: v, style: .default, handler: { (act) in
									token.select(v)
									self.delegate?.sentenceViewController(self, didChangeSentence: s)
								}))
							}

							if UIDevice.current.userInterfaceIdiom == .phone {
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
		}
	}
}
