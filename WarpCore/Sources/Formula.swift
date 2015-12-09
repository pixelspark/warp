import Foundation
import SwiftParser

/** Formula parses formulas written down in an Excel-like syntax (e.g. =SUM(SQRT(1+2/3);IF(1>2;3;4))) as a Expression
that can be used to calculate values. Like in Excel, the language used for the formulas (e.g. for function names) depends
on the user's preference and is therefore variable (Locale implements this). */
public class Formula: Parser {
	public struct Fragment {
		public let start: Int
		public let end: Int
		public let expression: Expression
		
		public var length: Int { get {
			return end - start
		} }
	}
	
	private var stack = Stack<Expression>()
	private var callStack = Stack<CallSite>()
	let locale: Locale
	public let originalText: String
	public private(set) var fragments: [Fragment] = []
	private var error: Bool = false
	
	public var root: Expression {
		get {
			return stack.head
		}
	}
	
	public init?(formula: String, locale: Locale) {
		self.originalText = formula
		self.locale = locale
		self.fragments = []
		super.init()
		if !self.parse(formula) || self.error {
			return nil
		}
		super.captures.removeAll(keepCapacity: false)
	}
	
	private func annotate(expression: Expression) {
		if let cc = super.current_capture {
			fragments.append(Fragment(start: cc.start, end: cc.end, expression: expression))
		}
	}
	
	private func pushInt() {
		annotate(stack.push(Literal(Value(Int(self.text)!))))
	}
	
	private func pushDouble() {
		if let n = self.locale.numberFormatter.numberFromString(self.text.stringByReplacingOccurrencesOfString(self.locale.groupingSeparator, withString: "")) {
			annotate(stack.push(Literal(Value.DoubleValue(n.doubleValue))))
		}
		else {
			annotate(stack.push(Literal(Value.InvalidValue)))
			error = true
		}
	}
	
	private func pushTimestamp() {
		let ts = self.text.substringFromIndex(self.text.startIndex.advancedBy(1))
		if let n = self.locale.numberFormatter.numberFromString(ts) {
			annotate(stack.push(Literal(Value.DateValue(n.doubleValue))))
		}
		else {
			annotate(stack.push(Literal(Value.InvalidValue)))
		}
	}
	
	private func pushString() {
		let text = self.text.stringByReplacingOccurrencesOfString("\"\"", withString: "\"")
		annotate(stack.push(Literal(Value(text))))
	}
	
	private func pushAddition() {
		pushBinary(Binary.Addition)
	}
	
	private func pushSubtraction() {
		pushBinary(Binary.Subtraction)
	}
	
	private func pushMultiplication() {
		pushBinary(Binary.Multiplication)
	}
	
	private func pushDivision() {
		pushBinary(Binary.Division)
	}
	
	private func pushPower() {
		pushBinary(Binary.Power)
	}
	
	private func pushConcat() {
		pushBinary(Binary.Concatenation)
	}
	
	private func pushNegate() {
		let a = stack.pop()
		stack.push(Call(arguments: [a], type: Function.Negate));
	}
	
	private func pushSibling() {
		annotate(stack.push(Sibling(columnName: Column(self.text))))
	}
	
	private func pushForeign() {
		annotate(stack.push(Foreign(columnName: Column(self.text))))
	}
	
	private func pushConstant() {
		for (constant, name) in locale.constants {
			if name.caseInsensitiveCompare(self.text) == NSComparisonResult.OrderedSame {
				annotate(stack.push(Literal(constant)))
				return
			}
		}
	}

	private func pushPostfixMultiplier(factor: Value) {
		let a = stack.pop()
		annotate(stack.push(Comparison(first: Literal(factor), second: a, type: Binary.Multiplication)))
	}
	
	private func pushBinary(type: Binary) {
		let a = stack.pop()
		let b = stack.pop()
		stack.push(Comparison(first:a, second: b, type: type))
	}
	
	private func pushGreater() {
		pushBinary(Binary.Greater)
	}
	
	private func pushGreaterEqual() {
		pushBinary(Binary.GreaterEqual)
	}
	
	private func pushLesser() {
		pushBinary(Binary.Lesser)
	}
	
	private func pushLesserEqual() {
		pushBinary(Binary.LesserEqual)
	}
	
	private func pushContainsString() {
		pushBinary(Binary.ContainsString)
	}
	
	private func pushContainsStringStrict() {
		pushBinary(Binary.ContainsStringStrict)
	}
	
	private func pushEqual() {
		pushBinary(Binary.Equal)
	}
	
	private func pushNotEqual() {
		pushBinary(Binary.NotEqual)
	}
	
	private func pushCall() {
		if let qu = locale.functionWithName(self.text) {
			callStack.push(CallSite(function: qu))
			return
		}
		
		// This should not happen
		fatalError("Parser rule lead to pushing a function that doesn't exist!")
	}
	
	private func pushIdentity() {
		annotate(stack.push(Identity()))
	}
	
	private func popCall() {
		let q = callStack.pop()
		annotate(stack.push(Call(arguments: q.args, type: q.function)))
	}
	
	private func pushArgument() {
		let q = stack.pop()
		var call = callStack.pop()
		call.args.append(q)
		callStack.push(call)
	}
	
	public override func rules() {
		/* We need to sort the function names by length (longest first) to make sure the right one gets matched. If the 
		shorter functions come first, they match with the formula before we get a chance to see whether the longer one 
		would also match  (parser is dumb) */
		var functionRules: [ParserRule] = []
		let functionNames = Function.allFunctions
			.map({return self.locale.nameForFunction($0) ?? ""}).sort({(a,b) in return a.characters.count > b.characters.count})
		
		functionNames.forEach {(functionName) in
			if !functionName.isEmpty {
				functionRules.append(Parser.matchLiteralInsensitive(functionName))
			}
		}

		let postfixRules = locale.postfixes.map { (postfix, multiplier) in return (literal(postfix) => { [unowned self] in self.pushPostfixMultiplier(multiplier) }) }
		
		// String literals & constants
		add_named_rule("arguments",			rule: (("(" ~~ Parser.matchList(^"logic" => pushArgument, separator: literal(locale.argumentSeparator)) ~~ ")")))
		add_named_rule("unaryFunction",		rule: ((Parser.matchAnyFrom(functionRules) => pushCall) ~~ ^"arguments") => popCall)
		add_named_rule("constant",			rule: Parser.matchAnyFrom(locale.constants.values.map({Parser.matchLiteralInsensitive($0)})) => pushConstant)
		add_named_rule("stringLiteral",		rule: literal(String(locale.stringQualifier)) ~  ((Parser.matchAnyCharacterExcept([locale.stringQualifier]) | locale.stringQualifierEscape)* => pushString) ~ literal(String(locale.stringQualifier)))
		
		add_named_rule("currentCell",		rule: literal(locale.currentCellIdentifier) => pushIdentity)
		
		add_named_rule("sibling",			rule: "[@" ~  (Parser.matchAnyCharacterExcept(["]"])+ => pushSibling) ~ "]")
		add_named_rule("foreign",			rule: "[#" ~  (Parser.matchAnyCharacterExcept(["]"])+ => pushForeign) ~ "]")
		add_named_rule("subexpression",		rule: (("(" ~~ (^"logic") ~~ ")")))
		
		// Number literals
		add_named_rule("digits",			rule: (("0"-"9") | locale.groupingSeparator)+)
		add_named_rule("integerNumber",		rule: (^"digits") => pushInt)
		add_named_rule("numberPostfix", rule: Parser.matchAnyFrom(postfixRules)/~)
		add_named_rule("timestamp",			rule: ("@" ~ ^"digits" ~ (locale.decimalSeparator ~ ^"digits")/~) => pushTimestamp)
		add_named_rule("doubleNumber",		rule: (^"digits" ~ (locale.decimalSeparator ~ ^"digits")/~) => pushDouble)
		add_named_rule("negativeNumber",	rule: ("-" ~ ^"doubleNumber") => pushNegate)
		add_named_rule("postfixedNumber",  rule: (^"negativeNumber" | ^"doubleNumber") ~ ^"numberPostfix")
		
		add_named_rule("value", rule: ^"postfixedNumber" | ^"timestamp" | ^"stringLiteral" | ^"unaryFunction" | ^"currentCell" | ^"constant" | ^"sibling" | ^"foreign" | ^"subexpression")
		add_named_rule("exponent", rule: ^"value" ~~ (("^" ~~ ^"value") => pushPower)*)
		
		let factor = ^"exponent" ~~ ((("*" ~~ ^"exponent") => pushMultiplication) | (("/" ~~ ^"exponent") => pushDivision))*
		let addition = factor ~~ (("+" ~~ factor => pushAddition) | ("-" ~~ factor => pushSubtraction))*
		add_named_rule("concatenation", rule: addition ~~ (("&" ~~ addition) => pushConcat)*)
		
		// Comparisons
		add_named_rule("containsString", rule: ("~=" ~~ ^"concatenation") => pushContainsString)
		add_named_rule("containsStringStrict", rule: ("~~=" ~~ ^"concatenation") => pushContainsStringStrict)
		add_named_rule("matchesRegex", rule: ("±=" ~~ ^"concatenation") => { [unowned self] in self.pushBinary(Binary.MatchesRegex) })
		add_named_rule("matchesRegexStrict", rule: ("±±=" ~~ ^"concatenation") => { [unowned self] in self.pushBinary(Binary.MatchesRegexStrict)})
		add_named_rule("greater", rule: (">" ~~ ^"concatenation") => pushGreater)
		add_named_rule("greaterEqual", rule: (">=" ~~ ^"concatenation") => pushGreaterEqual)
		add_named_rule("lesser", rule: ("<" ~~ ^"concatenation") => pushLesser)
		add_named_rule("lesserEqual", rule: ("<=" ~~ ^"concatenation") => pushLesserEqual)
		add_named_rule("equal", rule: ("=" ~~ ^"concatenation") => pushEqual)
		add_named_rule("notEqual", rule: ("<>" ~~ ^"concatenation") => pushNotEqual)
		add_named_rule("logic", rule: ^"concatenation" ~~ (^"greaterEqual" | ^"greater" | ^"lesserEqual" | ^"lesser" | ^"equal" | ^"notEqual" | ^"containsString" | ^"containsStringStrict" | ^"matchesRegex" | ^"matchesRegexStrict" )*)
		let formula = ("=")/~ ~~ Parser.matchWhitespace ~~ (^"logic")*!*
		start_rule = formula
	}
}

internal extension Parser {
	static func matchAnyCharacterExcept(characters: [Character]) -> ParserRule {
		return {(parser: Parser, reader: Reader) -> Bool in
			if reader.eof() {
				return false
			}
			
			let pos = reader.position
			let ch = reader.read()
			for exceptedCharacter in characters {
				if ch==exceptedCharacter {
					reader.seek(pos)
					return false
				}
			}
			return true
		}
	}
	
	static func matchAnyFrom(rules: [ParserRule]) -> ParserRule {
		return {(parser: Parser, reader: Reader) -> Bool in
			let pos = reader.position
			for rule in rules {
				if(rule(parser: parser, reader: reader)) {
					return true
				}
				reader.seek(pos)
			}
			
			return false
		}
	}
	
	static func matchList(item: ParserRule, separator: ParserRule) -> ParserRule {
		return item/~ ~~ (separator ~~ item)*
	}
	
	static func matchLiteralInsensitive(string:String) -> ParserRule {
		return {(parser: Parser, reader: Reader) -> Bool in
			let pos = reader.position
			
			for ch in string.characters {
				let flag = (String(ch).caseInsensitiveCompare(String(reader.read())) == NSComparisonResult.OrderedSame)
				
				if !flag {
					reader.seek(pos)
					return false
				}
			}
			return true
		}
	}
	
	/** The ~~ operator is a variant of the ~ operator that allows whitespace in between (a ~ b means: a followed by b, whereas
	a ~~ b means: a followed by b with whitespace allowed in between). */
	static let matchWhitespace: ParserRule = (" " | "\t" | "\r\n" | "\r" | "\n")*
}

/** Generate a parser rule that matches the given parser rule at least once, but possibly more */
internal postfix func ++ (left: ParserRule) -> ParserRule {
	return left ~~ left*
}

infix operator  ~~ {associativity left precedence 10}
internal func ~~ (left: String, right: String) -> ParserRule {
	return literal(left) ~~ literal(right)
}

internal func ~~ (left: String, right: ParserRule) -> ParserRule {
	return literal(left) ~~ right
}

internal func ~~ (left: ParserRule, right: String) -> ParserRule {
	return left ~~ literal(right)
}

internal func ~~ (left : ParserRule, right: ParserRule) -> ParserRule {
	return {(parser: Parser, reader: Reader) -> Bool in
		return left(parser: parser, reader: reader) && Parser.matchWhitespace(parser: parser, reader: reader) && right(parser: parser, reader: reader)
	}
}

private struct CallSite {
	let function: Function
	var args: [Expression] = []
	
	init(function: Function) {
		self.function = function
	}
}