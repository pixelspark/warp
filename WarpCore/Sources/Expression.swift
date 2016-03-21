import Foundation

internal let expressions: [Expression.Type] = [
	Sibling.self,
	Literal.self,
	Comparison.self,
	Call.self,
	Identity.self
]

/** A Expression is a 'formula' that evaluates to a certain Value given a particular context. */
public class Expression: NSObject, NSCoding {
	public func explain(locale: Locale, topLevel: Bool = true) -> String {
		return "??"
	}
	
	/** The complexity of an expression is an indication of how 'far fetched' it is */
	var complexity: Int { get {
		return 1
	}}
	
	/** Returns whether the result of this expression is independent of the row fed to it. An expression that reports it
	is constant is guaranteed to return a value for apply() called without a row, set of columns and input value. */
	public var isConstant: Bool { get {
		return false
	} }
	
	/** Returns a version of this expression that has constant parts replaced with their actual values. */
	public func prepare() -> Expression {
		if isConstant {
			return Literal(self.apply(Row(), foreign: nil, inputValue: nil))
		}
		return self
	}
	
	override init() {
	}
	
	public required init?(coder aDecoder: NSCoder) {
	}
	
	public func encodeWithCoder(aCoder: NSCoder) {
	}
	
	/** Returns a localized representation of this expression, which should (when parsed by Formula in the same locale)
	result in an equivalent expression. */
	public func toFormula(locale: Locale, topLevel: Bool = false) -> String {
		return ""
	}
	
	/** Return true if, under all circumstances, this expression will return a result that is equal to the result returned
	by the other expression (Value equality). Note that this is different from what isEqual returns: isEqual is about 
	literal (definition) equality, whereas isEquivalentTo is about meaningful equality.
	
	Some examples of the differences:
	- Comparison(a,b).isEqual(Comparison(b,a)) will return false, but if the operator in both cases is commutative,
	  isEquivalentTo will return true.
	- Call(x).isEqual(Call(x)) will return true if x is the same function, but isEquivalentTo will only do so when x is
	  deterministic. */
	public func isEquivalentTo(expression: Expression) -> Bool {
		return false
	}
	
	/** Requests that callback be called on self, and visit() forwarded to all children. This can be used to implement
	dependency searches, etc. */
	public func visit(@noescape callback: (Expression) -> (Expression)) -> Expression {
		return callback(self)
	}
	
	@nonobjc public final func visit(@noescape callback: (Expression) -> ()) {
		self.visit { (e) -> Expression in
			callback(e)
			return e
		}
	}
	
	/** Calculate the result of this expression for the given row, columns and current input value. */
	public func apply(row: Row, foreign: Row?, inputValue: Value?) -> Value {
		fatalError("A Expression was called that isn't implemented")
	}
	
	/** Returns a list of suggestions for applications of this expression on the given value (fromValue) that result in the
	given 'to' value (or bring the value closer to the toValue). */
	class func suggest(fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		return []
	}
	
	/** The infer function implements an algorithm to find one or more formulas that are able to transform an
	input value to a specific output value. It does so by looping over 'suggestions' (provided by Function
	implementations) for the application of (usually unary) functions to the input value to obtain (or come closer to) the
	output value. */
	public class final func infer(fromValue: Expression?, toValue: Value, inout suggestions: [Expression], level: Int, row: Row, column: Int?, maxComplexity: Int = Int.max, previousValues: [Value] = [], job: Job? = nil) {
		let inputValue: Value
		if let c = column {
			inputValue = row.values[c]
		}
		else {
			inputValue = Value.InvalidValue
		}

		if let c = job?.cancelled where c {
			return
		}
		
		// Try out combinations of formulas and see if they fit
		for formulaType in expressions {
			if let c = job?.cancelled where c {
				return
			}
			
			let suggestedFormulas = formulaType.suggest(fromValue, toValue: toValue, row: row, inputValue: inputValue, level: level, job: job);
			var exploreFurther: [Expression] = []
			
			for formula in suggestedFormulas {
				if formula.complexity > maxComplexity {
					continue
				}
				
				let result = formula.apply(row, foreign: nil, inputValue: inputValue)
				if result == toValue {
					suggestions.append(formula)
				}
				else {
					if level > 0 {
						exploreFurther.append(formula)
					}
				}
			}

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
				
				var nextLevelSuggestions: [Expression] = []
				var newPreviousValues = previousValues
				newPreviousValues.append(result)
				infer(formula, toValue: toValue, suggestions: &nextLevelSuggestions, level: level-1, row: row, column: column, maxComplexity: maxComplexity-1, previousValues: newPreviousValues, job: job)
				
				for nextLevelSuggestion in nextLevelSuggestions {
					if nextLevelSuggestion.apply(row, foreign: nil, inputValue: inputValue) == toValue {
						suggestions.append(nextLevelSuggestion)
					}
				}
			}
		}
	}
}

/** The Literal always evaluates to the value set to it on initialization. The formula parser generates a
Literal for each literal (numbers, strings, constants) it encounters. */
public final class Literal: Expression {
	public let value: Value
	
	public init(_ value: Value) {
		self.value = value
		super.init()
	}

	public override var hashValue: Int {
		return value.hashValue
	}

	override var complexity: Int { get {
		return 10
	}}
	
	public override var isConstant: Bool { get {
		return true
	} }
	
	public required init?(coder aDecoder: NSCoder) {
		self.value = ((aDecoder.decodeObjectForKey("value") as? ValueCoder) ?? ValueCoder()).value
		super.init(coder: aDecoder)
	}
	
	public override func explain(locale: Locale, topLevel: Bool) -> String {
		return locale.localStringFor(value)
	}
	
	public override func toFormula(locale: Locale, topLevel: Bool) -> String {
		switch value {
		case .StringValue(let s):
			let escaped = s.stringByReplacingOccurrencesOfString(String(locale.stringQualifier), withString: locale.stringQualifierEscape)
			return "\(locale.stringQualifier)\(escaped)\(locale.stringQualifier)"
			
		case .DoubleValue(let d):
			return locale.numberFormatter.stringFromNumber(NSNumber(double: d)) ?? ""
			
		case .DateValue(let d):
			return "@" + (locale.numberFormatter.stringFromNumber(NSNumber(double: d)) ?? "")
			
		case .BoolValue(let b):
			return locale.constants[Value(b)]!
			
		case .IntValue(let i):
			return "\(i)"
		
		case .InvalidValue: return locale.constants[Value.EmptyValue]!
		case .EmptyValue: return locale.constants[Value.EmptyValue]!
		}
	}
	
	public override func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(ValueCoder(self.value), forKey: "value")
		super.encodeWithCoder(aCoder)
	}
	
	public override func apply(row: Row, foreign: Row?, inputValue: Value?) -> Value {
		return value
	}
	
	override class func suggest(fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		if fromValue == nil {
			return [Literal(toValue)]
		}
		return []
	}
	
	public override func isEquivalentTo(expression: Expression) -> Bool {
		return self.isEqual(expression)
	}

	public override func isEqual(object: AnyObject?) -> Bool {
		if let o = object as? Literal where o.value == self.value {
			return true
		}
		return super.isEqual(object)
	}
}

/** The Identity returns whatever value was set to the inputValue parameter during evaluation. This value
usually represents the (current) value in the current cell. */
public class Identity: Expression {
	public override init() {
		super.init()
	}

	public override var hashValue: Int {
		return 0x1D377170
	}

	public override func explain(locale: Locale, topLevel: Bool) -> String {
		return translationForString("current value")
	}

	public override func toFormula(locale: Locale, topLevel: Bool) -> String {
		return locale.currentCellIdentifier
	}
	
	public required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	public override func apply(row: Row, foreign: Row?, inputValue: Value?) -> Value {
		return inputValue ?? Value.InvalidValue
	}
	
	public override func isEquivalentTo(expression: Expression) -> Bool {
		return self.isEqual(expression)
	}

	public override func isEqual(object: AnyObject?) -> Bool {
		if object is Identity {
			return true
		}
		return super.isEqual(object)
	}
}

/** Comparison evaluates to the result of applying a particular binary operator to two operands, which are 
other expressions. */
public final class Comparison: Expression {
	public let first: Expression
	public let second: Expression
	public var type: Binary
	
	public override var isConstant: Bool { get {
		return first.isConstant && second.isConstant
	} }

	public override var hashValue: Int {
		return first.hashValue ^ (second.hashValue >> 3)
	}

	/** Utility function to return the arguments of this binary expression in a partiular order. Suppose we want to test
	 whether a binary expression is of type A=B where A is a sibling reference and B is a literal; because the equals 
	 operator is commutative, B=A is also allowed. This function can be called as followed to retrieve the sibling and 
	 the literal, allowing either variant:

	 let (sibling, literal) = binaryExpression.pair(Sibling.self, Literal.self) */
	public func commutativePair<U, V>(first: U.Type, _ second: V.Type) -> (U,V)? {
		if let a = self.first as? U, let b = self.second as? V {
			return (a, b)
		}
		else if let a = self.first as? V, let b = self.second as? U {
			return (b, a)
		}
		return nil
	}
	
	override public func prepare() -> Expression {
		let firstOptimized = first.prepare()
		let secondOptimized = second.prepare()
		
		/* If first and second operand are equivalent, the result of '==' or '<>' is always known (even when the operands 
		are not constant, e.g. sibling or foreign references) */
		if firstOptimized.isEquivalentTo(secondOptimized) {
			switch self.type {
				case .Equal, .LesserEqual, .GreaterEqual:
					return Literal(Value.BoolValue(true))

				case .NotEqual, .Greater, .Lesser:
					return Literal(Value.BoolValue(false))
				
				default:
					break;
			}
		}
		
		// If the first and second operand are constant, the result of the binary expression can likely be precalculated
		let optimized = Comparison(first: firstOptimized, second: secondOptimized, type: self.type)
		if optimized.isConstant {
			return Literal(optimized.apply(Row(), foreign: nil, inputValue: nil))
		}
		return optimized
	}
	
	public override func visit(@noescape callback: (Expression) -> (Expression)) -> Expression {
		let first = self.first.visit(callback)
		let second = self.second.visit(callback)
		let newSelf = Comparison(first: first, second: second, type: self.type)
		return callback(newSelf)
	}
	
	public override func explain(locale: Locale, topLevel: Bool) -> String {
		return (topLevel ? "": "(") + second.explain(locale, topLevel: false) + " " + type.explain(locale) + " " + first.explain(locale, topLevel: false) + (topLevel ? "": ")")
	}
	
	public override func toFormula(locale: Locale, topLevel: Bool) -> String {
		let start = topLevel ? "" : "("
		let end = topLevel ? "" : ")"
		return "\(start)\(second.toFormula(locale))\(type.toFormula(locale))\(first.toFormula(locale))\(end)"
	}
	
	override var complexity: Int { get {
		return first.complexity + second.complexity + 1
	}}
	
	public init(first: Expression, second: Expression, type: Binary) {
		self.first = first
		self.second = second
		self.type = type
		super.init()
	}
	
	public required init?(coder aDecoder: NSCoder) {
		self.first = (aDecoder.decodeObjectForKey("first") as? Expression) ?? Identity()
		self.second = (aDecoder.decodeObjectForKey("second") as? Expression) ?? Identity()
		let typeString = (aDecoder.decodeObjectForKey("type") as? String) ?? Binary.Addition.rawValue
		self.type = Binary(rawValue: typeString) ?? Binary.Addition
		super.init(coder: aDecoder)
	}
	
	public override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(first, forKey: "first")
		aCoder.encodeObject(second, forKey: "second")
		aCoder.encodeObject(type.rawValue, forKey: "type")
	}
	
	public override func apply(row: Row, foreign: Row?, inputValue: Value?) -> Value {
		let left = second.apply(row, foreign: foreign, inputValue: nil)
		let right = first.apply(row, foreign: foreign, inputValue: nil)
		return self.type.apply(left, right)
	}
	
	override class func suggest(fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		var suggestions: [Expression] = []
		
		if let from = fromValue {
			if let f = fromValue?.apply(row, foreign: nil, inputValue: inputValue) {
				if level > 1 {
					if let targetDouble = toValue.doubleValue {
						if let fromDouble = f.doubleValue {
							// Suggest addition or subtraction
							let difference = targetDouble - fromDouble
							if difference != 0 {
								var addSuggestions: [Expression] = []
								Expression.infer(nil, toValue: Value(abs(difference)), suggestions: &addSuggestions, level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
								
								if difference > 0 {
									addSuggestions.forEach({suggestions.append(Comparison(first: $0, second: from, type: Binary.Addition))})
								}
								else {
									addSuggestions.forEach({suggestions.append(Comparison(first: $0, second: from, type: Binary.Subtraction))})
								}
							}
							
							// Suggest division or multiplication
							if fromDouble != 0 {
								let dividend = targetDouble / fromDouble
								
								var mulSuggestions: [Expression] = []
								Expression.infer(nil, toValue: Value(dividend < 1 ? (1/dividend) : dividend), suggestions: &mulSuggestions, level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
								
								if dividend >= 1 {
									mulSuggestions.forEach({suggestions.append(Comparison(first: $0, second: from, type: Binary.Multiplication))})
								}
								else {
									mulSuggestions.forEach({suggestions.append(Comparison(first: $0, second: from, type: Binary.Division))})
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
								
								var postfixSuggestions: [Expression] = []
								Expression.infer(nil, toValue: Value.StringValue(postfix), suggestions: &postfixSuggestions, level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
								
								postfixSuggestions.forEach({suggestions.append(Comparison(first: $0, second: from, type: Binary.Concatenation))})
							}
							else {
								// See if the target string shares a postfix with the source string
								let prefixLength = targetString.characters.count - fromString.characters.count
								let targetPostfix = targetString.substringWithRange(targetString.startIndex.advancedBy(prefixLength)..<targetString.endIndex)
								if fromString == targetPostfix {
									let prefix = targetString.substringWithRange(targetString.startIndex..<targetString.startIndex.advancedBy(prefixLength))
									print("'\(fromString)' => '\(targetString)' share postfix: '\(targetPostfix)' need prefix: '\(prefix)'")
									
									var prefixSuggestions: [Expression] = []
									Expression.infer(nil, toValue: Value.StringValue(prefix), suggestions: &prefixSuggestions, level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
									
									prefixSuggestions.forEach({suggestions.append(Comparison(first: from, second: $0, type: Binary.Concatenation))})
								}
							}
						}
					}
				}
			}
		}
		
		return suggestions
	}
	
	public override func isEquivalentTo(expression: Expression) -> Bool {
		if let otherBinary = expression as? Comparison {
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

	public override func isEqual(object: AnyObject?) -> Bool {
		if let o = object as? Comparison where o.first == self.first && o.second == self.second && o.type == self.type {
			return true
		}
		return super.isEqual(object)
	}
}

/** Call evaluates to the result of applying a function to a given set of arguments. The set of arguments
consists of expressions that are evaluated before sending them to the function. */
public final class Call: Expression {
	public let arguments: [Expression]
	public let type: Function

	public override var hashValue: Int {
		return arguments.reduce(type.hashValue) { t, e in return t ^ e.hashValue }
	}
	
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
	
	public override func visit(@noescape callback: (Expression) -> (Expression)) -> Expression {
		let newArguments = arguments.map({$0.visit(callback)})
		return callback(Call(arguments: newArguments, type: self.type))
	}
	
	public override func prepare() -> Expression {
		return self.type.prepare(arguments)
	}
	
	public override func explain(locale: Locale, topLevel: Bool) -> String {
		if arguments.count > 0 {
			let argumentsList = arguments.map({$0.explain(locale, topLevel: false)}).joinWithSeparator(", ")
			return "\(type.explain(locale))(\(argumentsList))"
		}
		return type.explain(locale)
	}
	
	public override func toFormula(locale: Locale, topLevel: Bool) -> String {
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
	
	public init(arguments: [Expression], type: Function) {
		self.arguments = arguments
		self.type = type
		super.init()
	}
	
	public required init?(coder aDecoder: NSCoder) {
		self.arguments = (aDecoder.decodeObjectForKey("args") as? [Expression]) ?? []
		let typeString = (aDecoder.decodeObjectForKey("type") as? String) ?? Function.Identity.rawValue
		self.type = Function(rawValue: typeString) ?? Function.Identity
		super.init(coder: aDecoder)
	}
	
	public override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(arguments, forKey: "args")
		aCoder.encodeObject(type.rawValue, forKey: "type")
	}
	
	public override func apply(row: Row, foreign: Row?, inputValue: Value?) -> Value {
		let vals = arguments.map({$0.apply(row, foreign: foreign, inputValue: inputValue)})
		return self.type.apply(vals)
	}
	
	public override func isEquivalentTo(expression: Expression) -> Bool {
		if let otherFunction = expression as? Call {
			if otherFunction.type == self.type && self.arguments == otherFunction.arguments && self.type.isDeterministic {
				return true
			}
		}
		return false
	}

	public override func isEqual(object: AnyObject?) -> Bool {
		if let o = object as? Call where o.type == self.type && o.arguments == self.arguments {
			return true
		}
		return super.isEqual(object)
	}
	
	override class func suggest(fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		var suggestions: [Expression] = []
		
		if let from = fromValue {
			if let f = fromValue?.apply(row, foreign: nil, inputValue: inputValue) {
				// Check whether one of the unary functions can transform the input value to the output value
				for op in Function.allFunctions {
					if(op.arity.valid(1) && op.isDeterministic) {
						if op.apply([f]) == toValue {
							suggestions.append(Call(arguments: [from], type: op))
						}
					}
				}
				
				// For binary and n-ary functions, specific test cases follow
				var incompleteSuggestions: [Expression] = []
				if let targetString = toValue.stringValue {
					let length = Value(targetString.characters.count)

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
								let pack = Pack(splitted)
								for i in 0..<pack.count {
									let item = pack[i]
									let splitExpression = Call(arguments: [from, Literal(Value.StringValue(separator))], type: Function.Split)
									let nthExpression = Call(arguments: [splitExpression, Literal(Value.IntValue(i+1))], type: Function.Nth)
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
									suggestions.append(Call(arguments: [from, Literal(length)], type: Function.Right))

									let startIndex = sourceString.startIndex.distanceTo(range.startIndex)
									let start = Literal(Value(startIndex))
									let length = Literal(Value(range.startIndex.distanceTo(range.endIndex)))
									if startIndex == 0 {
										suggestions.append(Call(arguments: [from, length], type: Function.Left))
									}
									else {
										suggestions.append(Call(arguments: [from, start, length], type: Function.Mid))
									}
								}
								else {
									// Suggest a text replace
									suggestions.append(Call(arguments: [Identity(), Literal(f), Literal(toValue)], type: Function.Substitute))
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

protocol ColumnReferencingExpression {
	var column: Column { get }
}

/** The Sibling evaluates to the value of a cell in a particular column on the same row as the current value. */
public final class Sibling: Expression, ColumnReferencingExpression {
	public var column: Column
	
	public init(_ columnName: Column) {
		self.column = columnName
		super.init()
	}

	public override var hashValue: Int {
		return column.hashValue
	}
	
	public override func explain(locale: Locale, topLevel: Bool) -> String {
		return String(format: translationForString("value in column %@"), column.name)
	}
	
	public required init?(coder aDecoder: NSCoder) {
		column = Column((aDecoder.decodeObjectForKey("columnName") as? String) ?? "")
		super.init(coder: aDecoder)
	}
	
	public override func toFormula(locale: Locale, topLevel: Bool) -> String {
		return "[@\(column.name)]"
	}
	
	public override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(column.name, forKey: "columnName")
	}
	
	public override func apply(row: Row, foreign: Row?, inputValue: Value?) -> Value {
		return row[column] ?? Value.InvalidValue
	}
	
	override class func suggest(fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		var s: [Expression] = []
		if fromValue == nil {
			for columnName in row.columns {
				s.append(Sibling(columnName))
			}
		}
		return s
	}
	
	public override func isEquivalentTo(expression: Expression) -> Bool {
		if let otherSibling = expression as? Sibling {
			return otherSibling.column == self.column
		}
		return false
	}

	public override func isEqual(object: AnyObject?) -> Bool {
		if let o = object as? Sibling where o.column == self.column {
			return true
		}
		return super.isEqual(object)
	}
}

/** The Foreign evaluates to the value of a cell in a particular column in the foreign row. This is used to 
evaluate whether two rows should be matched up in a join. If no foreign row is given, this expression gives an error. */
public final class Foreign: Expression, ColumnReferencingExpression {
	public var column: Column
	
	public init(_ column: Column) {
		self.column = column
		super.init()
	}

	public override var hashValue: Int {
		return ~column.hashValue
	}
	
	public override func explain(locale: Locale, topLevel: Bool) -> String {
		return String(format: translationForString("value in foreign column %@"), column.name)
	}
	
	public required init?(coder aDecoder: NSCoder) {
		column = Column((aDecoder.decodeObjectForKey("columnName") as? String) ?? "")
		super.init(coder: aDecoder)
	}
	
	public override func toFormula(locale: Locale, topLevel: Bool) -> String {
		return "[#\(column.name)]"
	}
	
	public override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(column.name, forKey: "columnName")
	}
	
	public override func apply(row: Row, foreign: Row?, inputValue: Value?) -> Value {
		return foreign?[column] ?? Value.InvalidValue
	}
	
	override class func suggest(fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		// TODO: implement when we are going to implement foreign suggestions
		return []
	}
	
	public override func isEquivalentTo(expression: Expression) -> Bool {
		if let otherForeign = expression as? Foreign {
			return otherForeign.column == self.column
		}
		return false
	}

	public override func isEqual(object: AnyObject?) -> Bool {
		if let o = object as? Foreign where o.column == self.column {
			return true
		}
		return super.isEqual(object)
	}
}

/** A filter set represents a set of values that is selected from a set of values (usually a data set column). */
public class FilterSet: NSObject, NSCoding {
	public var selectedValues: Set<Value> = []
	
	public override init() {
	}
	
	public required init?(coder aDecoder: NSCoder) {
		if let v = aDecoder.decodeObjectForKey("selectedValues") as? [ValueCoder] {
			selectedValues = Set(v.map({return $0.value}))
		}
	}
	
	public func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(Array<ValueCoder>(selectedValues.map({return ValueCoder($0)})), forKey: "selectedValues")
	}
	
	/** Returns an expression representing this filter. The source column is represented as Identity. */
	public var expression: Expression {
		if selectedValues.count == 1 {
			// The value must be equal to the selected value x - generate value == x
			return Comparison(first: Literal(selectedValues.first!), second: Identity(), type: .Equal)
		}
		else if selectedValues.count > 1 {
			// The value may match any of the selected values x, y, z - generate IN(value, x, y, z)
			var args: [Expression] = [Identity()]
			for value in selectedValues {
				args.append(Literal(value))
			}
			
			return Call(arguments: args, type: Function.In)
		}
		else {
			// No value is selected, therefore no value should match
			return Literal(Value(false))
		}
	}
}

/** Functions defined on Expression that rely on knowledge of its subclasses should be in this extension. */
extension Expression {
	/** Returns a version of this expression that can be used to find matching rows in a foreign table. It replaces all
	occurences of Foreign with Sibling, and replaces instances Sibling with the
	corresponding values from the row given. */
	final func expressionForForeignFiltering(row: Row) -> Expression {
		return visit { (oldExpression) in
			if let old = oldExpression as? Sibling {
				return Literal(old.apply(row, foreign: nil, inputValue: nil))
			}
			else if let old = oldExpression as? Foreign {
				return Sibling(old.column)
			}
			else {
				return oldExpression
			}
		}
	}
	
	/** Returns a version of this expression where all foreign references have been replaced by sibling references. The
	expression is not allowed to contain sibling references (in wich case this function will return nil) */
	final func expressionForForeignFiltering() -> Expression? {
		var error = false
		
		let result = visit { (oldExpression) -> (Expression) in
			if  oldExpression is Sibling {
				error = true
				return oldExpression
			}
			else if let old = oldExpression as? Foreign {
				return Sibling(old.column)
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
	
	/** Returns this expression with all occurences of Identity replaced with the given new expression. */
	public final func expressionReplacingIdentityReferencesWith(newExpression: Expression) -> Expression {
		return visit { (oldExpression) in
			if oldExpression is Identity {
				return newExpression
			}
			return oldExpression
		}
	}

	public var siblingDependencies: Set<Column> {
		var deps: Set<Column> = []

		visit { expression -> () in
			if let ex = expression as? Sibling {
				deps.insert(ex.column)
			}
		}
		return deps
	}
	
	/** Returns whether this expression depends on sibling columns (e.g. contains a Sibling somewhere in 
	its tree). */
	public var dependsOnSiblings: Bool {
		var depends = false
		visit { (expression) -> () in
			if expression is Sibling {
				depends = true
			}
		}
		return depends
	}

	/** Returns whether this expression depends on foreign columns (e.g. contains a Foreign somewhere in
	its tree). */
	public var dependsOnForeigns: Bool {
		var depends = false
		visit { expression -> () in
			if expression is Foreign {
				depends = true
			}
		}
		return depends
	}
}