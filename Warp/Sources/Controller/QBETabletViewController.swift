import Foundation
import Cocoa


protocol QBETabletViewDelegate: NSObjectProtocol {
	/** Called by the tablet when it wishes to be closed. The return value is true if the tablet should destroy itself. */
	func tabletViewDidClose(view: QBETabletViewController) -> Bool

	/** Indicates that the tablet view has changed its contents in such a way that outside elements may be affected. */
	func tabletViewDidChangeContents(view: QBETabletViewController)

	/** Indicates that the tablet view has selected an object that is configurable, or nil if a non-configurable object
	was selected. */
	func tabletView(view: QBETabletViewController, didSelectConfigurable: QBEConfigurable?, delegate: QBESentenceViewDelegate)
}

class QBETabletViewController: NSViewController {
	var tablet: QBETablet!
	weak var delegate: QBETabletViewDelegate? = nil

	func tabletWasSelected() {
	}

	func tabletWasDeselected() {
	}

	func selectArrow(arrow: QBETabletArrow) {
	}

	@IBAction func closeTablet(sender: AnyObject) {
		self.delegate?.tabletViewDidClose(self)
	}
}