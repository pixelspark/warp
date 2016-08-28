import Foundation
import Cocoa


protocol QBETabletViewDelegate: NSObjectProtocol {
	/** Called by the tablet when it wishes to be closed. The return value is true if the tablet should destroy itself. */
	@discardableResult func tabletViewDidClose(_ view: QBETabletViewController) -> Bool

	/** Indicates that the tablet view has changed its contents in such a way that outside elements may be affected. */
	func tabletViewDidChangeContents(_ view: QBETabletViewController)

	/** Indicates that the tablet view has selected an object that is configurable, or nil if a non-configurable object
	was selected. */
	func tabletView(_ view: QBETabletViewController, didSelectConfigurable: QBEConfigurable?, configureNow: Bool, delegate: QBESentenceViewDelegate?)

	/** Called when the tablet wants to export an object. This is equivalent to attempting to drag out an object (e.g.
	a chain) from an outlet view onto the workspace in which the tablet is contained. */
	func tabletView(_ view: QBETabletViewController, exportObject: NSObject)
}

class QBETabletViewController: NSViewController {
	var tablet: QBETablet!
	weak var delegate: QBETabletViewDelegate? = nil

	var responder: NSResponder? { return self }

	func tabletWasSelected() {
	}

	func tabletWasDeselected() {
	}

	func selectArrow(_ arrow: QBETabletArrow) {
	}

	func startEditing() {
	}

	@IBAction func closeTablet(_ sender: AnyObject) {
		self.delegate?.tabletViewDidClose(self)
	}
}
