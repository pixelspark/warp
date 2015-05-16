import Foundation

protocol QBEChainDependent: NSObjectProtocol {
	var dependencies: Set<QBEChain> { get }
}

/** QBEChain represents a chain of steps, leading to a result data set. **/
class QBEChain: NSObject, NSSecureCoding, QBEChainDependent {
	static let dragType = "nl.pixelspark.Warp.Chain"
	
	var head: QBEStep? = nil
	weak internal(set) var tablet: QBETablet? = nil
	
	init(head: QBEStep? = nil) {
		self.head = head
	}
	
	required init(coder aDecoder: NSCoder) {
		head = aDecoder.decodeObjectOfClass(QBEStep.self, forKey: "head") as? QBEStep
	}
	
	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(head, forKey: "head")
	}
	
	static func supportsSecureCoding() -> Bool {
		return true
	}
	
	var dependencies: Set<QBEChain> { get {
		var deps: Set<QBEChain> = []
		
		for s in steps {
			if let sd = s as? QBEChainDependent {
				deps.unionInPlace(sd.dependencies)
			}
		}
		
		return deps
	} }
	
	var isPartOfDependencyLoop: Bool { get {
		return dependencies.contains(self)
	} }
	
	var steps: [QBEStep] { get {
		var s: [QBEStep] = []
		var current = head
		
		while current != nil {
			s.append(current!)
			current = current!.previous
		}
		
		return s.reverse()
	} }
	
	func insertStep(step: QBEStep, afterStep: QBEStep?) {
		if afterStep == nil {
			// Insert at beginning
			if head != nil {
				var before = head
				while before!.previous != nil {
					before = before!.previous
				}
				
				before!.previous = step
			}
			else {
				head = step
			}
		}
		else {
			step.previous = afterStep
			if head == afterStep {
				head = step
			}
		}
	}
	
	/** This method is called right before a document is saved to disk using encodeWithCoder. Steps that reference
	external files should take the opportunity to create security bookmarks to these files (as required by Apple's
	App Sandbox) and store them. **/
	func willSaveToDocument(atURL: NSURL) {
		self.steps.each({$0.willSaveToDocument(atURL)})
	}
	
	/** This method is called right after a document has been loaded from disk. **/
	func didLoadFromDocument(atURL: NSURL) {
		self.steps.each({$0.didLoadFromDocument(atURL)})
	}
}
