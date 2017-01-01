/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import WarpCore

#if os(macOS)
	import Cocoa
	typealias UXDocument = NSDocument
#endif

#if os(iOS)
	import UIKit
	typealias UXDocument = UIDocument
#endif

class QBEDocument: UXDocument {
	private(set) var tablets: [QBETablet] = []
	private(set) var savedAtLeastOnce = false

	static var fileExtension = "warp"
	
	func removeTablet(_ tablet: QBETablet) {
		assert(tablet.document == self, "tablet must belong to this document")
		tablet.document = nil
		tablets.remove(tablet)
	}
	
	func addTablet(_ tablet: QBETablet) {
		assert(tablet.document == nil, "tablet must not be associated with another document already")
		tablet.document = self
		tablets.append(tablet)
	}

	func archive() throws -> Data {
		let data = NSMutableData()
		let ka = NSKeyedArchiver(forWritingWith: data)

		// Previously QBETablet was the class used for chain tablets, now it is a superclass. Use a different alias to not confuse older versions
		ka.setClassName("Warp.QBETablet.v2", for: QBETablet.classForKeyedArchiver()!)

		// The archiver should pretend QBEDocumentCoder is actually QBEDocument.
		ka.setClassName("Warp.QBEDocument", for: QBEDocumentCoder.classForKeyedArchiver()!)

		let coder = QBEDocumentCoder(self)
		ka.encode(coder, forKey: "root")
		ka.finishEncoding()
		return data as Data
	}

	func unarchive(from data: Data, ofType typeName: String) throws {
		let unarchiver = NSKeyedUnarchiver(forReadingWith: data)

		// Ensure that old classes referenced in files generated by older versions of this software can be found
		unarchiver.setClass(QBERectangle.classForKeyedUnarchiver(), forClassName: "_TtC4WarpP33_B11F6D3701F49B735237E0045569881C12QBERectangle")
		unarchiver.setClass(Order.classForKeyedUnarchiver(), forClassName: "WarpCore.QBEOrder")
		unarchiver.setClass(Aggregation.classForKeyedUnarchiver(), forClassName: "WarpCore.QBEAggregation")
		unarchiver.setClass(Expression.classForKeyedUnarchiver(), forClassName: "WarpCore.QBEExpression")
		unarchiver.setClass(FilterSet.classForKeyedUnarchiver(), forClassName: "WarpCore.QBEFilterSet")
		unarchiver.setClass(DatasetDefinition.classForKeyedUnarchiver(), forClassName: "WarpCore.QBEDatasetDefinition")
		unarchiver.setClass(Raster.classForKeyedUnarchiver(), forClassName: "WarpCore.QBERaster")
		unarchiver.setClass(Sibling.classForKeyedUnarchiver(), forClassName: "WarpCore.QBESiblingExpression")
		unarchiver.setClass(Literal.classForKeyedUnarchiver(), forClassName: "WarpCore.QBELiteralExpresion")
		unarchiver.setClass(Call.classForKeyedUnarchiver(), forClassName: "WarpCore.QBEFunctionExpression")
		unarchiver.setClass(Moving.classForKeyedUnarchiver(), forClassName: "WarpCore.QBEMoving")
		unarchiver.setClass(ValueCoder.classForKeyedUnarchiver(), forClassName: "WarpCore.QBEValueCoder")
		unarchiver.setClass(Foreign.classForKeyedUnarchiver(), forClassName: "WarpCore.QBEForeignExpression")
		unarchiver.setClass(Comparison.classForKeyedUnarchiver(), forClassName: "WarpCore.QBEBinaryExpression")
		unarchiver.setClass(Identity.classForKeyedUnarchiver(), forClassName: "WarpCore.QBEIdentityExpression")
		unarchiver.setClass(QBEChainTablet.classForKeyedUnarchiver(), forClassName: "Warp.QBETablet")

		#if os(macOS)
			unarchiver.setClass(QBEExplodeVerticallyStep.classForKeyedUnarchiver(), forClassName: "Warp.QBEExplodeStep")
		#endif

		// Trick the unarchiver into using QBEDocumentCoder for decoding QBEDocuments
		unarchiver.setClass(QBEDocumentCoder.classForKeyedUnarchiver(), forClassName: "Warp.QBEDocument")

		if let x = unarchiver.decodeObject(forKey: "root") as? QBEDocumentCoder {
			tablets = x.tablets
			tablets.forEach { $0.document = self }
		}
		unarchiver.finishDecoding()
	}

	#if os(macOS)
		override func data(ofType typeName: String) throws -> Data {
			return try self.archive()
		}

		override func read(from data: Data, ofType typeName: String) throws {
			try self.unarchive(from: data, ofType: typeName)
		}

		override func windowControllerDidLoadNib(_ aController: NSWindowController) {
			super.windowControllerDidLoadNib(aController)
			// Add any code here that needs to be executed once the windowController has loaded the document's window.
		}

		override class func autosavesInPlace() -> Bool {
			return true
		}
	
		override func makeWindowControllers() {
			let storyboard = NSStoryboard(name: "Main", bundle: nil)

			if !QBESettings.sharedInstance.once("tour", callback: { () -> () in
				let ctr = storyboard.instantiateController(withIdentifier: "tour") as! NSWindowController
				ctr.window?.titleVisibility = .hidden
				self.addWindowController(ctr)
			}) {
				let windowController = storyboard.instantiateController(withIdentifier: "documentWindow") as! NSWindowController
				self.addWindowController(windowController)
			}
		}

		override func save(_ sender: Any?) {
			savedAtLeastOnce = true
			super.save(sender)
			self.updateWindowControllers()
		}

		override func saveAs(_ sender: Any?) {
			savedAtLeastOnce = true
			super.save(sender)
			self.updateWindowControllers()
		}

		override func save(withDelegate delegate: Any?, didSave didSaveSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
			savedAtLeastOnce = true
			super.save(withDelegate: delegate, didSave: didSaveSelector, contextInfo: contextInfo)
			self.updateWindowControllers()
		}

		private func updateWindowControllers() {
			self.windowControllers.forEach { dc in
				if let qdc = dc as? QBEWindowController {
					qdc.update()
				}
			}
		}

		override func write(to url: URL, ofType typeName: String) throws {
			/* Steps may use security-scoped bookmarks to reference files. These bookmarks are document-specific, and in order
			to create the bookmarks, the system expects the URL to the document. However, the document does not exist yet
			before it is written, as Cocoa by default writes to a temporary location, then afterwards moves the document to
			the final destination. So therefore we write the document twice: once to make sure it exists, and then once again
			to write a version this time with the security scoped bookmarks. */
			try super.write(to: url, ofType: typeName)
			self.tablets.forEach { $0.willSaveToDocument(url) }
			try super.write(to: url, ofType: typeName)
			self.updateWindowControllers()
		}

		override func read(from url: URL, ofType typeName: String) throws {
			try super.read(from: url, ofType: typeName)
			self.tablets.forEach { $0.didLoadFromDocument(url) }
			self.updateWindowControllers()
		}
	#endif

	#if os(iOS)
		override init(fileURL: URL) {
			super.init(fileURL: fileURL)
		}

		override func load(fromContents contents: Any, ofType typeName: String?) throws {
			try self.unarchive(from: contents as! Data, ofType: typeName ?? "")
		}

		override func contents(forType typeName: String) throws -> Any {
			return try self.archive()
		}

		override func read(from url: URL) throws {
			try super.read(from: url)
			self.tablets.forEach { $0.document = self; $0.didLoadFromDocument(url) }
		}

		override func save(to url: URL, for saveOperation: UIDocumentSaveOperation, completionHandler: ((Bool) -> Void)? = nil) {
			self.tablets.forEach { $0.willSaveToDocument(url) }
			super.save(to: url, for: saveOperation, completionHandler: completionHandler)
		}

		override func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
			self.close(completionHandler: { success in
				completionHandler(nil)
			})
		}
	#endif
}

/** Need to put encoding logic in a separate class because QBEDocument itself cannot be NSSecureCoding, because it must
(on iOS) subclass UIDocument. This in turn prevents adding the required initWithCoder initializer, because UIDocument
must be called with init(fileURL:) which we do not know when loading from a coder. */
class QBEDocumentCoder: NSObject, NSSecureCoding {
	static var supportsSecureCoding: Bool = true

	private(set) var tablets: [QBETablet] = []

	init(_ document: QBEDocument) {
		self.tablets = document.tablets
	}

	required init?(coder aDecoder: NSCoder) {
		super.init()

		if let head = aDecoder.decodeObject(of: QBEStep.self, forKey: "head") {
			let legacyTablet = QBEChainTablet(chain: QBEChain(head: head))
			tablets.append(legacyTablet)
		}
		else {
			tablets = aDecoder.decodeObject(of: [QBETablet.self, NSArray.self], forKey: "tablets") as? [QBETablet] ?? []
		}
	}

	func encode(with coder: NSCoder) {
		coder.encode(tablets, forKey: "tablets")
	}
}
