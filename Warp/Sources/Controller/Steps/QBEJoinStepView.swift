/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore

class QBEJoinStepView: QBEConfigurableStepViewControllerFor<QBEJoinStep> {
	@IBOutlet var formulaField: NSTextField?

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBEJoinStepView", bundle: nil)
	}
	
	func tabView(_ tabView: NSTabView, didSelectTabViewItem tabViewItem: NSTabViewItem?) {
		updateView()
	}
	
	required init?(coder: NSCoder) {
		fatalError("Should not be called")
	}

	internal override func viewWillAppear() {
		super.viewWillAppear()
		self.formulaField?.stringValue = (step.condition?.toFormula(self.delegate?.locale ?? Language(), topLevel: true) ?? "")
		updateView()
	}
	
	private func updateView() {
		if let f = step.condition {
			let formula = f.toFormula(self.delegate?.locale ?? Language(), topLevel: true)
			if let parsed = Formula(formula: formula, locale: self.delegate?.locale ?? Language()) {
				self.formulaField?.attributedStringValue = parsed.syntaxColoredFormula
			}
		}
	}
	
	@IBAction func updateFromComplexView(_ sender: NSObject) {
		// Set formula
		let oldFormula = step.condition?.toFormula(self.delegate?.locale ?? Language(), topLevel: true) ?? ""
		if let f = self.formulaField?.stringValue {
			if f != oldFormula {
				if let parsed = Formula(formula: f, locale: (self.delegate?.locale ?? Language()))?.root {
					step.condition = parsed
					delegate?.configurableView(self, didChangeConfigurationFor: step)
					updateView()
				}
				else {
					// TODO this should be a bit more informative
					let a = NSAlert()
					a.messageText = NSLocalizedString("The formula you typed is not valid.", comment: "")
					a.alertStyle = NSAlertStyle.warning
					a.beginSheetModal(for: self.view.window!, completionHandler: nil)
				}
			}
		}
	}
	
	override func viewWillDisappear() {
		NotificationCenter.default.removeObserver(self)
	}
}
