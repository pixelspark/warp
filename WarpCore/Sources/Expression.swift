/* Copyright (c) 2014-2016 Pixelspark, Tommy van der Vorst

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
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
	public func explain(_ locale: Language, topLevel: Bool = true) -> String {
		return "??"
	}
	
	/** The complexity of an expression is an indication of how 'far fetched' it is */
	public var complexity: Int {
		return 1
	}
	
	/** Returns whether the result of this expression is independent of the row fed to it. An expression that reports it
	is constant is guaranteed to return a value for apply() called without a row, set of columns and input value. */
	public var isConstant: Bool {
		return false
	}
	
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
	
	public func encode(with aCoder: NSCoder) {
	}
	
	/** Returns a localized representation of this expression, which should (when parsed by Formula in the same locale)
	result in an equivalent expression. */
	public func toFormula(_ locale: Language, topLevel: Bool = false) -> String {
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
	public func isEquivalentTo(_ expression: Expression) -> Bool {
		return false
	}
	
	/** Requests that callback be called on self, and visit() forwarded to all children. This can be used to implement
	dependency searches, etc. */
	@discardableResult public func visit( _ callback: (Expression) -> (Expression)) -> Expression {
		return callback(self)
	}
	
	@nonobjc public final func visit( _ callback: (Expression) -> ()) {
		self.visit { (e) -> Expression in
			callback(e)
			return e
		}
	}
	
	/** Calculate the result of this expression for the given row, columns and current input value. */
	public func apply(_ row: Row, foreign: Row?, inputValue: Value?) -> Value {
		fatalError("A Expression was called that isn't implemented")
	}
	
	/** Returns a list of suggestions for applications of this expression on the given value (fromValue) that result in the
	given 'to' value (or bring the value closer to the toValue). */
	class func suggest(_ fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		return []
	}

	private var containsLiterals: Bool {
		var contains = false
		self.visit { e -> () in
			if e is Literal {
				contains = true
			}
		}
		return contains
	}
	
	/** The infer function implements an algorithm to find one or more formulas that are able to transform an
	input value to a specific output value. It does so by looping over 'suggestions' (provided by Function
	implementations) for the application of (usually unary) functions to the input value to obtain (or come closer to) the
	output value. */
	public class final func infer(_ fromValue: Expression?, toValue: Value, level: Int, row: Row, column: Int?, maxComplexity inMaxComplexity: Int = Int.max, previousValues: [Value] = [], job: Job? = nil) -> [Expression] {
		if level <= 0 {
			return []
		}
		var outSuggestions: [Expression] = []
		var inMaxComplexity = inMaxComplexity

		let inputValue: Value
		if let c = column {
			inputValue = row.values[c]
		}
		else {
			inputValue = Value.invalid
		}

		if let c = job?.isCancelled, c {
			return outSuggestions
		}

		var exploreFurther: [(Expression, maxComplexity: Int)] = []

		// Try out combinations of formulas and see if they fit
		for formulaType in expressions {
			if let c = job?.isCancelled, c {
				return outSuggestions
			}
			
			let suggestedFormulas = formulaType.suggest(fromValue, toValue: toValue, row: row, inputValue: inputValue, level: level, job: job);
			
			for formula in suggestedFormulas {
				if formula.complexity > inMaxComplexity {
					continue
				}
				
				let result = formula.apply(row, foreign: nil, inputValue: inputValue)
				if result == toValue {
					// This one is good, but look for a less complex one still
					inMaxComplexity = min(inMaxComplexity, formula.complexity)
					outSuggestions.append(formula)
					exploreFurther.append((formula, maxComplexity: formula.complexity))
				}
				else {
					exploreFurther.append((formula, maxComplexity: inMaxComplexity))
				}
			}
		}

		// Let's see if we can find something else
		for (formula, maxComplexity) in exploreFurther {
			if formula.complexity > inMaxComplexity {
				continue
			}

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

			var newPreviousValues = previousValues
			newPreviousValues.append(result)
			let nextLevelSuggestions = infer(formula, toValue: toValue, level: level-1, row: row, column: column, maxComplexity: min(inMaxComplexity, maxComplexity-1), previousValues: newPreviousValues, job: job)
			
			for nextLevelSuggestion in nextLevelSuggestions {
				if nextLevelSuggestion.apply(row, foreign: nil, inputValue: inputValue) == toValue {
					outSuggestions.append(nextLevelSuggestion)
				}
			}
		}

		return outSuggestions
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

	override public var complexity: Int {
		return 10
	}
	
	public override var isConstant: Bool {
		return true
	}
	
	public required init?(coder aDecoder: NSCoder) {
		self.value = ((aDecoder.decodeObject(forKey: "value") as? ValueCoder) ?? ValueCoder()).value
		super.init(coder: aDecoder)
	}
	
	public override func explain(_ locale: Language, topLevel: Bool) -> String {
		return locale.localStringFor(value)
	}
	
	public override func toFormula(_ locale: Language, topLevel: Bool) -> String {
		switch value {
		case .string(let s):
			let escaped = s.replacingOccurrences(of: String(locale.stringQualifier), with: locale.stringQualifierEscape)
			return "\(locale.stringQualifier)\(escaped)\(locale.stringQualifier)"

		case .blob(let d):
			return "\(locale.blobQualifier)\(d.base64EncodedString())\(locale.blobQualifier)"
			
		case .double(let d):
			return locale.numberFormatter.string(from: NSNumber(value: d)) ?? ""
			
		case .date(let d):
			return "@" + (locale.numberFormatter.string(from: NSNumber(value: d)) ?? "")
			
		case .bool(let b):
			return locale.constants[Value(b)]!
			
		case .int(let i):
			return "\(i)"
		
		case .invalid: return locale.constants[Value.empty]!
		case .empty: return locale.constants[Value.empty]!
		}
	}
	
	public override func encode(with aCoder: NSCoder) {
		aCoder.encode(ValueCoder(self.value), forKey: "value")
		super.encode(with: aCoder)
	}
	
	public override func apply(_ row: Row, foreign: Row?, inputValue: Value?) -> Value {
		return value
	}
	
	override class func suggest(_ fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		if fromValue == nil {
			return [Literal(toValue)]
		}
		return []
	}
	
	public override func isEquivalentTo(_ expression: Expression) -> Bool {
		return self.isEqual(expression)
	}

	public override func isEqual(_ object: Any?) -> Bool {
		if let o = object as? Literal, o.value == self.value {
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

	public override func explain(_ locale: Language, topLevel: Bool) -> String {
		return translationForString("current value")
	}

	public override func toFormula(_ locale: Language, topLevel: Bool) -> String {
		return locale.currentCellIdentifier
	}
	
	public required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	public override func apply(_ row: Row, foreign: Row?, inputValue: Value?) -> Value {
		return inputValue ?? Value.invalid
	}
	
	public override func isEquivalentTo(_ expression: Expression) -> Bool {
		return self.isEqual(expression)
	}

	override class func suggest(_ fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		return [Identity()]
	}

	public override func isEqual(_ object: Any?) -> Bool {
		if object is Identity {
			return true
		}
		return super.isEqual(object)
	}

	public override var complexity: Int {
		return 0
	}
}

/** Comparison evaluates to the result of applying a particular binary operator to two operands, which are 
other expressions. */
public final class Comparison: Expression {
	public let first: Expression
	public let second: Expression
	public var type: Binary
	
	public override var isConstant: Bool {
		return first.isConstant && second.isConstant
	}

	public override var hashValue: Int {
		return first.hashValue ^ (second.hashValue >> 3)
	}

	/** Utility function to return the arguments of this binary expression in a partiular order. Suppose we want to test
	 whether a binary expression is of type A=B where A is a sibling reference and B is a literal; because the equals 
	 operator is commutative, B=A is also allowed. This function can be called as followed to retrieve the sibling and 
	 the literal, allowing either variant:

	 let (sibling, literal) = binaryExpression.pair(Sibling.self, Literal.self) */
	public func commutativePair<U, V>(_ first: U.Type, _ second: V.Type) -> (U,V)? {
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
				case .equal, .lesserEqual, .greaterEqual:
					return Literal(Value.bool(true))

				case .notEqual, .greater, .lesser:
					return Literal(Value.bool(false))
				
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
	
	public override func visit( _ callback: (Expression) -> (Expression)) -> Expression {
		let first = self.first.visit(callback)
		let second = self.second.visit(callback)
		let newSelf = Comparison(first: first, second: second, type: self.type)
		return callback(newSelf)
	}
	
	public override func explain(_ locale: Language, topLevel: Bool) -> String {
		return (topLevel ? "": "(") + second.explain(locale, topLevel: false) + " " + type.explain(locale) + " " + first.explain(locale, topLevel: false) + (topLevel ? "": ")")
	}
	
	public override func toFormula(_ locale: Language, topLevel: Bool) -> String {
		let start = topLevel ? "" : "("
		let end = topLevel ? "" : ")"
		return "\(start)\(second.toFormula(locale))\(type.toFormula(locale))\(first.toFormula(locale))\(end)"
	}
	
	override public var complexity: Int {
		return first.complexity + second.complexity + 5
	}
	
	public init(first: Expression, second: Expression, type: Binary) {
		self.first = first
		self.second = second
		self.type = type
		super.init()
	}
	
	public required init?(coder aDecoder: NSCoder) {
		self.first = (aDecoder.decodeObject(forKey: "first") as? Expression) ?? Identity()
		self.second = (aDecoder.decodeObject(forKey: "second") as? Expression) ?? Identity()
		let typeString = (aDecoder.decodeObject(forKey: "type") as? String) ?? Binary.addition.rawValue
		self.type = Binary(rawValue: typeString) ?? Binary.addition
		super.init(coder: aDecoder)
	}
	
	public override func encode(with aCoder: NSCoder) {
		super.encode(with: aCoder)
		aCoder.encode(first, forKey: "first")
		aCoder.encode(second, forKey: "second")
		aCoder.encode(type.rawValue, forKey: "type")
	}
	
	public override func apply(_ row: Row, foreign: Row?, inputValue: Value?) -> Value {
		let left = second.apply(row, foreign: foreign, inputValue: nil)
		let right = first.apply(row, foreign: foreign, inputValue: nil)
		return self.type.apply(left, right)
	}
	
	override class func suggest(_ fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		var suggestions: [Expression] = []
		
		if let from = fromValue {
			if let f = fromValue?.apply(row, foreign: nil, inputValue: inputValue) {
				if level > 1 {
					if let targetDouble = toValue.doubleValue {
						if let fromDouble = f.doubleValue {
							// Suggest addition or subtraction
							let difference = targetDouble - fromDouble
							if difference != 0 {
								let addSuggestions = Expression.infer(nil, toValue: Value(abs(difference)), level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
								
								if difference > 0 {
									addSuggestions.forEach {
										suggestions.append(Comparison(first: $0, second: from, type: Binary.addition))
									}
								}
								else {
									addSuggestions.forEach {
										suggestions.append(Comparison(first: $0, second: from, type: Binary.subtraction))
									}
								}
							}
							
							// Suggest division or multiplication
							if fromDouble != 0 {
								let dividend = targetDouble / fromDouble

								let mulSuggestions = Expression.infer(nil, toValue: Value(dividend < 1 ? (1/dividend) : dividend), level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
								
								if dividend >= 1 {
									mulSuggestions.forEach {
										suggestions.append(Comparison(first: $0, second: from, type: Binary.multiplication))
									}
								}
								else {
									mulSuggestions.forEach {
										suggestions.append(Comparison(first: $0, second: from, type: Binary.division))
									}
								}
							}
						}
					}
					else if let targetString = toValue.stringValue, let fromString = f.stringValue {
						if !targetString.isEmpty && !fromString.isEmpty && fromString.characters.count < targetString.characters.count {
							// See if the target string shares a prefix with the source string
							let targetPrefix = targetString.substring(with: targetString.startIndex..<targetString.characters.index(targetString.startIndex, offsetBy: fromString.characters.count))
							if fromString == targetPrefix {
								let postfix = targetString.substring(with: targetString.characters.index(targetString.startIndex, offsetBy: fromString.characters.count)..<targetString.endIndex)
								print("'\(fromString)' => '\(targetString)' share prefix: '\(targetPrefix)' need postfix: '\(postfix)'")

								let postfixSuggestions = Expression.infer(nil, toValue: Value.string(postfix), level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
								
								postfixSuggestions.forEach {
									suggestions.append(Comparison(first: $0, second: from, type: Binary.concatenation))
								}
							}
							else {
								// See if the target string shares a postfix with the source string
								let prefixLength = targetString.characters.count - fromString.characters.count
								let targetPostfix = targetString.substring(with: targetString.characters.index(targetString.startIndex, offsetBy: prefixLength)..<targetString.endIndex)
								if fromString == targetPostfix {
									let prefix = targetString.substring(with: targetString.startIndex..<targetString.characters.index(targetString.startIndex, offsetBy: prefixLength))
									print("'\(fromString)' => '\(targetString)' share postfix: '\(targetPostfix)' need prefix: '\(prefix)'")
									
									let prefixSuggestions = Expression.infer(nil, toValue: Value.string(prefix), level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
									
									prefixSuggestions.forEach {
										suggestions.append(Comparison(first: from, second: $0, type: Binary.concatenation))
									}
								}
							}
						}
					}
				}
			}
		}
		
		return suggestions
	}
	
	public override func isEquivalentTo(_ expression: Expression) -> Bool {
		if let otherBinary = expression as? Comparison {
			if otherBinary.type == self.type && otherBinary.first.isEquivalentTo(self.first) && otherBinary.second.isEquivalentTo(self.second) {
				return true
			}
			// A <> B is equivalent to B = A, so in these cases the binary expression is equivalent
			else if let mirror = self.type.mirror, otherBinary.type == mirror && otherBinary.first.isEquivalentTo(self.second) && otherBinary.second.isEquivalentTo(self.first) {
				return true
			}
		}
		
		return false
	}

	public override func isEqual(_ object: Any?) -> Bool {
		if let o = object as? Comparison, o.first == self.first && o.second == self.second && o.type == self.type {
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
	
	public override var isConstant: Bool {
		if !type.isDeterministic {
			return false
		}
		
		for a in arguments {
			if !a.isConstant {
				return false
			}
		}
		
		return true
	}
	
	public override func visit( _ callback: (Expression) -> (Expression)) -> Expression {
		let newArguments = arguments.map({$0.visit(callback)})
		return callback(Call(arguments: newArguments, type: self.type))
	}
	
	public override func prepare() -> Expression {
		return self.type.prepare(arguments)
	}
	
	public override func explain(_ locale: Language, topLevel: Bool) -> String {
		return type.explain(locale, arguments: self.arguments)
	}
	
	public override func toFormula(_ locale: Language, topLevel: Bool) -> String {
		return type.toFormula(locale, arguments: self.arguments)
	}
	
	override public var complexity: Int {
		var complexity = 1
		for a in arguments {
			complexity += a.complexity
		}
		
		return complexity + 10
	}
	
	public init(arguments: [Expression], type: Function) {
		self.arguments = arguments
		self.type = type
		super.init()
	}
	
	public required init?(coder aDecoder: NSCoder) {
		self.arguments = (aDecoder.decodeObject(forKey: "args") as? [Expression]) ?? []
		let typeString = (aDecoder.decodeObject(forKey: "type") as? String) ?? Function.identity.rawValue
		self.type = Function(rawValue: typeString) ?? Function.identity
		super.init(coder: aDecoder)
	}
	
	public override func encode(with aCoder: NSCoder) {
		super.encode(with: aCoder)
		aCoder.encode(arguments, forKey: "args")
		aCoder.encode(type.rawValue, forKey: "type")
	}
	
	public override func apply(_ row: Row, foreign: Row?, inputValue: Value?) -> Value {
		let vals = arguments.map({$0.apply(row, foreign: foreign, inputValue: inputValue)})
		return self.type.apply(vals)
	}
	
	public override func isEquivalentTo(_ expression: Expression) -> Bool {
		if let otherFunction = expression as? Call {
			if otherFunction.type == self.type && self.arguments == otherFunction.arguments && self.type.isDeterministic {
				return true
			}

			if self.type.isIdentityWithSingleArgument && self.arguments.count == 1 && expression is Identity {
				return true
			}
		}
		return false
	}

	public override func isEqual(_ object: Any?) -> Bool {
		if let o = object as? Call, o.type == self.type && o.arguments == self.arguments {
			return true
		}
		return super.isEqual(object)
	}
	
	override class func suggest(_ fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		var suggestions: [Expression] = []
		
		if let from = fromValue {
			if let f = fromValue?.apply(row, foreign: nil, inputValue: inputValue) {
				// Check whether one of the unary functions can transform the input value to the output value
				for op in Function.allFunctions {
					if(op.arity.valid(1) && op.isDeterministic && !op.isIdentityWithSingleArgument) {
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
							if let c = job?.isCancelled, c {
								break
							}
							
							let splitted = sourceString.components(separatedBy: separator)
							if splitted.count > 1 {
								let pack = Pack(splitted)
								for i in 0..<pack.count {
									let item = pack[i]
									let splitExpression = Call(arguments: [from, Literal(Value.string(separator))], type: Function.split)
									let nthExpression = Call(arguments: [splitExpression, Literal(Value.int(i+1))], type: Function.nth)
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
								if let range = sourceString.range(of: targetString) {
									suggestions.append(Call(arguments: [from, Literal(length)], type: Function.right))

									let startIndex = sourceString.characters.distance(from: sourceString.startIndex, to: range.lowerBound)
									let start = Literal(Value(startIndex))
									let length = Literal(Value(sourceString.distance(from: range.lowerBound, to: range.upperBound)))
									if startIndex == 0 {
										suggestions.append(Call(arguments: [from, length], type: Function.left))
									}
									else {
										suggestions.append(Call(arguments: [from, start, length], type: Function.mid))
									}
								}
								else {
									// Suggest a text replace
									suggestions.append(Call(arguments: [Identity(), Literal(f), Literal(toValue)], type: Function.substitute))
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

	public override var complexity: Int {
		return 2
	}

	public override var hashValue: Int {
		return column.hashValue
	}
	
	public override func explain(_ locale: Language, topLevel: Bool) -> String {
		return String(format: translationForString("value in column %@"), column.name)
	}
	
	public required init?(coder aDecoder: NSCoder) {
		column = Column((aDecoder.decodeObject(forKey: "columnName") as? String) ?? "")
		super.init(coder: aDecoder)
	}
	
	public override func toFormula(_ locale: Language, topLevel: Bool) -> String {
		if Formula.canBeWittenAsShorthandSibling(name: column.name) {
			return column.name
		}
		return "[\(column.name)]"
	}
	
	public override func encode(with aCoder: NSCoder) {
		super.encode(with: aCoder)
		aCoder.encode(column.name, forKey: "columnName")
	}
	
	public override func apply(_ row: Row, foreign: Row?, inputValue: Value?) -> Value {
		return row[column] ?? Value.invalid
	}
	
	override class func suggest(_ fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		var s: [Expression] = []
		for columnName in row.columns {
			if fromValue == nil || row[columnName] == toValue {
				s.append(Sibling(columnName))
			}
		}

		// If none of the siblings match, just return all of them, see if that helps
		if s.count == 0 {
			return row.columns.map { Sibling($0) }
		}

		return s
	}
	
	public override func isEquivalentTo(_ expression: Expression) -> Bool {
		if let otherSibling = expression as? Sibling {
			return otherSibling.column == self.column
		}
		return false
	}

	public override func isEqual(_ object: Any?) -> Bool {
		if let o = object as? Sibling, o.column == self.column {
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
	
	public override func explain(_ locale: Language, topLevel: Bool) -> String {
		return String(format: translationForString("value in foreign column %@"), column.name)
	}
	
	public required init?(coder aDecoder: NSCoder) {
		column = Column((aDecoder.decodeObject(forKey: "columnName") as? String) ?? "")
		super.init(coder: aDecoder)
	}
	
	public override func toFormula(_ locale: Language, topLevel: Bool) -> String {
		return "[#\(column.name)]"
	}
	
	public override func encode(with aCoder: NSCoder) {
		super.encode(with: aCoder)
		aCoder.encode(column.name, forKey: "columnName")
	}
	
	public override func apply(_ row: Row, foreign: Row?, inputValue: Value?) -> Value {
		return foreign?[column] ?? Value.invalid
	}
	
	override class func suggest(_ fromValue: Expression?, toValue: Value, row: Row, inputValue: Value?, level: Int, job: Job?) -> [Expression] {
		// TODO: implement when we are going to implement foreign suggestions
		return []
	}
	
	public override func isEquivalentTo(_ expression: Expression) -> Bool {
		if let otherForeign = expression as? Foreign {
			return otherForeign.column == self.column
		}
		return false
	}

	public override func isEqual(_ object: Any?) -> Bool {
		if let o = object as? Foreign, o.column == self.column {
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

	public init(values: Set<Value>) {
		self.selectedValues = values
	}
	
	public required init?(coder aDecoder: NSCoder) {
		if let v = aDecoder.decodeObject(forKey: "selectedValues") as? [ValueCoder] {
			selectedValues = Set(v.map({return $0.value}))
		}
	}
	
	public func encode(with aCoder: NSCoder) {
		aCoder.encode(Array<ValueCoder>(selectedValues.map({return ValueCoder($0)})), forKey: "selectedValues")
	}
	
	/** Returns an expression representing this filter. The source column is represented as Identity. */
	public var expression: Expression {
		if selectedValues.count == 1 {
			// The value must be equal to the selected value x - generate value == x
			return Comparison(first: Literal(selectedValues.first!), second: Identity(), type: .equal)
		}
		else if selectedValues.count > 1 {
			// The value may match any of the selected values x, y, z - generate IN(value, x, y, z)
			var args: [Expression] = [Identity()]
			for value in selectedValues {
				args.append(Literal(value))
			}
			
			return Call(arguments: args, type: Function.in)
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
	final func expressionForForeignFiltering(_ row: Row) -> Expression {
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
	public final func expressionReplacingIdentityReferencesWith(_ newExpression: Expression) -> Expression {
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
