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
		let joinTypeSentenceItem = QBESentenceOptions(options: [
			JoinType.LeftJoin.rawValue: NSLocalizedString("including", comment: ""),
			JoinType.InnerJoin.rawValue: NSLocalizedString("ignoring", comment: "")
			], value: self.joinType.rawValue, callback: { [weak self] (newJoinTypeName) -> () in
				if let j = JoinType(rawValue: newJoinTypeName) {
					self?.joinType = j
				}
			})

		let binaryOptions = Binary.allBinaries.filter { $0.isComparative }.mapDictionary { b in return (b.rawValue, b.explain(locale)) }

		if self.isSimple {
			return QBESentence(format: "Join data on [#] [#] [#], [#] rows without matches".localized,
				QBESentenceList(value: self.simpleSibling?.name ?? "", provider: { cb in
					let job = Job(.UserInitiated)
					if let previous = self.previous {
						previous.exampleData(job, maxInputRows: 100, maxOutputRows: 1, callback: { result in
							switch result {
							case .Success(let data):
								data.columns(job) { result in
									switch result {
									case .Success(let columns):
										cb(.Success(columns.map { $0.name }))

									case .Failure(let e):
										cb(.Failure(e))
									}
								}
							case .Failure(let e):
								return cb(.Failure(e))
							}
						})
					}
					else {
						cb(.Failure("No previous step"))
					}
				}, callback: { [weak self] newValue in
					self?.simpleSibling = Column(newValue)
				}),

				QBESentenceOptions(options: binaryOptions, value: (self.simpleType ?? .Equal).rawValue, callback: { [weak self] newType in
					self?.simpleType = Binary(rawValue: newType)
				}),

				QBESentenceList(value: self.simpleForeign?.name ?? "", provider: { cb in
					let job = Job(.UserInitiated)
					if let right = self.right?.head {
						right.exampleData(job, maxInputRows: 100, maxOutputRows: 1, callback: { result in
							switch result {
							case .Success(let data):
								data.columns(job) { result in
									switch result {
									case .Success(let columns):
										cb(.Success(columns.map { $0.name }))

									case .Failure(let e):
										cb(.Failure(e))
									}
								}
							case .Failure(let e):
								return cb(.Failure(e))
							}
						})
					}
					else {
						cb(.Failure("No data to join to"))
					}
					}, callback: { [weak self] newValue in
						self?.simpleForeign = Column(newValue)
				}),

				joinTypeSentenceItem
			)
		}
		else {
			return QBESentence(format: NSLocalizedString("Join data on [#], [#] rows without matches", comment: ""),
				QBESentenceFormula(expression: self.condition ?? Literal(Value.BoolValue(false)), locale: locale, callback: { [weak self] (newExpression) -> () in
					self?.condition = newExpression
				}),
				joinTypeSentenceItem
			)
		}
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

	/** Returns whether the currently set join is 'simple' (e.g. only based on a comparison of two columns). This requires 
	the join condition to be a binary expression with on either side a column reference. */
	var isSimple: Bool {
		if let c = self.condition as? Comparison {
			if c.first is Foreign && c.second is Sibling {
				return true
			}

			if c.second is Foreign && c.first is Sibling {
				return true
			}

			if c.isConstant {
				let constantValue = c.apply(Row(), foreign: nil, inputValue: nil)
				if !constantValue.isValid || constantValue == Value.BoolValue(false) {
					return true
				}
			}

			return false
		}
		else {
			return true
		}
	}

	var simpleForeign: Column? {
		get {
			if let foreign = (self.condition as? Comparison)?.first as? Foreign {
				return foreign.column
			}
			else if let foreign = (self.condition as? Comparison)?.second as? Foreign {
				return foreign.column
			}
			else {
				return nil
			}
		}
		set {
			setSimpleCondition(sibling: simpleSibling, foreign: newValue)
		}
	}

	var simpleSibling: Column? {
		get {
			if let sibling = (self.condition as? Comparison)?.second as? Sibling {
				return sibling.column
			}
			else if let sibling = (self.condition as? Comparison)?.first as? Sibling {
				return sibling.column
			}
			else {
				return nil
			}
		}
		set {
			setSimpleCondition(sibling: newValue, foreign: simpleForeign)
		}
	}

	var simpleType: Binary? {
		get {
			return (self.condition as? Comparison)?.type
		}
		set {
			(self.condition as? Comparison)?.type = newValue!
		}
	}

	private func setSimpleCondition(sibling sibling: Column?, foreign: Column?) {
		let currentType = self.simpleType ?? Binary.Equal
		let first: Expression = (foreign != nil) ? Foreign(foreign!) : Literal(Value.InvalidValue)
		let second: Expression = (sibling != nil) ? Sibling(sibling!) : Literal(Value.InvalidValue)
		self.condition = Comparison(first: first, second: second, type: currentType)
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
