/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore

class QBEJoinStep: QBEStep, NSSecureCoding, QBEChainDependent {
	weak var right: QBEChain? = nil
	var joinType: JoinType = JoinType.leftJoin
	var condition: Expression? = nil

	required init() {
		super.init()
	}

	override init(previous: QBEStep?) {
		joinType = .leftJoin
		super.init(previous: previous)
	}
	
	required init(coder aDecoder: NSCoder) {
		right = aDecoder.decodeObject(of: QBEChain.self, forKey: "right")
		condition = aDecoder.decodeObject(of: Expression.self, forKey: "condition")
		joinType = JoinType(rawValue: aDecoder.decodeObject(of: NSString.self, forKey: "joinType") as? String ?? "") ?? .leftJoin
		
		super.init(coder: aDecoder)
	}
	
	static var supportsSecureCoding: Bool = true
	
	override func encode(with coder: NSCoder) {
		coder.encode(right, forKey: "right")
		coder.encode(condition, forKey: "condition")
		coder.encode(String(utf8String: joinType.rawValue), forKey: "joinType")
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
		let joinTypeSentenceItem = QBESentenceOptionsToken(options: [
			JoinType.leftJoin.rawValue: NSLocalizedString("including", comment: ""),
			JoinType.innerJoin.rawValue: NSLocalizedString("ignoring", comment: "")
			], value: self.joinType.rawValue, callback: { [weak self] (newJoinTypeName) -> () in
				if let j = JoinType(rawValue: newJoinTypeName) {
					self?.joinType = j
				}
			})

		let binaryOptions = Binary.allBinaries.filter { $0.isComparative }.mapDictionary { b in return (b.rawValue, b.explain(locale)) }

		if self.isSimple {
			return QBESentence(format: "Join data on [#] [#] [#], [#] rows without matches".localized,
				QBESentenceDynamicOptionsToken(value: self.simpleSibling?.name ?? "", provider: { cb in
					let job = Job(.userInitiated)
					if let previous = self.previous {
						previous.exampleDataset(job, maxInputRows: 100, maxOutputRows: 1, callback: { result in
							switch result {
							case .success(let data):
								data.columns(job) { result in
									switch result {
									case .success(let columns):
										cb(.success(columns.map { $0.name }))

									case .failure(let e):
										cb(.failure(e))
									}
								}
							case .failure(let e):
								return cb(.failure(e))
							}
						})
					}
					else {
						cb(.failure("No previous step"))
					}
				}, callback: { [weak self] newValue in
					self?.simpleSibling = Column(newValue)
				}),

				QBESentenceOptionsToken(options: binaryOptions, value: (self.simpleType ?? .equal).rawValue, callback: { [weak self] newType in
					self?.simpleType = Binary(rawValue: newType)
				}),

				QBESentenceDynamicOptionsToken(value: self.simpleForeign?.name ?? "", provider: { cb in
					let job = Job(.userInitiated)
					if let right = self.right?.head {
						right.exampleDataset(job, maxInputRows: 100, maxOutputRows: 1, callback: { result in
							switch result {
							case .success(let data):
								data.columns(job) { result in
									switch result {
									case .success(let columns):
										cb(.success(columns.map { $0.name }))

									case .failure(let e):
										cb(.failure(e))
									}
								}
							case .failure(let e):
								return cb(.failure(e))
							}
						})
					}
					else {
						cb(.failure("No data to join to"))
					}
					}, callback: { [weak self] newValue in
						self?.simpleForeign = Column(newValue)
				}),

				joinTypeSentenceItem
			)
		}
		else {
			return QBESentence(format: NSLocalizedString("Join data on [#], [#] rows without matches", comment: ""),
				QBESentenceFormulaToken(expression: self.condition ?? Literal(Value.bool(false)), locale: locale, callback: { [weak self] (newExpression) -> () in
					self?.condition = newExpression
				}, contextCallback: self.contextCallbackForFormulaSentence),
				joinTypeSentenceItem
			)
		}
	}
	
	private func join(_ right: Dataset) -> Join? {
		if let c = condition {
			return Join(type: joinType, foreignDataset: right, expression: c)
		}
		return nil
	}
	
	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		// Create two separate jobs for left and right data, so progress is equally counted
		let leftJob = Job(parent: job)
		let rightJob = Job(parent: job)

		if let p = previous {
			p.fullDataset(leftJob) { leftDataset in
				if let r = self.right, let h = r.head {
					h.fullDataset(rightJob) { rightDataset in
						switch rightDataset {
							case .success(let rd):
								if let j = self.join(rd) {
									callback(leftDataset.use({$0.join(j)}))
								}
								else {
									callback(.failure(NSLocalizedString("Not all information was available to perform the join.", comment: "")))
								}
							
							case .failure(_):
								callback(rightDataset)
						}
					}
				}
				else {
					callback(.failure(NSLocalizedString("The data to join with was not found.", comment: "")))
				}
			}
		}
		else {
			callback(.failure(NSLocalizedString("A join step was not placed after another step.", comment: "")))
		}
	}
	
	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		if let p = previous {
			// Create two separate jobs for left and right data, so progress is equally counted
			let leftJob = Job(parent: job)
			let rightJob = Job(parent: job)

			p.exampleDataset(leftJob, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows) {(leftDataset) -> () in
				switch leftDataset {
					case .success(let ld):
						if let r = self.right, let h = r.head {
							h.exampleDataset(rightJob, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: { (rightDataset) -> () in
								switch rightDataset {
									case .success(let rd):
										if let j = self.join(rd) {
											callback(.success(ld.join(j)))
										}
										else {
											callback(.failure(NSLocalizedString("Not all information was available to perform the join.", comment: "")))
										}
									
									case .failure(_):
										callback(rightDataset)
								}
							})
						}
						else {
							callback(.failure(NSLocalizedString("The data to join with was not found.", comment: "")))
						}
					case .failure(_):
						callback(leftDataset)
				}
			}
		}
		else {
			callback(.failure(NSLocalizedString("A join step was not placed after another step.", comment: "")))
		}
	}
	
	override func apply(_ data: Dataset, job: Job?, callback: @escaping (Fallible<Dataset>) -> ()) {
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
				if !constantValue.isValid || constantValue == Value.bool(false) {
					return true
				}
			}

			return false
		}
		else {
			return false
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

	private func setSimpleCondition(sibling: Column?, foreign: Column?) {
		let currentType = self.simpleType ?? Binary.equal
		let first: Expression = (foreign != nil) ? Foreign(foreign!) : Literal(Value.invalid)
		let second: Expression = (sibling != nil) ? Sibling(sibling!) : Literal(Value.invalid)
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
		right = aDecoder.decodeObject(of: QBEChain.self, forKey: "right")
		super.init(coder: aDecoder)
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
		return QBESentence([QBESentenceLabelToken(NSLocalizedString("Merge data", comment: ""))])
	}
	
	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		if let p = previous {
			p.fullDataset(job) {(leftDataset) -> () in
				if let r = self.right, let h = r.head {
					h.fullDataset(job) { (rightDataset) -> () in
						switch rightDataset {
							case .success(let rd):
								callback(leftDataset.use {$0.union(rd)})
								
							case .failure(_):
								callback(rightDataset)
						}
					}
				}
				else {
					callback(.failure(NSLocalizedString("The data to merge with was not found.", comment: "")))
				}
			}
		}
		else {
			callback(.failure(NSLocalizedString("A merge step was not placed after another step.", comment: "")))
		}
	}
	
	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		if let p = previous {
			p.exampleDataset(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows) {(leftDataset) -> () in
				switch leftDataset {
				case .success(let ld):
					if let r = self.right, let h = r.head {
						h.exampleDataset(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: { (rightDataset) -> () in
							switch rightDataset {
								case .success(let rd):
									callback(.success(ld.union(rd)))
									
								case .failure(_):
									callback(rightDataset)
							}
						})
					}
					else {
						callback(.failure(NSLocalizedString("The data to merge with was not found.", comment: "")))
					}
				case .failure(_):
					callback(leftDataset)
				}
			}
		}
		else {
			callback(.failure(NSLocalizedString("A merge step was not placed after another step.", comment: "")))
		}
	}
	
	override func apply(_ data: Dataset, job: Job?, callback: @escaping (Fallible<Dataset>) -> ()) {
		fatalError("QBEMergeStep.apply should not be used")
	}
}
