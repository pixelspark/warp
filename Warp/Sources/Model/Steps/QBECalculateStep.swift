import Foundation
import WarpCore

fileprivate extension Expression {
	static let permutationLimit = 1000

	/** Generate all possible permutations of this expression by replacing sibling and identity references in this 
	expression by sibling references in the given set of columns (or an identiy reference). */
	func permutationsUsing(_ columns: Set<Column>, limit: Int = Expression.permutationLimit) -> Set<Expression> {
		let replacements = columns.map { Sibling($0) } + [Identity()]
		let substitutes = self.siblingDependencies.map { Sibling($0) } + [Identity()]

		let v = self.generateVariants(self, replacing: ArraySlice(substitutes), with: replacements, limit: limit)

		return v
	}

	func generateVariants(_ expression: Expression, replacing: ArraySlice<Expression>, with: [Expression], limit: Int) -> Set<Expression> {
		assert(limit >= 0, "Limit cannot be negative")
		if limit == 0 {
			return []
		}

		if let first = replacing.first {
			let remaining = replacing.dropFirst()

			var results: Set<Expression> = []
			for w in with {
				let newExpression = expression.visit { e -> Expression in
					if e == first {
						return w
					}
					return e
				}

				let subLimit = limit - results.count
				if subLimit > 0 {
					results.formUnion(self.generateVariants(newExpression, replacing: remaining, with: with, limit: subLimit))
				}
				else {
					break
				}
			}
			return results
		}
		else {
			return [expression]
		}
	}
}

/** This class keeps track of calculation expressions used earlier/elsewhere. It can be invoked to suggest derivate 
expressions in which the sibling references are replaced with siblings that actually exist in the new context. */
private class QBEHistory {
	let historyLimit = 50

	static let sharedInstance = QBEHistory()
	var expressions: Set<Expression> = []

	/** Add an expression to the history, limiting the expression history list to a specified amount of entries. */
	func addExpression(_ expression: Expression) {
		if !expressions.contains(expression) {
			while expressions.count > (self.historyLimit - 1) {
				expressions.removeFirst()
			}

			expressions.insert(expression)
		}
	}

	/** Suggest new expressions based on the older expressions, but given the presence of certain columns (columns that
	existed in the original expression are assumed to be non-existent if they are not in the given set).*/
	func suggestExpressionsGiven(_ columns: Set<Column>) -> Set<Expression> {
		var variants: Set<Expression> = []

		for e in expressions {
			variants.formUnion(e.permutationsUsing(columns))
		}

		return variants
	}
}

class QBECalculateStep: QBEStep {
	var function: Expression { didSet { QBEHistory.sharedInstance.addExpression(function) } }
	var targetColumn: Column
	var insertRelativeTo: Column? = nil
	var insertBefore: Bool = false

	required init() {
		function = Identity()
		targetColumn = ""
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		function = (aDecoder.decodeObject(forKey: "function") as? Expression) ?? Identity()
		targetColumn = Column((aDecoder.decodeObject(forKey: "targetColumn") as? String) ?? "")
		QBEHistory.sharedInstance.addExpression(function)
		
		if let after = aDecoder.decodeObject(forKey: "insertAfter") as? String {
			insertRelativeTo = Column(after)
		}
		
		/* Older versions of Warp do not encode this key and assume insert after (hence the relative column is coded as 
		'insertAfter'). As decodeBoolForKey defaults to false for keys it cannot find, this is the expected behaviour. */
		self.insertBefore = aDecoder.decodeBool(forKey: "insertBefore")
		
		super.init(coder: aDecoder)
	}
	
	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: NSLocalizedString("Calculate column [#] as [#]", comment: ""),
			QBESentenceTextToken(value: self.targetColumn.name, callback: { [weak self] (newName) -> (Bool) in
				if !newName.isEmpty {
					self?.targetColumn = Column(newName)
					return true
				}
				return false
			}),
			QBESentenceFormulaToken(expression: self.function, locale: locale, callback: { [weak self] (newExpression) -> () in
				self?.function = newExpression
			}, contextCallback: self.contextCallbackForFormulaSentence)
		)
	}
	
	override func encode(with coder: NSCoder) {
		coder.encode(function, forKey: "function")
		coder.encode(targetColumn.name, forKey: "targetColumn")
		coder.encode(insertRelativeTo?.name, forKey: "insertAfter")
		coder.encode(insertBefore, forKey: "insertBefore")
		super.encode(with: coder)
	}
	
	required init(previous: QBEStep?, targetColumn: Column, function: Expression, insertRelativeTo: Column? = nil, insertBefore: Bool = false) {
		self.function = function
		self.targetColumn = targetColumn
		self.insertRelativeTo = insertRelativeTo
		self.insertBefore = insertBefore
		super.init(previous: previous)
	}
	
	override func apply(_ data: Dataset, job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		let result = data.calculate([targetColumn: function])
		if let relativeTo = insertRelativeTo {
			// Reorder columns in the result set so that targetColumn is inserted after insertAfter
			data.columns(job) { (columns) in
				callback(columns.use { (cns: OrderedSet<Column>) -> Dataset in
					var cns = cns
					cns.remove(self.targetColumn)
					if let idx = cns.index(of: relativeTo) {
						if self.insertBefore {
							cns.insert(self.targetColumn, at: idx)
						}
						else {
							cns.insert(self.targetColumn, at: idx+1)
						}
					}
					return result.selectColumns(cns)
				})
			}
		}
		else {
			// If the column is to be added at the beginning, shuffle columns around (the default is to add at the end
			if insertRelativeTo == nil && insertBefore {
				data.columns(job) { (columns: Fallible<OrderedSet<Column>>) -> () in
					switch columns {
						case .success(let cns):
							var columns = cns
							columns.remove(self.targetColumn)
							columns.insert(self.targetColumn, at: 0)
							callback(.success(result.selectColumns(columns)))
						
						case .failure(let error):
							callback(.failure(error))
					}
				}
			}
			else {
				callback(.success(result))
			}
		}
	}
	
	override func mergeWith(_ prior: QBEStep) -> QBEStepMerge {
		// FIXME: what to do with insertAfter?
		if let p = prior as? QBECalculateStep, p.targetColumn == self.targetColumn {
			var dependsOnPrevious = false
			var otherDependenciesThanIdentity = false
			
			// If this function is not constant, it may depend on another column
			if !function.isConstant {
				// Check whether this calculation overwrites the previous result, or depends on its outcome
				self.function.visit {(expr) -> () in
					if let col  = expr as? Sibling {
						if col.column == p.targetColumn {
							// This expression depends on the column produced by the previous one, hence it cannot overwrite it
							dependsOnPrevious = true
							otherDependenciesThanIdentity = true
						}
					}
					else if expr is Identity {
						dependsOnPrevious = true
					}
				}
			}
			
			if !dependsOnPrevious {
				// The new step recalculates the column and makes the earlier calculation step irrelevant
				let relativeTo = self.insertRelativeTo ?? p.insertRelativeTo
				let before = relativeTo == self.insertRelativeTo ? self.insertBefore : p.insertBefore
				return QBEStepMerge.advised(QBECalculateStep(previous: previous, targetColumn: targetColumn, function: function, insertRelativeTo: relativeTo, insertBefore: before))
			}
			else if !otherDependenciesThanIdentity {
				// We can safely 'wrap' the earlier calculation
				return QBEStepMerge.advised(QBECalculateStep(
					previous: p.previous,
					targetColumn: targetColumn,
					function: self.function.expressionReplacingIdentityReferencesWith(p.function),
					insertRelativeTo: p.insertRelativeTo,
					insertBefore: p.insertBefore
				))
			}
		}
		
		return QBEStepMerge.impossible
	}
	
	class func suggest(change fromValue: Value?, toValue: Value, inRaster: Raster, row: Int, column: Int?, locale: Language, job: Job?) -> [Expression] {
		var suggestions: [Expression] = []
		if fromValue != toValue {
			// Was a formula typed in?
			if let f = Formula(formula: toValue.stringValue ?? "", locale: locale), !(f.root is Literal) && !(f.root is Identity) {
				// Replace occurrences of the identity with a reference to this column (so users can type '@/1000')
				let newFormula = f.root.visit { e -> Expression in
					if e is Identity {
						if let c = column {
							return Sibling(inRaster.columns[c])
						}
						else {
							return Literal(.invalid)
						}
					}
					return e
				}
				suggestions.append(newFormula)

				// If this was definitely a formula, do not suggest anything else
				if let tv = toValue.stringValue, tv.hasPrefix(Formula.prefix) {
					return Array(Set(suggestions)).sorted { a,b in return a.complexity < b.complexity }
				}
			}

			// Maybe there is an expression in the history that may be of help
			for e in QBEHistory.sharedInstance.suggestExpressionsGiven(Set(inRaster.columns)) {
				if e.apply(inRaster[row], foreign: nil, inputValue: fromValue) == toValue {
					trace("Suggesting from history: \(e.toFormula(locale))")
					suggestions.append(e)
				}
			}

			suggestions += Expression.infer(fromValue != nil ? Literal(fromValue!): nil, toValue: toValue, level: 3, row: inRaster[row], column: column, job: job)
		}
		return Array(Set(suggestions)).sorted { a,b in return a.complexity < b.complexity }
	}

	override func related(job: Job, callback: @escaping (Fallible<[QBERelatedStep]>) -> ()) {
		super.related(job: job) { result in
			switch result {
			case .success(let relatedSteps):
				return callback(.success(relatedSteps.flatMap { related -> QBERelatedStep? in
					switch related {
					case .joinable(step: _, type: _, condition: let expression):
						// Rewrite the join expression to take into account any of our renames
						var stillPossible = true
						expression.visit { e -> () in
							if let sibling = e as? Sibling, sibling.column == self.targetColumn {
								// Column we join on was recalculated
								stillPossible = false
							}
						}

						if stillPossible {
							return related
						}
						return nil
					}
					}))

			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}
}
