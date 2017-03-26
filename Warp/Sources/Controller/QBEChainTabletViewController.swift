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

class QBEValueConfigurable: NSObject, QBEConfigurable {
	var value: Value

	var locale: Language {
		return QBEAppDelegate.sharedInstance.locale
	}

	init(value: Value) {
		self.value = value
	}

	func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
			QBESentenceLabelToken(locale.localStringFor(self.value))
		])
	}
}

class QBEChangeableValueConfigurable: NSObject, QBEFullyConfigurable {
	var value: Value
	let callback: (Value) -> ()
	var locale: Language {
		return QBEAppDelegate.sharedInstance.locale
	}

	init(value: Value, callback: @escaping (Value) -> ()) {
		self.value = value
		self.callback = callback
	}

	func setSentence(_ sentence: QBESentence) {
		if let text = sentence.tokens.first {
			self.value = locale.valueForLocalString(text.label)
			self.callback(self.value)
		}
		else {
			self.callback(Value.empty)
		}
	}

	func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
				QBESentenceLabelToken(locale.localStringFor(self.value))
		])
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
		if changeable {
			self.delegate?.tabletView(self, didSelectConfigurable: QBEChangeableValueConfigurable(value: value, callback: callback), configureNow: false, delegate: nil)
		}
		else {
			self.delegate?.tabletView(self, didSelectConfigurable: QBEValueConfigurable(value: value), configureNow: false, delegate: nil)
		}
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
