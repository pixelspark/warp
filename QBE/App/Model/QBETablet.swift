import Foundation

/** A 'tablet' is a user-defined working item that represents tabular data and (possibly in the future) other forms of
data. Currently a tablet is always comprised of a QBEChain that calculates data. **/
class QBETablet: NSObject, NSSecureCoding {
	weak internal(set) var document: QBEDocument? = nil
	
	var chain: QBEChain { didSet {
		assert(chain.tablet == nil, "chain must not be associated with another tablet already")
		chain.tablet = self
	} }
	
	init(chain: QBEChain) {
		self.chain = chain
	}
	
	required init(coder aDecoder: NSCoder) {
		if let c = aDecoder.decodeObjectOfClass(QBEChain.self, forKey: "chain") as? QBEChain {
			chain = c
		}
		else {
			chain = QBEChain()
		}
	}
	
	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(chain, forKey: "chain")
	}
	
	static func supportsSecureCoding() -> Bool {
		return true
	}
	
	/** This method is called right before a document is saved to disk using encodeWithCoder. Steps that reference
	external files should take the opportunity to create security bookmarks to these files (as required by Apple's
	App Sandbox) and store them. **/
	func willSaveToDocument(atURL: NSURL) {
		self.chain.willSaveToDocument(atURL)
	}
	
	/** This method is called right after a document has been loaded from disk. **/
	func didLoadFromDocument(atURL: NSURL) {
		self.chain.didLoadFromDocument(atURL)
	}
}