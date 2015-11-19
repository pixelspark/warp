import Foundation

internal let QBEExpressions: [QBEExpression.Type] = [
	QBESiblingExpression.self,
	QBELiteralExpression.self,
	QBEBinaryExpression.self,
	QBEFunctionExpression.self,
	QBEIdentityExpression.self
]

/** A QBEExpression is a 'formula' that evaluates to a certain QBEValue given a particular context. */
public class QBEExpression: NSObject, NSCoding {
	public func explain(locale: QBELocale, topLevel: Bool = true) -> String {
		return "??"
	}
	
	/** The complexity of an expression is an indication of how 'far fetched' it is - this is used by QBEInferer to 
	decide which expressions to suggest. */
	var complexity: Int { get {
		return 1
	}}
	
	/** Returns whether the result of this expression is independent of the row fed to it. An expression that reports it
	is constant is guaranteed to return a value for apply() called without a row, set of columns and input value. */
	public var isConstant: Bool { get {
		return false
	} }
	
	/** Returns a version of this expression that has constant parts replaced with their actual values. */
	func prepare() -> QBEExpression {
		if isConstant {
			return QBELiteralExpression(self.apply(QBERow(), foreign: nil, inputValue: nil))
		}
		return self
	}
	
	override init() {
	}
	
	public required init?(coder aDecoder: NSCoder) {
	}
	
	public func encodeWithCoder(aCoder: NSCoder) {
	}
	
	/** Returns a localized representation of this expression, which should (when parsed by QBEFormula in the same locale)
	result in an equivalent expression. */
	public func toFormula(locale: QBELocale, topLevel: Bool = false) -> String {
		return ""
	}
	
	/** Return true if, under all circumstances, this expression will return a result that is equal to the result returned
	by the other expression (QBEValue equality). */
	public func isEquivalentTo(expression: QBEExpression) -> Bool {
		return false
	}
	
	/** Requests that callback be called on self, and visit() forwarded to all children. This can be used to implement
	dependency searches, etc. */
	public func visit(@noescape callback: (QBEExpression) -> (QBEExpression)) -> QBEExpression {
		return callback(self)
	}
	
	@nonobjc public final func visit(@noescape callback: (QBEExpression) -> ()) {
		self.visit { (e) -> QBEExpression in
			callback(e)
			return e
		}
	}
	
	/** Calculate the result of this expression for the given row, columns and current input value. */
	public func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		fatalError("A QBEExpression was called that isn't implemented")
	}
	
	/** Returns a list of suggestions for applications of this expression on the given value (fromValue) that result in the
	given 'to' value (or bring the value closer to the toValue). */
	class func suggest(fromValue: QBEExpression?, toValue: QBEValue, row: QBERow, inputValue: QBEValue?, level: Int, job: QBEJob?) -> [QBEExpression] {
		return []
	}
	
	/** The infer function implements an algorithm to find one or more formulas that are able to transform an
	input value to a specific output value. It does so by looping over 'suggestions' (provided by QBEFunction
	implementations) for the application of (usually unary) functions to the input value to obtain (or come closer to) the
	output value. */
	public class final func infer(fromValue: QBEExpression?, toValue: QBEValue, inout suggestions: [QBEExpression], level: Int, row: QBERow, column: Int, maxComplexity: Int = Int.max, previousValues: [QBEValue] = [], job: QBEJob? = nil) {
		let inputValue = row.values[column]
		if let c = job?.cancelled where c {
			return
		}
		
		// Try out combinations of formulas and see if they fit
		for formulaType in QBEExpressions {
			if let c = job?.cancelled where c {
				return
			}
			
			let suggestedFormulas = formulaType.suggest(fromValue, toValue: toValue, row: row, inputValue: inputValue, level: level, job: job);
			var complexity = maxComplexity
			var exploreFurther: [QBEExpression] = []
			
			for formula in suggestedFormulas {
				if formula.complexity >= maxComplexity {
					continue
				}
				
				let result = formula.apply(row, foreign: nil, inputValue: inputValue)
				if result == toValue {
					suggestions.append(formula)
					
					if formula.complexity < maxComplexity {
						complexity = formula.complexity
					}
				}
				else {
					if level > 0 {
						exploreFurther.append(formula)
					}
				}
			}
			
			if suggestions.isEmpty {
				// Let's see if we can find something else
				for formula in exploreFurther {
					let result = formula.apply(row, foreign: nil, inputValue: inputValue)
					
					// Have we already seen this result? Then ignore
					var found = false
					for previous in previousValues {
						if previous == result {
							found = true
							break
						}
					}
					
					if found {
						continue
					}
					
					var nextLevelSuggestions: [QBEExpression] = []
					var newPreviousValues = previousValues
					newPreviousValues.append(result)
					infer(formula, toValue: toValue, suggestions: &nextLevelSuggestions, level: level-1, row: row, column: column, maxComplexity: complexity, previousValues: newPreviousValues, job: job)
					
					for nextLevelSuggestion in nextLevelSuggestions {
						if nextLevelSuggestion.apply(row, foreign: nil, inputValue: inputValue) == toValue {
							if nextLevelSuggestion.complexity <= complexity {
								suggestions.append(nextLevelSuggestion)
								complexity = nextLevelSuggestion.complexity
							}
						}
					}
				}
			}
		}
	}
}

/** The QBELiteralExpression always evaluates to the value set to it on initialization. The formula parser generates a
QBELiteralExpression for each literal (numbers, strings, constants) it encounters. */
public final class QBELiteralExpression: QBEExpression {
	public let value: QBEValue
	
	public init(_ value: QBEValue) {
		self.value = value
		super.init()
	}
	
	override var complexity: Int { get {
		return 10
	}}
	
	public override var isConstant: Bool { get {
		return true
	} }
	
	public required init?(coder aDecoder: NSCoder) {
		self.value = ((aDecoder.decodeObjectForKey("value") as? QBEValueCoder) ?? QBEValueCoder()).value
		super.init(coder: aDecoder)
	}
	
	public override func explain(locale: QBELocale, topLevel: Bool) -> String {
		return locale.localStringFor(value)
	}
	
	public override func toFormula(locale: QBELocale, topLevel: Bool) -> String {
		switch value {
		case .StringValue(let s):
			let escaped = s.stringByReplacingOccurrencesOfString(String(locale.stringQualifier), withString: locale.stringQualifierEscape)
			return "\(locale.stringQualifier)\(escaped)\(locale.stringQualifier)"
			
		case .DoubleValue(let d):
			return locale.numberFormatter.stringFromNumber(NSNumber(double: d)) ?? ""
			
		case .DateValue(let d):
			return "@" + (locale.numberFormatter.stringFromNumber(NSNumber(double: d)) ?? "")
			
		case .BoolValue(let b):
			return locale.constants[QBEValue(b)]!
			
		case .IntValue(let i):
			return "\(i)"
		
		case .InvalidValue: return locale.constants[QBEValue.EmptyValue]!
		case .EmptyValue: return locale.constants[QBEValue.EmptyValue]!
		}
	}
	
	public override func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(QBEValueCoder(self.value), forKey: "value")
		super.encodeWithCoder(aCoder)
	}
	
	public override func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		return value
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, row: QBERow, inputValue: QBEValue?, level: Int, job: QBEJob?) -> [QBEExpression] {
		if fromValue == nil {
			return [QBELiteralExpression(toValue)]
		}
		return []
	}
	
	public override func isEquivalentTo(expression: QBEExpression) -> Bool {
		if let otherLiteral = expression as? QBELiteralExpression {
			return otherLiteral.value == self.value
		}
		return false
	}
}

/** The QBEIdentityExpression returns whatever value was set to the inputValue parameter during evaluation. This value
usually represents the (current) value in the current cell. */
public class QBEIdentityExpression: QBEExpression {
	public override init() {
		super.init()
	}
	
	public override func explain(locale: QBELocale, topLevel: Bool) -> String {
		return QBEText("current value")
	}

	public override func toFormula(locale: QBELocale, topLevel: Bool) -> String {
		return locale.currentCellIdentifier
	}
	
	public required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	public override func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		return inputValue ?? QBEValue.InvalidValue
	}
	
	public override func isEquivalentTo(expression: QBEExpression) -> Bool {
		return expression is QBEIdentityExpression
	}
}

/** QBEBinaryExpression evaluates to the result of applying a particular binary operator to two operands, which are 
other expressions. */
public final class QBEBinaryExpression: QBEExpression {
	public let first: QBEExpression
	public let second: QBEExpression
	public var type: QBEBinary
	
	public override var isConstant: Bool { get {
		return first.isConstant && second.isConstant
	} }
	
	override func prepare() -> QBEExpression {
		let firstOptimized = first.prepare()
		let secondOptimized = second.prepare()
		
		/* If first and second operand are equivalent, the result of '==' or '<>' is always known (even when the operands 
		are not constant, e.g. sibling or foreign references) */
		if firstOptimized.isEquivalentTo(secondOptimized) {
			switch self.type {
				case .Equal, .LesserEqual, .GreaterEqual:
					return QBELiteralExpression(QBEValue.BoolValue(true))

				case .NotEqual, .Greater, .Lesser:
					return QBELiteralExpression(QBEValue.BoolValue(false))
				
				default:
					break;
			}
		}
		
		// If the first and second operand are constant, the result of the binary expression can likely be precalculated
		let optimized = QBEBinaryExpression(first: firstOptimized, second: secondOptimized, type: self.type)
		if optimized.isConstant {
			return QBELiteralExpression(optimized.apply(QBERow(), foreign: nil, inputValue: nil))
		}
		return optimized
	}
	
	public override func visit(@noescape callback: (QBEExpression) -> (QBEExpression)) -> QBEExpression {
		let first = self.first.visit(callback)
		let second = self.second.visit(callback)
		let newSelf = QBEBinaryExpression(first: first, second: second, type: self.type)
		return callback(newSelf)
	}
	
	public override func explain(locale: QBELocale, topLevel: Bool) -> String {
		return (topLevel ? "": "(") + second.explain(locale, topLevel: false) + " " + type.explain(locale) + " " + first.explain(locale, topLevel: false) + (topLevel ? "": ")")
	}
	
	public override func toFormula(locale: QBELocale, topLevel: Bool) -> String {
		let start = topLevel ? "" : "("
		let end = topLevel ? "" : ")"
		return "\(start)\(second.toFormula(locale))\(type.toFormula(locale))\(first.toFormula(locale))\(end)"
	}
	
	override var complexity: Int { get {
		return first.complexity + second.complexity + 1
	}}
	
	public init(first: QBEExpression, second: QBEExpression, type: QBEBinary) {
		self.first = first
		self.second = second
		self.type = type
		super.init()
	}
	
	public required init?(coder aDecoder: NSCoder) {
		self.first = (aDecoder.decodeObjectForKey("first") as? QBEExpression) ?? QBEIdentityExpression()
		self.second = (aDecoder.decodeObjectForKey("second") as? QBEExpression) ?? QBEIdentityExpression()
		let typeString = (aDecoder.decodeObjectForKey("type") as? String) ?? QBEBinary.Addition.rawValue
		self.type = QBEBinary(rawValue: typeString) ?? QBEBinary.Addition
		super.init(coder: aDecoder)
	}
	
	public override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(first, forKey: "first")
		aCoder.encodeObject(second, forKey: "second")
		aCoder.encodeObject(type.rawValue, forKey: "type")
	}
	
	public override func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		let left = second.apply(row, foreign: foreign, inputValue: nil)
		let right = first.apply(row, foreign: foreign, inputValue: nil)
		return self.type.apply(left, right)
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, row: QBERow, inputValue: QBEValue?, level: Int, job: QBEJob?) -> [QBEExpression] {
		var suggestions: [QBEExpression] = []
		
		if let from = fromValue {
			if let f = fromValue?.apply(row, foreign: nil, inputValue: inputValue) {
				if level > 1 {
					if let targetDouble = toValue.doubleValue {
						if let fromDouble = f.doubleValue {
							// Suggest addition or subtraction
							let difference = targetDouble - fromDouble
							if difference != 0 {
								var addSuggestions: [QBEExpression] = []
								QBEExpression.infer(nil, toValue: QBEValue(abs(difference)), suggestions: &addSuggestions, level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
								
								if difference > 0 {
									addSuggestions.forEach({suggestions.append(QBEBinaryExpression(first: $0, second: from, type: QBEBinary.Addition))})
								}
								else {
									addSuggestions.forEach({suggestions.append(QBEBinaryExpression(first: $0, second: from, type: QBEBinary.Subtraction))})
								}
							}
							
							// Suggest division or multiplication
							if fromDouble != 0 {
								let dividend = targetDouble / fromDouble
								
								var mulSuggestions: [QBEExpression] = []
								QBEExpression.infer(nil, toValue: QBEValue(dividend < 1 ? (1/dividend) : dividend), suggestions: &mulSuggestions, level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
								
								if dividend >= 1 {
									mulSuggestions.forEach({suggestions.append(QBEBinaryExpression(first: $0, second: from, type: QBEBinary.Multiplication))})
								}
								else {
									mulSuggestions.forEach({suggestions.append(QBEBinaryExpression(first: $0, second: from, type: QBEBinary.Division))})
								}
							}
						}
					}
					else if let targetString = toValue.stringValue, let fromString = f.stringValue {
						if !targetString.isEmpty && !fromString.isEmpty && fromString.characters.count < targetString.characters.count {
							// See if the target string shares a prefix with the source string
							let targetPrefix = targetString.substringWithRange(targetString.startIndex..<targetString.startIndex.advancedBy(fromString.characters.count))
							if fromString == targetPrefix {
								let postfix = targetString.substringWithRange(targetString.startIndex.advancedBy(fromString.characters.count)..<targetString.endIndex)
								print("'\(fromString)' => '\(targetString)' share prefix: '\(targetPrefix)' need postfix: '\(postfix)'")
								
								var postfixSuggestions: [QBEExpression] = []
								QBEExpression.infer(nil, toValue: QBEValue.StringValue(postfix), suggestions: &postfixSuggestions, level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
								
								postfixSuggestions.forEach({suggestions.append(QBEBinaryExpression(first: $0, second: from, type: QBEBinary.Concatenation))})
							}
							else {
								// See if the target string shares a postfix with the source string
								let prefixLength = targetString.characters.count - fromString.characters.count
								let targetPostfix = targetString.substringWithRange(targetString.startIndex.advancedBy(prefixLength)..<targetString.endIndex)
								if fromString == targetPostfix {
									let prefix = targetString.substringWithRange(targetString.startIndex..<targetString.startIndex.advancedBy(prefixLength))
									print("'\(fromString)' => '\(targetString)' share postfix: '\(targetPostfix)' need prefix: '\(prefix)'")
									
									var prefixSuggestions: [QBEExpression] = []
									QBEExpression.infer(nil, toValue: QBEValue.StringValue(prefix), suggestions: &prefixSuggestions, level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
									
									prefixSuggestions.forEach({suggestions.append(QBEBinaryExpression(first: from, second: $0, type: QBEBinary.Concatenation))})
								}
							}
						}
					}
				}
			}
		}
		
		return suggestions
	}
	
	public override func isEquivalentTo(expression: QBEExpression) -> Bool {
		if let otherBinary = expression as? QBEBinaryExpression {
			if otherBinary.type == self.type && otherBinary.first.isEquivalentTo(self.first) && otherBinary.second.isEquivalentTo(self.second) {
				return true
			}
			// A <> B is equivalent to B = A, so in these cases the binary expression is equivalent
			else if let mirror = self.type.mirror where otherBinary.type == mirror && otherBinary.first.isEquivalentTo(self.second) && otherBinary.second.isEquivalentTo(self.first) {
				return true
			}
		}
		
		return false
	}
}

/** QBEFunctionExpression evaluates to the result of applying a function to a given set of arguments. The set of arguments
consists of QBEExpressions that are evaluated before sending them to the function. */
public final class QBEFunctionExpression: QBEExpression {
	public let arguments: [QBEExpression]
	public let type: QBEFunction
	
	public override var isConstant: Bool { get {
		if !type.isDeterministic {
			return false
		}
		
		for a in arguments {
			if !a.isConstant {
				return false
			}
		}
		
		return true
	} }
	
	public override func visit(@noescape callback: (QBEExpression) -> (QBEExpression)) -> QBEExpression {
		let newArguments = arguments.map({$0.visit(callback)})
		return callback(QBEFunctionExpression(arguments: newArguments, type: self.type))
	}
	
	override func prepare() -> QBEExpression {
		return self.type.prepare(arguments)
	}
	
	public override func explain(locale: QBELocale, topLevel: Bool) -> String {
		let argumentsList = arguments.map({$0.explain(locale, topLevel: false)}).joinWithSeparator(", ")
		return "\(type.explain(locale))(\(argumentsList))"
	}
	
	public override func toFormula(locale: QBELocale, topLevel: Bool) -> String {
		let args = arguments.map({$0.toFormula(locale)}).joinWithSeparator(locale.argumentSeparator)
		return "\(type.toFormula(locale))(\(args))"
	}
	
	override var complexity: Int { get {
		var complexity = 1
		for a in arguments {
			complexity = max(complexity, a.complexity)
		}
		
		return complexity + 1
	}}
	
	public init(arguments: [QBEExpression], type: QBEFunction) {
		self.arguments = arguments
		self.type = type
		super.init()
	}
	
	public required init?(coder aDecoder: NSCoder) {
		self.arguments = (aDecoder.decodeObjectForKey("args") as? [QBEExpression]) ?? []
		let typeString = (aDecoder.decodeObjectForKey("type") as? String) ?? QBEFunction.Identity.rawValue
		self.type = QBEFunction(rawValue: typeString) ?? QBEFunction.Identity
		super.init(coder: aDecoder)
	}
	
	public override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(arguments, forKey: "args")
		aCoder.encodeObject(type.rawValue, forKey: "type")
	}
	
	public override func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		let vals = arguments.map({$0.apply(row, foreign: foreign, inputValue: inputValue)})
		return self.type.apply(vals)
	}
	
	public override func isEquivalentTo(expression: QBEExpression) -> Bool {
		if let otherFunction = expression as? QBEFunctionExpression {
			if otherFunction.type == self.type && self.arguments == otherFunction.arguments && self.type.isDeterministic {
				return true
			}
		}
		return false
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, row: QBERow, inputValue: QBEValue?, level: Int, job: QBEJob?) -> [QBEExpression] {
		var suggestions: [QBEExpression] = []
		
		if let from = fromValue {
			if let f = fromValue?.apply(row, foreign: nil, inputValue: inputValue) {
				// Check whether one of the unary functions can transform the input value to the output value
				for op in QBEFunction.allFunctions {
					if(op.arity.valid(1) && op.isDeterministic) {
						if op.apply([f]) == toValue {
							suggestions.append(QBEFunctionExpression(arguments: [from], type: op))
						}
					}
				}
				
				// For binary and n-ary functions, specific test cases follow
				var incompleteSuggestions: [QBEExpression] = []
				if let targetString = toValue.stringValue {
					let length = QBEValue(targetString.characters.count)

					// Is the 'to' string perhaps a substring of the 'from' string?
					if let sourceString = f.stringValue {
						// Let's see if we can extract this string using array logic. Otherwise suggest index-based string splitting
						var foundAsElement = false
						let separators = [" ", ",", ";", "\t", "|", "-", ".", "/", ":", "\\", "#", "=", "_", "(", ")", "[", "]"]
						for separator in separators {
							if let c = job?.cancelled where c {
								break
							}
							
							let splitted = sourceString.componentsSeparatedByString(separator)
							if splitted.count > 1 {
								let pack = QBEPack(splitted)
								for i in 0..<pack.count {
									let item = pack[i]
									let splitExpression = QBEFunctionExpression(arguments: [from, QBELiteralExpression(QBEValue.StringValue(separator))], type: QBEFunction.Split)
									let nthExpression = QBEFunctionExpression(arguments: [splitExpression, QBELiteralExpression(QBEValue.IntValue(i+1))], type: QBEFunction.Nth)
									if targetString == item {
										suggestions.append(nthExpression)
										foundAsElement = true
									}
									else {
										incompleteSuggestions.append(nthExpression)
									}
									
								}
							}
						}

						if !foundAsElement {
							if incompleteSuggestions.count > 0 {
								suggestions += incompleteSuggestions
							}
							else {
								if let range = sourceString.rangeOfString(targetString) {
									suggestions.append(QBEFunctionExpression(arguments: [from, QBELiteralExpression(length)], type: QBEFunction.Left))
									suggestions.append(QBEFunctionExpression(arguments: [from, QBELiteralExpression(length)], type: QBEFunction.Right))
									
									let start = QBELiteralExpression(QBEValue(sourceString.startIndex.distanceTo(range.startIndex)))
									let length = QBELiteralExpression(QBEValue(range.startIndex.distanceTo(range.endIndex)))
									suggestions.append(QBEFunctionExpression(arguments: [from, start, length], type: QBEFunction.Mid))
								}
							}
						}
					}
				}
			}
		}
		
		return suggestions
	}
}

protocol QBEColumnReferencingExpression {
	var columnName: QBEColumn { get }
}

/** The QBESiblingExpression evaluates to the value of a cell in a particular column on the same row as the current value. */
public final class QBESiblingExpression: QBEExpression, QBEColumnReferencingExpression {
	public var columnName: QBEColumn
	
	public init(columnName: QBEColumn) {
		self.columnName = columnName
		super.init()
	}
	
	public override func explain(locale: QBELocale, topLevel: Bool) -> String {
		return String(format: QBEText("value in column %@"), columnName.name)
	}
	
	public required init?(coder aDecoder: NSCoder) {
		columnName = QBEColumn((aDecoder.decodeObjectForKey("columnName") as? String) ?? "")
		super.init(coder: aDecoder)
	}
	
	public override func toFormula(locale: QBELocale, topLevel: Bool) -> String {
		return "[@\(columnName.name)]"
	}
	
	public override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(columnName.name, forKey: "columnName")
	}
	
	public override func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		return row[columnName] ?? QBEValue.InvalidValue
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, row: QBERow, inputValue: QBEValue?, level: Int, job: QBEJob?) -> [QBEExpression] {
		var s: [QBEExpression] = []
		if fromValue == nil {
			for columnName in row.columnNames {
				s.append(QBESiblingExpression(columnName: columnName))
			}
		}
		return s
	}
	
	public override func isEquivalentTo(expression: QBEExpression) -> Bool {
		if let otherSibling = expression as? QBESiblingExpression {
			return otherSibling.columnName == self.columnName
		}
		return false
	}
}

/** The QBEForeignExpression evaluates to the value of a cell in a particular column in the foreign row. This is used to 
evaluate whether two rows should be matched up in a join. If no foreign row is given, this expression gives an error. */
public final class QBEForeignExpression: QBEExpression, QBEColumnReferencingExpression {
	public var columnName: QBEColumn
	
	public init(columnName: QBEColumn) {
		self.columnName = columnName
		super.init()
	}
	
	public override func explain(locale: QBELocale, topLevel: Bool) -> String {
		return String(format: QBEText("value in foreign column %@"), columnName.name)
	}
	
	public required init?(coder aDecoder: NSCoder) {
		columnName = QBEColumn((aDecoder.decodeObjectForKey("columnName") as? String) ?? "")
		super.init(coder: aDecoder)
	}
	
	public override func toFormula(locale: QBELocale, topLevel: Bool) -> String {
		return "[#\(columnName.name)]"
	}
	
	public override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(columnName.name, forKey: "columnName")
	}
	
	public override func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		return foreign?[columnName] ?? QBEValue.InvalidValue
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, row: QBERow, inputValue: QBEValue?, level: Int, job: QBEJob?) -> [QBEExpression] {
		// TODO: implement when we are going to implement foreign suggestions
		return []
	}
	
	public override func isEquivalentTo(expression: QBEExpression) -> Bool {
		if let otherForeign = expression as? QBEForeignExpression {
			return otherForeign.columnName == self.columnName
		}
		return false
	}
}

public class QBEFilterSet: NSObject, NSCoding {
	public var selectedValues: Set<QBEValue> = []
	
	public override init() {
	}
	
	public required init?(coder aDecoder: NSCoder) {
		if let v = aDecoder.decodeObjectForKey("selectedValues") as? [QBEValueCoder] {
			selectedValues = Set(v.map({return $0.value}))
		}
	}
	
	public func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(Array<QBEValueCoder>(selectedValues.map({return QBEValueCoder($0)})), forKey: "selectedValues")
	}
	
	/** Returns an expression representing this filter. The source column is represented as QBEIdentityExpression. */
	public var expression: QBEExpression { get {
		var args: [QBEExpression] = [QBEIdentityExpression()]
		for value in selectedValues {
			args.append(QBELiteralExpression(value))
		}
		
		return QBEFunctionExpression(arguments: args, type: QBEFunction.In)
	} }
}

/** Functions defined on QBEExpression that rely on knowledge of its subclasses should be in this extension. */
extension QBEExpression {
	/** Returns a version of this expression that can be used to find matching rows in a foreign table. It replaces all
	occurences of QBEForeignExpression with QBESiblingExpression, and replaces instances QBESiblingExpression with the
	corresponding values from the row given. */
	final func expressionForForeignFiltering(row: QBERow) -> QBEExpression {
		return visit { (oldExpression) in
			if let old = oldExpression as? QBESiblingExpression {
				return QBELiteralExpression(old.apply(row, foreign: nil, inputValue: nil))
			}
			else if let old = oldExpression as? QBEForeignExpression {
				return QBESiblingExpression(columnName: old.columnName)
			}
			else {
				return oldExpression
			}
		}
	}
	
	/** Returns a version of this expression where all foreign references have been replaced by sibling references. The
	expression is not allowed to contain sibling references (in wich case this function will return nil) */
	final func expressionForForeignFiltering() -> QBEExpression? {
		var error = false
		
		let result = visit { (oldExpression) -> (QBEExpression) in
			if  oldExpression is QBESiblingExpression {
				error = true
				return oldExpression
			}
			else if let old = oldExpression as? QBEForeignExpression {
				return QBESiblingExpression(columnName: old.columnName)
			}
			else {
				return oldExpression
			}
		}
		
		if error {
			return nil
		}
		return result
	}
	
	/** Returns this expression with all occurences of QBEIdentityExpression replaced with the given new expression. */
	public final func expressionReplacingIdentityReferencesWith(newExpression: QBEExpression) -> QBEExpression {
		return visit { (oldExpression) in
			if oldExpression is QBEIdentityExpression {
				return newExpression
			}
			return oldExpression
		}
	}

	public var siblingDependencies: Set<QBEColumn> {
		var deps: Set<QBEColumn> = []

		visit { expression -> () in
			if let ex = expression as? QBESiblingExpression {
				deps.insert(ex.columnName)
			}
		}
		return deps
	}
	
	/** Returns whether this expression depends on sibling columns (e.g. contains a QBESiblingExpression somewhere in 
	its tree). */
	public var dependsOnSiblings: Bool { get {
		var depends = false
		visit { (expression) -> () in
			if expression is QBESiblingExpression {
				depends = true
			}
		}
		return depends
	} }

	/** Returns whether this expression depends on foreign columns (e.g. contains a QBEForeignExpression somewhere in
	its tree). */
	public var dependsOnForeigns: Bool { get {
		var depends = false
		visit { (expression) -> () in
			if expression is QBEForeignExpression {
				depends = true
			}
		}
		return depends
		} }
}