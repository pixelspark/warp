import Foundation
import WarpCore

class QBERenameStep: QBEStep {
	var renames: [Column: Column] = [:]

	required init() {
		super.init()
	}
	
	init(previous: QBEStep?, renames: [Column:Column] = [:]) {
		self.renames = renames
		super.init(previous: previous)
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		if renames.isEmpty {
			return QBESentence([QBESentenceLabelToken(NSLocalizedString("Rename columns", comment: ""))])
		}
		else if renames.count < 4{
			let sentence = QBESentence(format: "Rename column".localized)

			var n = 0
			for (old, new) in renames {
				let last = (n == (renames.count - 1))
				let secondLast = (n == (renames.count - 2))
				sentence.append(QBESentence(format: (secondLast ? "[#] to [#], and " : (last ? "[#] to [#]" : "[#] to [#], ")).localized,
					QBESentenceTextToken(value: old.name, callback: { [weak self] (newOld) -> (Bool) in
						if !newOld.isEmpty {
							self?.renames[Column(newOld)] = self?.renames.removeValue(forKey: old)
							return true
						}
						return false
					}),
					QBESentenceTextToken(value: new.name, callback: { [weak self] (newNew) -> (Bool) in
						if !newNew.isEmpty {
							self?.renames[old] = Column(newNew)
							return true
						}
						return false
					})
				))
				n += 1
			}
			return sentence
		}
		else {
			return QBESentence([QBESentenceLabelToken(String(format: NSLocalizedString("Rename %d columns", comment: ""), renames.count))])
		}
	}
	
	required init(coder aDecoder: NSCoder) {
		let renames = (aDecoder.decodeObject(forKey: "renames") as? [String:String]) ?? [:]
		self.renames = [:]
		
		for (key, value) in renames {
			self.renames[Column(key)] = Column(value)
		}
		super.init(coder: aDecoder)
	}
	
	override func encode(with coder: NSCoder) {
		var renames: [String: String] = [:]
		for (key, value) in self.renames {
			renames[key.name] = value.name
		}
		coder.encode(renames, forKey: "renames")
		super.encode(with: coder)
	}
	
	override func apply(_ data: Dataset, job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		// If we have nothing to rename, bypass this step
		if self.renames.isEmpty {
			callback(.success(data))
			return
		}
		
		data.columns(job) { (existingColumnsFallible) -> () in
			callback(existingColumnsFallible.use {(existingColumnNames) -> Dataset in
				var calculations: [Column: Expression] = [:]
				var newColumns: OrderedSet<Column> = []
				
				// Create a calculation that performs the rename
				for oldName in existingColumnNames {
					if let newName = self.renames[oldName], newName != oldName {
						if !newColumns.contains(newName) {
							calculations[newName] = Sibling(oldName)
							newColumns.append(newName)
						}
					}
					else {
						newColumns.append(oldName)
					}
				}
				return data.calculate(calculations).selectColumns(newColumns)
			})
		}
	}
	
	override func mergeWith(_ prior: QBEStep) -> QBEStepMerge {
		if let p = prior as? QBERenameStep {
			var renames = p.renames
			
			// Find out which columns are created by the prior step
			var renamed: [Column: Column] = [:]
			for (old, new) in renames {
				renamed[new] = old
			}
			
			// Merge our renames with the previous ones
			for (old, new) in self.renames {
				if let older = renamed[old] {
					// We are renaming a column that was renamed previously, overwrite the rename
					renames[older] = new
				}
				else {
					renames[old] = new
				}
			}
			self.renames = renames
			
			// This step can ony be a further subset of the columns selected by the prior
			return QBEStepMerge.advised(self)
		}
		else if let p = prior as? QBECalculateStep {
			if let firstRename = self.renames.first, self.renames.count == 1 && firstRename.0 == p.targetColumn {
				let newCalculate = QBECalculateStep(previous: p.previous, targetColumn: firstRename.1, function: p.function)
				return QBEStepMerge.advised(newCalculate)
			}
		}
		return QBEStepMerge.impossible
	}

	override func related(job: Job, callback: @escaping (Fallible<[QBERelatedStep]>) -> ()) {
		super.related(job: job) { result in
			switch result {
			case .success(let relatedSteps):
				return callback(.success(relatedSteps.flatMap { related -> QBERelatedStep? in
					switch related {
					case .joinable(step: let joinStep, type: let joinType, condition: let expression):
						// Rewrite the join expression to take into account any of our renames
						let newExpression = expression.visit { e -> Expression in
							if let sibling = e as? Sibling, let newName = self.renames[sibling.column] {
								return Sibling(newName)
							}

							return e
						}

						return .joinable(step: joinStep, type: joinType, condition: newExpression)
					}
				}))

			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}
}
