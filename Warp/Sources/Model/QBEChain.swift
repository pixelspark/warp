import Foundation
import WarpCore

struct QBEDependency: Hashable, Equatable {
	let step: QBEStep
	let dependsOn: QBEChain
	
	var hashValue: Int { get {
		return step.hashValue ^ dependsOn.hashValue
	} }
}

func ==(lhs: QBEDependency, rhs: QBEDependency) -> Bool {
	return lhs.step == rhs.step && lhs.dependsOn == rhs.dependsOn
}

protocol QBEChainDependent: NSObjectProtocol {
	var recursiveDependencies: Set<QBEDependency> { get }
	var directDependencies: Set<QBEDependency> { get }
}

/** QBEChain represents a chain of steps, leading to a result data set. */
class QBEChain: NSObject, NSSecureCoding, QBEChainDependent {
	static let dragType = "nl.pixelspark.Warp.Chain"
	
	var head: QBEStep? = nil
	weak internal(set) var tablet: QBETablet? = nil
	
	init(head: QBEStep? = nil) {
		self.head = head
	}
	
	required init?(coder aDecoder: NSCoder) {
		head = aDecoder.decodeObjectOfClass(QBEStep.self, forKey: "head")
	}
	
	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(head, forKey: "head")
	}
	
	static func supportsSecureCoding() -> Bool {
		return true
	}
	
	var recursiveDependencies: Set<QBEDependency> {
		var deps: Set<QBEDependency> = []
		
		for s in steps {
			if let sd = s as? QBEChainDependent {
				deps.unionInPlace(sd.recursiveDependencies)
			}
		}
		
		return deps
	}

	var directDependencies: Set<QBEDependency> {
		var deps: Set<QBEDependency> = []

		for s in steps {
			if let sd = s as? QBEChainDependent {
				deps.unionInPlace(sd.directDependencies)
			}
		}

		return deps
	}
	
	var isPartOfDependencyLoop: Bool {
		return Array(directDependencies).map({$0.dependsOn}).contains(self)
	}
	
	var steps: [QBEStep] {
		var s: [QBEStep] = []
		var current = head
		
		while current != nil {
			s.append(current!)
			current = current!.previous
		}
		
		return Array(s.reverse())
	}
	
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
	App Sandbox) and store them. */
	func willSaveToDocument(atURL: NSURL) {
		self.steps.forEach { $0.willSaveToDocument(atURL) }
	}
	
	/** This method is called right after a document has been loaded from disk. */
	func didLoadFromDocument(atURL: NSURL) {
		self.steps.forEach { $0.didLoadFromDocument(atURL) }
	}
}
