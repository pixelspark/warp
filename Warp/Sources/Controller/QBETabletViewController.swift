/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import Cocoa
import WarpCore

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

@objc protocol QBESearchableDelegate {
	func searchableDidChange(_ searchable: QBESearchable)
}

@objc protocol QBESearchable {
	var searchQuery: String { get set }
	var supportsSearch: Bool { get }
	var responder: NSResponder? { get }
	weak var searchDelegate: QBESearchableDelegate? { get set }
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

	func startEditingWithIdentifier(_ ids: Set<Column>, callback: (() -> ())? = nil) {
	}

	@IBAction func closeTablet(_ sender: AnyObject) {
		self.delegate?.tabletViewDidClose(self)
	}
}
