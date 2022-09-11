/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import CoreGraphics

public class QBERectangle: NSObject, NSSecureCoding {
	let rect: CGRect
	
	init(_ rect: CGRect) {
		self.rect = rect
	}
	
	@objc required public init?(coder aDecoder: NSCoder) {
		rect = CGRect(
			x: aDecoder.decodeDouble(forKey: "x"),
			y: aDecoder.decodeDouble(forKey: "y"),
			width: aDecoder.decodeDouble(forKey: "w"),
			height: aDecoder.decodeDouble(forKey: "h")
		)
	}
	
	@objc public func encode(with aCoder: NSCoder) {
		aCoder.encode(Double(rect.origin.x), forKey: "x")
		aCoder.encode(Double(rect.origin.y), forKey: "y")
		aCoder.encode(Double(rect.size.width), forKey: "w")
		aCoder.encode(Double(rect.size.height), forKey: "h")
	}
	
	public static var supportsSecureCoding: Bool = true
}

/** An arrow that exists between two tablets, indicating some sort of dependency. */
class QBETabletArrow: NSObject, QBEArrow {
	private(set) weak var from: QBETablet?
	private(set) weak var to: QBETablet?
	private(set) weak var fromStep: QBEStep?

	/** Create an arrow between two tablets. The arrow should always point in the direction the data is flowing. */
	init(from: QBETablet, to: QBETablet, fromStep: QBEStep) {
		self.from = from
		self.to = to
		self.fromStep = fromStep
	}

	var sourceFrame: CGRect { get {
		return from?.frame ?? CGRect.zero
	} }

	var targetFrame: CGRect { get {
		return to?.frame ?? CGRect.zero
	} }
}

/** A 'tablet' is an interactive widget that is contained in the document that allows visualisation and/or manipulation
of data. A tablet has a rectangular shape and a certain position in the document ('frame'). */
@objc class QBETablet: NSObject, NSSecureCoding {
	weak internal var document: QBEDocument? = nil
	var frame: CGRect? = nil

	/** An arrow is a dependency between two tablets. */
	var arrows: [QBETabletArrow] {
		return []
	}

	var displayName: String? { get {
		return nil
	} }

	override init() {
	}
	
	required init?(coder aDecoder: NSCoder) {
		if let rect = aDecoder.decodeObject(of: QBERectangle.self, forKey: "frame") {
			frame = rect.rect
		}
		
		super.init()
	}
	
	func encode(with aCoder: NSCoder) {
		aCoder.encode(frame == nil ? nil : QBERectangle(frame!), forKey: "frame")
	}
	
	static var supportsSecureCoding: Bool = true
	
	/** This method is called right before a document is saved to disk using encodeWithCoder. Steps that reference
	external files should take the opportunity to create security bookmarks to these files (as required by Apple's
	App Sandbox) and store them. */
	func willSaveToDocument(_ atURL: URL) {
	}
	
	/** This method is called right after a document has been loaded from disk. */
	func didLoadFromDocument(_ atURL: URL) {
	}
}

/** A chain tablet is a tablet that shows a 'chain' of operations calculating tabular data. */
@objc class QBEChainTablet: QBETablet {
	var chain: QBEChain { didSet {
		assert(chain.tablet == nil, "chain must not be associated with another tablet already")
		chain.tablet = self
	} }

	init(chain: QBEChain) {
		self.chain = chain
		super.init()
		self.chain.tablet = self
	}

	required init?(coder aDecoder: NSCoder) {
		if let c = aDecoder.decodeObject(of: QBEChain.self, forKey: "chain") {
			chain = c
		}
		else {
			chain = QBEChain()
		}

		super.init(coder: aDecoder)
		chain.tablet = self
	}


	override var arrows: [QBETabletArrow] {
		var arrows: [QBETabletArrow] = []
		for dep in chain.directDependencies {
			if let s = chain.tablet, let t = dep.dependsOn.tablet {
				arrows.append(QBETabletArrow(from: t, to: s, fromStep: dep.step))
			}
		}
		return arrows
	}

	override func encode(with aCoder: NSCoder) {
		super.encode(with: aCoder)
		aCoder.encode(chain, forKey: "chain")
	}

	override func willSaveToDocument(_ atURL: URL) {
		self.chain.willSaveToDocument(atURL)
	}

	override func didLoadFromDocument(_ atURL: URL) {
		self.chain.didLoadFromDocument(atURL)
	}
	
}
