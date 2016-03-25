import Foundation

public class QBERectangle: NSObject, NSSecureCoding {
	let rect: CGRect
	
	init(_ rect: CGRect) {
		self.rect = rect
	}
	
	@objc required public init?(coder aDecoder: NSCoder) {
		rect = CGRect(
			x: aDecoder.decodeDoubleForKey("x") ?? Double.NaN,
			y: aDecoder.decodeDoubleForKey("y") ?? Double.NaN,
			width: aDecoder.decodeDoubleForKey("w") ?? Double.NaN,
			height: aDecoder.decodeDoubleForKey("h") ?? Double.NaN
		)
	}
	
	@objc public func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeDouble(Double(rect.origin.x), forKey: "x")
		aCoder.encodeDouble(Double(rect.origin.y), forKey: "y")
		aCoder.encodeDouble(Double(rect.size.width), forKey: "w")
		aCoder.encodeDouble(Double(rect.size.height), forKey: "h")
	}
	
	@objc public static func supportsSecureCoding() -> Bool {
		return true
	}
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
		return from?.frame ?? CGRectZero
	} }

	var targetFrame: CGRect { get {
		return to?.frame ?? CGRectZero
	} }
}

/** A 'tablet' is an interactive widget that is contained in the document that allows visualisation and/or manipulation
of data. A tablet has a rectangular shape and a certain position in the document ('frame'). */
@objc class QBETablet: NSObject, NSSecureCoding {
	weak internal(set) var document: QBEDocument? = nil
	var frame: CGRect? = nil

	/** An arrow is a dependency between two tablets. */
	var arrows: [QBETabletArrow] {
		return []
	}

	var displayName: String? { get {
		return self.document?.displayName
	} }

	override init() {
	}
	
	required init?(coder aDecoder: NSCoder) {
		if let rect = aDecoder.decodeObjectOfClass(QBERectangle.self, forKey: "frame") {
			frame = rect.rect
		}
		
		super.init()
	}
	
	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(frame == nil ? nil : QBERectangle(frame!), forKey: "frame")
	}
	
	static func supportsSecureCoding() -> Bool {
		return true
	}
	
	/** This method is called right before a document is saved to disk using encodeWithCoder. Steps that reference
	external files should take the opportunity to create security bookmarks to these files (as required by Apple's
	App Sandbox) and store them. */
	func willSaveToDocument(atURL: NSURL) {
	}
	
	/** This method is called right after a document has been loaded from disk. */
	func didLoadFromDocument(atURL: NSURL) {
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
		if let c = aDecoder.decodeObjectOfClass(QBEChain.self, forKey: "chain") {
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

	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(chain, forKey: "chain")
	}

	override func willSaveToDocument(atURL: NSURL) {
		self.chain.willSaveToDocument(atURL)
	}

	override func didLoadFromDocument(atURL: NSURL) {
		self.chain.didLoadFromDocument(atURL)
	}
	
}