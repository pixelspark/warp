import Foundation

private class QBERectangle: NSObject, NSSecureCoding {
	let rect: CGRect
	
	init(_ rect: CGRect) {
		self.rect = rect
	}
	
	@objc required init?(coder aDecoder: NSCoder) {
		rect = CGRect(
			x: aDecoder.decodeDoubleForKey("x") ?? Double.NaN,
			y: aDecoder.decodeDoubleForKey("y") ?? Double.NaN,
			width: aDecoder.decodeDoubleForKey("w") ?? Double.NaN,
			height: aDecoder.decodeDoubleForKey("h") ?? Double.NaN
		)
	}
	
	@objc func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeDouble(Double(rect.origin.x), forKey: "x")
		aCoder.encodeDouble(Double(rect.origin.y), forKey: "y")
		aCoder.encodeDouble(Double(rect.size.width), forKey: "w")
		aCoder.encodeDouble(Double(rect.size.height), forKey: "h")
	}
	
	@objc static func supportsSecureCoding() -> Bool {
		return true
	}
}

/** A 'tablet' is a user-defined working item that represents tabular data and (possibly in the future) other forms of
data. Currently a tablet is always comprised of a QBEChain that calculates data. */
@objc class QBETablet: NSObject, NSSecureCoding {
	weak internal(set) var document: QBEDocument? = nil
	var frame: CGRect? = nil
	
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
		if let c = aDecoder.decodeObjectOfClass(QBEChain.self, forKey: "chain") as? QBEChain {
			chain = c
		}
		else {
			chain = QBEChain()
		}
		
		if let rect = aDecoder.decodeObjectOfClass(QBERectangle.self, forKey: "frame") as? QBERectangle {
			frame = rect.rect
		}
		
		super.init()
		chain.tablet = self
	}
	
	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(chain, forKey: "chain")
		aCoder.encodeObject(frame == nil ? nil : QBERectangle(frame!), forKey: "frame")
	}
	
	static func supportsSecureCoding() -> Bool {
		return true
	}
	
	/** This method is called right before a document is saved to disk using encodeWithCoder. Steps that reference
	external files should take the opportunity to create security bookmarks to these files (as required by Apple's
	App Sandbox) and store them. */
	func willSaveToDocument(atURL: NSURL) {
		self.chain.willSaveToDocument(atURL)
	}
	
	/** This method is called right after a document has been loaded from disk. */
	func didLoadFromDocument(atURL: NSURL) {
		self.chain.didLoadFromDocument(atURL)
	}
}