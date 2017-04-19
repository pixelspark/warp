/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Cocoa
import WarpCore

/** Provides a configurable for a single value. If the value is a list, the configurable will provide a token to the
sentence editor for each value. */
class QBEValueConfigurable: NSObject, QBEFullyConfigurable {
	var value: Value
	let isChangeable: Bool
	let callback: (Value) -> ()
	var locale: Language {
		return QBEAppDelegate.sharedInstance.locale
	}

	var isEditable: Bool {
		switch value {
		case .list(_):
			return false

		default:
			return self.isChangeable
		}
	}

	init(value: Value, editable: Bool, callback: @escaping (Value) -> ()) {
		self.value = value
		self.isChangeable = editable
		self.callback = callback
	}

	func setSentence(_ sentence: QBESentence) {
		assert(self.isEditable, "This value is not editable!")
		
		if let text = sentence.tokens.first {
			self.value = locale.valueForLocalString(text.label)
			self.callback(self.value)
		}
		else {
			self.callback(Value.empty)
		}
	}

	func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		switch value {
		case .list(let xs):
			let n = min(6, xs.count)

			var tokens = (0..<n).map { index -> QBESentenceToken in
				let value = xs[index]
				return QBESentenceTextToken(value: locale.localStringFor(value)) { newValue -> Bool in
					var newList = xs
					newList[index] = locale.valueForLocalString(newValue)
					self.value = .list(newList)
					self.callback(self.value)
					return true
				}
			}

			if xs.count > n {
				tokens.append(QBESentenceLabelToken(String(format: "and %d more".localized, xs.count - n)))
			}

			return QBESentence(tokens)

		default:
			return QBESentence([
				QBESentenceLabelToken(locale.localStringFor(self.value))
			])
		}
	}
}

internal class QBEChainTabletViewController: QBETabletViewController, QBEChainViewControllerDelegate, QBESearchable {
	var chainViewController: QBEChainViewController? = nil { didSet { bind() } }

	var supportsSearch: Bool {
		return true
	}

	var searchQuery: String {
		set {
			self.chainViewController?.fulltextSearchQuery = newValue
		}
		get {
			return self.chainViewController?.fulltextSearchQuery ?? ""
		}
	}

	weak var searchDelegate: QBESearchableDelegate? = nil

	override var responder: NSResponder? { return chainViewController }

	override func tabletWasDeselected() {
		self.chainViewController?.selected = false
	}

	override func tabletWasSelected() {
		self.chainViewController?.selected = true
	}

	private func bind() {
		self.chainViewController?.chain = (self.tablet as! QBEChainTablet).chain
		self.chainViewController?.delegate = self
	}

	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		if segue.identifier == "chain" {
			self.chainViewController = segue.destinationController as? QBEChainViewController
		}
	}

	override func selectArrow(_ arrow: QBETabletArrow) {
		if let s = arrow.fromStep, s != self.chainViewController?.currentStep {
			self.chainViewController?.currentStep = s
			self.chainViewController?.calculate()
		}
	}

	override func startEditing() {
		self.chainViewController?.startEditing(self)
	}

	override func startEditingWithIdentifier(_ ids: Set<Column>, callback: (() -> ())? = nil) {
		self.chainViewController?.startEditingWithIdentifier(ids, callback: callback)
	}

	/** Chain view delegate implementation */
	func chainViewDidClose(_ view: QBEChainViewController) -> Bool {
		return self.delegate?.tabletViewDidClose(self) ?? true
	}

	func chainView(_ view: QBEChainViewController, editValue value: Value, changeable: Bool, callback: @escaping (Value) -> ()) {
		self.delegate?.tabletView(self, didSelectConfigurable: QBEValueConfigurable(value: value, editable: changeable, callback: callback), configureNow: false, delegate: nil)
	}

	func chainView(_ view: QBEChainViewController, configureStep step: QBEStep?, necessary: Bool, delegate: QBESentenceViewDelegate) {
		self.delegate?.tabletView(self, didSelectConfigurable:step, configureNow: necessary, delegate: delegate)
	}

	func chainViewDidChangeChain(_ view: QBEChainViewController) {
		self.delegate?.tabletViewDidChangeContents(self)
		self.searchDelegate?.searchableDidChange(self)
	}

	func chainView(_ view: QBEChainViewController, exportChain chain: QBEChain) {
		self.delegate?.tabletView(self, exportObject: chain)
	}
}
