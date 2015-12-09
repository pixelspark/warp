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

	static func supportsSecureCoding() -> Bool {
		return true
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(right, forKey: "right")
		super.encodeWithCoder(coder)
	}
	
	var dependencies: Set<QBEDependency> { get {
		if let r = right {
			return [QBEDependency(step: self, dependsOn: r)]
		}
		return []
	} }

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
			QBESentenceText(NSLocalizedString("Cloned data", comment: ""))
		])
	}
	
	override func fullData(job: Job, callback: (Fallible<Data>) -> ()) {
		if let r = self.right, let h = r.head {
			h.fullData(job, callback: callback)
		}
		else {
			callback(.Failure(NSLocalizedString("Clone step cannot find the original to clone from.", comment: "")))
		}
	}
	
	override func exampleData(job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Data>) -> ()) {
		if let r = self.right, let h = r.head {
			h.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: callback)
		}
		else {
			callback(.Failure(NSLocalizedString("Clone step cannot find the original to clone from.", comment: "")))
		}
	}
	
	override func apply(data: Data, job: Job, callback: (Fallible<Data>) -> ()) {
		fatalError("QBECloneStep.apply should not be used")
	}
}