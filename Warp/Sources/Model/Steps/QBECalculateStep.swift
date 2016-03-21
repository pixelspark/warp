import Foundation
import WarpCore

private extension Expression {
	static let permutationLimit = 1000

	/** Generate all possible permutations of this expression by replacing sibling and identity references in this 
	expression by sibling references in the given set of columns (or an identiy reference). */
	private func permutationsUsing(columns: Set<Column>, limit: Int = Expression.permutationLimit) -> Set<Expression> {
		let replacements = columns.map { Sibling($0) } + [Identity()]
		let substitutes = self.siblingDependencies.map { Sibling($0) } + [Identity()]

		let v = self.generateVariants(self, replacing: ArraySlice(substitutes), with: replacements, limit: limit)

		return v
	}

	private func generateVariants(expression: Expression, replacing: ArraySlice<Expression>, with: [Expression], limit: Int) -> Set<Expression> {
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
					results.unionInPlace(self.generateVariants(newExpression, replacing: remaining, with: with, limit: subLimit))
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

	private class var sharedInstance : QBEHistory {
		struct Static {
			static var onceToken : dispatch_once_t = 0
			static var instance : QBEHistory? = nil
		}

		dispatch_once(&Static.onceToken) {
			Static.instance = QBEHistory()
		}
		return Static.instance!
	}

	var expressions: Set<Expression> = []

	/** Add an expression to the history, limiting the expression history list to a specified amount of entries. */
	func addExpression(expression: Expression) {
		if !expressions.contains(expression) {
			while expressions.count > (self.historyLimit - 1) {
				expressions.removeFirst()
			}

			expressions.insert(expression)
		}
	}

	/** Suggest new expressions based on the older expressions, but given the presence of certain columns (columns that
	existed in the original expression are assumed to be non-existent if they are not in the given set).*/
	func suggestExpressionsGiven(columns: Set<Column>) -> Set<Expression> {
		var variants: Set<Expression> = []

		for e in expressions {
			variants.unionInPlace(e.permutationsUsing(columns))
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
		function = (aDecoder.decodeObjectForKey("function") as? Expression) ?? Identity()
		targetColumn = Column((aDecoder.decodeObjectForKey("targetColumn") as? String) ?? "")
		QBEHistory.sharedInstance.addExpression(function)
		
		if let after = aDecoder.decodeObjectForKey("insertAfter") as? String {
			insertRelativeTo = Column(after)
		}
		
		/* Older versions of Warp do not encode this key and assume insert after (hence the relative column is coded as 
		'insertAfter'). As decodeBoolForKey defaults to false for keys it cannot find, this is the expected behaviour. */
		self.insertBefore = aDecoder.decodeBoolForKey("insertBefore")
		
		super.init(coder: aDecoder)
	}
	
	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: NSLocalizedString("Calculate column [#] as [#]", comment: ""),
			QBESentenceTextInput(value: self.targetColumn.name, callback: { [weak self] (newName) -> (Bool) in
				if !newName.isEmpty {
					self?.targetColumn = Column(newName)
					return true
				}
				return false
			}),
			QBESentenceFormula(expression: self.function, locale: locale, callback: { [weak self] (newExpression) -> () in
				self?.function = newExpression
			})
		)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(function, forKey: "function")
		coder.encodeObject(targetColumn.name, forKey: "targetColumn")
		coder.encodeObject(insertRelativeTo?.name, forKey: "insertAfter")
		coder.encodeBool(insertBefore, forKey: "insertBefore")
		super.encodeWithCoder(coder)
	}
	
	required init(previous: QBEStep?, targetColumn: Column, function: Expression, insertRelativeTo: Column? = nil, insertBefore: Bool = false) {
		self.function = function
		self.targetColumn = targetColumn
		self.insertRelativeTo = insertRelativeTo
		self.insertBefore = insertBefore
		super.init(previous: previous)
	}
	
	override func apply(data: Data, job: Job, callback: (Fallible<Data>) -> ()) {
		let result = data.calculate([targetColumn: function])
		if let relativeTo = insertRelativeTo {
			// Reorder columns in the result set so that targetColumn is inserted after insertAfter
			data.columns(job) { (columns) in
				callback(columns.use { (var cns: [Column]) -> Data in
					cns.remove(self.targetColumn)
					if let idx = cns.indexOf(relativeTo) {
						if self.insertBefore {
							cns.insert(self.targetColumn, atIndex: idx)
						}
						else {
							cns.insert(self.targetColumn, atIndex: idx+1)
						}
					}
					return result.selectColumns(cns)
				})
			}
		}
		else {
			// If the column is to be added at the beginning, shuffle columns around (the default is to add at the end
			if insertRelativeTo == nil && insertBefore {
				data.columns(job) { (columns: Fallible<[Column]>) -> () in
					switch columns {
						case .Success(let cns):
							var columns = cns
							columns.remove(self.targetColumn)
							columns.insert(self.targetColumn, atIndex: 0)
							callback(.Success(result.selectColumns(columns)))
						
						case .Failure(let error):
							callback(.Failure(error))
					}
				}
			}
			else {
				callback(.Success(result))
			}
		}
	}
	
	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		// FIXME: what to do with insertAfter?
		if let p = prior as? QBECalculateStep where p.targetColumn == self.targetColumn {
			var dependsOnPrevious = false
			
			// If this function is not constant, it may depend on another column
			if !function.isConstant {
				// Check whether this calculation overwrites the previous result, or depends on its outcome
				self.function.visit {(expr) -> () in
					if let col  = expr as? Sibling {
						if col.column == p.targetColumn {
							// This expression depends on the column produced by the previous one, hence it cannot overwrite it
							dependsOnPrevious = true
						}
					}
					else if expr is Identity {
						dependsOnPrevious = true
					}
				}
			}
			
			if !dependsOnPrevious {
				let relativeTo = self.insertRelativeTo ?? p.insertRelativeTo
				let before = relativeTo == self.insertRelativeTo ? self.insertBefore : p.insertBefore
				return QBEStepMerge.Advised(QBECalculateStep(previous: previous, targetColumn: targetColumn, function: function, insertRelativeTo: relativeTo, insertBefore: before))
			}
		}
		
		return QBEStepMerge.Impossible
	}
	
	class func suggest(change fromValue: Value?, toValue: Value, inRaster: Raster, row: Int, column: Int?, locale: Locale, job: Job?) -> [Expression] {
		var suggestions: [Expression] = []
		if fromValue != toValue {
			// Was a formula typed in?
			if let f = Formula(formula: toValue.stringValue ?? "", locale: locale) where !(f.root is Literal) && !(f.root is Identity) {
				// Replace occurrences of the identity with a reference to this column (so users can type '@/1000')
				let newFormula = f.root.visit { e -> Expression in
					if e is Identity {
						if let c = column {
							return Sibling(inRaster.columns[c])
						}
						else {
							return Literal(.InvalidValue)
						}
					}
					return e
				}
				suggestions.append(newFormula)
			}

			// Maybe there is an expression in the history that may be of help
			for e in QBEHistory.sharedInstance.suggestExpressionsGiven(Set(inRaster.columns)) {
				if e.apply(Row(inRaster[row], columns: inRaster.columns), foreign: nil, inputValue: fromValue) == toValue {
					trace("Suggesting from history: \(e.toFormula(locale))")
					suggestions.append(e)
				}
			}

			Expression.infer(fromValue != nil ? Literal(fromValue!): nil, toValue: toValue, suggestions: &suggestions, level: 8, row: Row(inRaster[row], columns: inRaster.columns), column: column, job: job)
		}
		return suggestions
	}
}