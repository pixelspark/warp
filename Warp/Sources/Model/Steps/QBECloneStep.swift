import Foundation
import WarpCore

class QBECloneStep: QBEStep, NSSecureCoding, QBEChainDependent {
	weak var right: QBEChain?
	
	init(chain: QBEChain?) {
		super.init()
		self.right = chain
	}
	
	required init(coder aDecoder: NSCoder) {
		right = aDecoder.decodeObjectOfClass(QBEChain.self, forKey: "right")
		super.init(coder: aDecoder)
	}

	required init() {
		right = nil
		super.init()
	}

	static var supportsSecureCoding: Bool = true
	
	override func encode(with coder: NSCoder) {
		coder.encode(right, forKey: "right")
		super.encode(with: coder)
	}
	
	var recursiveDependencies: Set<QBEDependency> {
		if let r = right {
			return Set([QBEDependency(step: self, dependsOn: r)]).union(r.recursiveDependencies)
		}
		return []
	}

	var directDependencies: Set<QBEDependency> {
		if let r = right {
			return Set([QBEDependency(step: self, dependsOn: r)])
		}
		return []
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
			QBESentenceText(NSLocalizedString("Cloned data", comment: ""))
		])
	}
	
	override func fullDataset(_ job: Job, callback: (Fallible<Dataset>) -> ()) {
		if let r = self.right, let h = r.head {
			h.fullDataset(job, callback: callback)
		}
		else {
			callback(.failure(NSLocalizedString("Clone step cannot find the original to clone from.", comment: "")))
		}
	}
	
	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Dataset>) -> ()) {
		if let r = self.right, let h = r.head {
			h.exampleDataset(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: callback)
		}
		else {
			callback(.failure(NSLocalizedString("Clone step cannot find the original to clone from.", comment: "")))
		}
	}

	override var mutableDataset: MutableDataset? {
		return self.right?.head?.mutableDataset
	}
	
	override func apply(_ data: Dataset, job: Job, callback: (Fallible<Dataset>) -> ()) {
		fatalError("QBECloneStep.apply should not be used")
	}
}
