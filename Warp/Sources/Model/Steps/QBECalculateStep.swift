import Foundation
import WarpCore

class QBECalculateStep: QBEStep {
	var function: Expression
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
			data.columnNames(job) { (columnNames) in
				callback(columnNames.use { (var cns: [Column]) -> Data in
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
				data.columnNames(job) { (columnNames: Fallible<[Column]>) -> () in
					switch columnNames {
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
						if col.columnName == p.targetColumn {
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
				let before = self.insertBefore ?? p.insertBefore
				return QBEStepMerge.Advised(QBECalculateStep(previous: previous, targetColumn: targetColumn, function: function, insertRelativeTo: relativeTo, insertBefore: before))
			}
		}
		
		return QBEStepMerge.Impossible
	}
	
	class func suggest(change fromValue: Value, toValue: Value, inRaster: Raster, row: Int, column: Int, locale: Locale, job: Job?) -> [Expression] {
		var suggestions: [Expression] = []
		if fromValue != toValue {			
			// Was a formula typed in?

			if let f = Formula(formula: toValue.stringValue ?? "", locale: locale) where !(f.root is Literal) && !(f.root is Identity) {
				// Replace occurrences of the identity with a reference to this column (so users can type '@/1000')
				let newFormula = f.root.visit { e -> Expression in
					if e is Identity {
						return Sibling(columnName: inRaster.columnNames[column])
					}
					return e
				}
				suggestions.append(newFormula)
			}
			Expression.infer(Literal(fromValue), toValue: toValue, suggestions: &suggestions, level: 8, row: Row(inRaster[row], columnNames: inRaster.columnNames), column: column, job: job)
		}
		return suggestions
	}
}