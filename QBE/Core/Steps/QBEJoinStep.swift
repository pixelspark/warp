import Foundation

class QBEJoinStep: QBEStep, NSSecureCoding, QBEChainDependent {
	weak var right: QBEChain?
	var condition: QBEExpression?
	
	override init(previous: QBEStep?) {
		super.init(previous: previous)
	}
	
	required init(coder aDecoder: NSCoder) {
		right = aDecoder.decodeObjectOfClass(QBEChain.self, forKey: "right") as? QBEChain
		condition = aDecoder.decodeObjectOfClass(QBEExpression.self, forKey: "condition") as? QBEExpression
		super.init(coder: aDecoder)
	}
	
	static func supportsSecureCoding() -> Bool {
		return true
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(right, forKey: "right")
		coder.encodeObject(condition, forKey: "condition")
		super.encodeWithCoder(coder)
	}
	
	var dependencies: Set<QBEDependency> { get {
		if let r = right {
			return [QBEDependency(step: self, dependsOn: r)]
		}
		return []
	} }
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short || condition == nil {
			return NSLocalizedString("Join data", comment: "")
		}
		else {
			return String(format: NSLocalizedString("Join data: %@", comment: ""), condition!.explain(locale))
		}
	}
	
	private func join(right: QBEData) -> QBEJoin? {
		if let c = condition {
			return QBEJoin.LeftJoin(right, c)
		}
		return nil
	}
	
	override func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		if let p = previous {
			p.fullData(job) {(leftData) -> () in
				if let r = self.right, let h = r.head {
					h.fullData(job) { (rightData) -> () in
						switch rightData {
							case .Success(let rd):
								if let j = self.join(rd.value) {
									callback(leftData.use({$0.join(j)}))
								}
								else {
									callback(.Failure(NSLocalizedString("Not all information was available to perform the join.", comment: "")))
								}
							
							case .Failure(_):
								callback(rightData)
						}
					}
				}
				else {
					callback(.Failure(NSLocalizedString("The data to join with was not found.", comment: "")))
				}
			}
		}
		else {
			callback(.Failure(NSLocalizedString("A join step was not placed after another step.", comment: "")))
		}
	}
	
	override func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEFallible<QBEData>) -> ()) {
		if let p = previous {
			p.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows) {(leftData) -> () in
				switch leftData {
					case .Success(let ld):
						if let r = self.right, let h = r.head {
							h.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: { (rightData) -> () in
								switch rightData {
									case .Success(let rd):
										if let j = self.join(rd.value) {
											callback(QBEFallible(ld.value.join(j)))
										}
										else {
											callback(.Failure(NSLocalizedString("Not all information was available to perform the join.", comment: "")))
										}
									
									case .Failure(_):
										callback(rightData)
								}
							})
						}
						else {
							callback(.Failure(NSLocalizedString("The data to join with was not found.", comment: "")))
						}
					case .Failure(_):
						callback(leftData)
				}
			}
		}
		else {
			callback(.Failure(NSLocalizedString("A join step was not placed after another step.", comment: "")))
		}
	}
	
	override func apply(data: QBEData, job: QBEJob?, callback: (QBEFallible<QBEData>) -> ()) {
		fatalError("QBEJoinStep.apply should not be used")
	}
}
