import Foundation

class QBECloneStep: QBEStep, NSSecureCoding, QBEChainDependent {
	weak var right: QBEChain?
	
	init(chain: QBEChain?) {
		super.init(previous: nil)
		self.right = chain
	}
	
	required init(coder aDecoder: NSCoder) {
		right = aDecoder.decodeObjectOfClass(QBEChain.self, forKey: "right") as? QBEChain
		super.init(coder: aDecoder)
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
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		return NSLocalizedString("Cloned data", comment: "")
	}
	
	override func fullData(job: QBEJob, callback: (QBEData) -> ()) {
		if let r = self.right, let h = r.head {
			h.fullData(job, callback: callback)
		}
		else {
			// FIXME: error message instead of empty data
			callback(QBERasterData())
		}
	}
	
	override func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEData) -> ()) {
		if let r = self.right, let h = r.head {
			h.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: callback)
		}
		else {
			// FIXME: error message instead of empty data
			callback(QBERasterData())
		}
	}
	
	override func apply(data: QBEData, job: QBEJob, callback: (QBEData) -> ()) {
		fatalError("QBECloneStep.apply should not be used")
	}
}