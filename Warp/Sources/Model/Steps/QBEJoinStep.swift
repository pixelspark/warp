import Foundation
import WarpCore

class QBEJoinStep: QBEStep, NSSecureCoding, QBEChainDependent {
	weak var right: QBEChain? = nil
	var joinType: JoinType = JoinType.LeftJoin
	var condition: Expression? = nil

	required init() {
		super.init()
	}

	override init(previous: QBEStep?) {
		joinType = .LeftJoin
		super.init(previous: previous)
	}
	
	required init(coder aDecoder: NSCoder) {
		right = aDecoder.decodeObjectOfClass(QBEChain.self, forKey: "right")
		condition = aDecoder.decodeObjectOfClass(Expression.self, forKey: "condition")
		joinType = JoinType(rawValue: aDecoder.decodeObjectOfClass(NSString.self, forKey: "joinType") as? String ?? "") ?? .LeftJoin
		
		super.init(coder: aDecoder)
	}
	
	static func supportsSecureCoding() -> Bool {
		return true
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(right, forKey: "right")
		coder.encodeObject(condition, forKey: "condition")
		coder.encodeObject(NSString(UTF8String: joinType.rawValue), forKey: "joinType")
		super.encodeWithCoder(coder)
	}
	
	var dependencies: Set<QBEDependency> { get {
		if let r = right {
			return [QBEDependency(step: self, dependsOn: r)]
		}
		return []
	} }

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: NSLocalizedString("Join data on [#], [#] rows without matches", comment: ""),
			QBESentenceFormula(expression: self.condition ?? Literal(Value.BoolValue(false)), locale: locale, callback: { [weak self] (newExpression) -> () in
				self?.condition = newExpression
			}),
			QBESentenceOptions(options: [
				JoinType.LeftJoin.rawValue: NSLocalizedString("including", comment: ""),
				JoinType.InnerJoin.rawValue: NSLocalizedString("ignoring", comment: "")
			], value: self.joinType.rawValue, callback: { [weak self] (newJoinTypeName) -> () in
				if let j = JoinType(rawValue: newJoinTypeName) {
					self?.joinType = j
				}
			})
		)
	}
	
	private func join(right: Data) -> Join? {
		if let c = condition {
			return Join(type: joinType, foreignData: right, expression: c)
		}
		return nil
	}
	
	override func fullData(job: Job, callback: (Fallible<Data>) -> ()) {
		if let p = previous {
			p.fullData(job) {(leftData) -> () in
				if let r = self.right, let h = r.head {
					h.fullData(job) { (rightData) -> () in
						switch rightData {
							case .Success(let rd):
								if let j = self.join(rd) {
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
	
	override func exampleData(job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Data>) -> ()) {
		if let p = previous {
			p.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows) {(leftData) -> () in
				switch leftData {
					case .Success(let ld):
						if let r = self.right, let h = r.head {
							h.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: { (rightData) -> () in
								switch rightData {
									case .Success(let rd):
										if let j = self.join(rd) {
											callback(.Success(ld.join(j)))
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
	
	override func apply(data: Data, job: Job?, callback: (Fallible<Data>) -> ()) {
		fatalError("QBEJoinStep.apply should not be used")
	}
}

class QBEMergeStep: QBEStep, NSSecureCoding, QBEChainDependent {
	weak var right: QBEChain? = nil

	required init() {
		super.init()
	}
	
	init(previous: QBEStep?, with: QBEChain?) {
		right = with
		super.init(previous: previous)
	}
	
	required init(coder aDecoder: NSCoder) {
		right = aDecoder.decodeObjectOfClass(QBEChain.self, forKey: "right")
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

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([QBESentenceText(NSLocalizedString("Merge data", comment: ""))])
	}
	
	override func fullData(job: Job, callback: (Fallible<Data>) -> ()) {
		if let p = previous {
			p.fullData(job) {(leftData) -> () in
				if let r = self.right, let h = r.head {
					h.fullData(job) { (rightData) -> () in
						switch rightData {
							case .Success(let rd):
								callback(leftData.use {$0.union(rd)})
								
							case .Failure(_):
								callback(rightData)
						}
					}
				}
				else {
					callback(.Failure(NSLocalizedString("The data to merge with was not found.", comment: "")))
				}
			}
		}
		else {
			callback(.Failure(NSLocalizedString("A merge step was not placed after another step.", comment: "")))
		}
	}
	
	override func exampleData(job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Data>) -> ()) {
		if let p = previous {
			p.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows) {(leftData) -> () in
				switch leftData {
				case .Success(let ld):
					if let r = self.right, let h = r.head {
						h.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: { (rightData) -> () in
							switch rightData {
								case .Success(let rd):
									callback(.Success(ld.union(rd)))
									
								case .Failure(_):
									callback(rightData)
							}
						})
					}
					else {
						callback(.Failure(NSLocalizedString("The data to merge with was not found.", comment: "")))
					}
				case .Failure(_):
					callback(leftData)
				}
			}
		}
		else {
			callback(.Failure(NSLocalizedString("A merge step was not placed after another step.", comment: "")))
		}
	}
	
	override func apply(data: Data, job: Job?, callback: (Fallible<Data>) -> ()) {
		fatalError("QBEMergeStep.apply should not be used")
	}
}
