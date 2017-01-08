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

protocol QBEFormulaViewControllerDelegate: class {
	func formula(_ controller: QBEFormulaViewController, didChangeExpression to: Expression)
}

class QBEFormulaViewController: UIViewController, UITextViewDelegate {
	@IBOutlet var textField: UITextView! = nil
	weak var delegate: QBEFormulaViewControllerDelegate? = nil

	var expression: Expression? = nil { didSet {
		if textField != nil {
			self.update()
		}
	} }

	private func update() {
		if let e = self.expression {
			let locale = QBEAppDelegate.sharedInstance.locale
			let formulaString = e.toFormula(locale, topLevel: true)

			if let formula = Formula(formula: formulaString, locale: locale) {
				self.textField.attributedText = formula.syntaxColoredFormula
				return
			}
		}

		self.textField.attributedText = NSAttributedString(string: "")
	}

	override func viewDidLoad() {
		self.update()
	}

	func textViewDidChange(_ textView: UITextView) {
		/*if let f = Formula(formula: textField.text, locale: QBEAppDelegate.sharedInstance.locale) {
			self.expression = f.root
		}*/
	}

	@IBAction func apply(_ sender: AnyObject) {
		if let f = Formula(formula: textField.text, locale: QBEAppDelegate.sharedInstance.locale) {
			self.expression = f.root
			self.delegate?.formula(self, didChangeExpression: f.root)
		}
		self.update()
	}

	@IBAction func done(_ sender: AnyObject) {
		self.apply(sender)
		self.dismiss(animated: true, completion: nil)
	}
}
