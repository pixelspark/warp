import Foundation
import SwiftParser

/** Formula parses formulas written down in an Excel-like syntax (e.g. =SUM(SQRT(1+2/3);IF(1>2;3;4))) as a Expression
that can be used to calculate values. Like in Excel, the language used for the formulas (e.g. for function names) depends
on the user's preference and is therefore variable (Language implements this). */
public class Formula: Parser {
	/** The character that indicates a formula starts. While it is not required in the formula syntax, it can be used to 
	distinguish text and other static data from formulas. **/
	public static let prefix = "="

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
	let locale: Language
	public let originalText: String
	public private(set) var fragments: [Fragment] = []
	private var error: Bool = false
	
	public var root: Expression {
		get {
			return stack.head
		}
	}
	
	public init?(formula: String, locale: Language) {
		self.originalText = formula
		self.locale = locale
		self.fragments = []
		super.init()
		if !self.parse(formula) || self.error {
			return nil
		}
		super.captures.removeAll(keepingCapacity: false)
	}
	
	private func annotate(_ expression: Expression) {
		if let cc = super.current_capture {
			fragments.append(Fragment(start: cc.start, end: cc.end, expression: expression))
		}
	}
	
	private func pushInt() {
		annotate(stack.push(Literal(Value(Int(self.text)!))))
	}
	
	private func pushDouble() {
		if let n = self.locale.numberFormatter.number(from: self.text.replacingOccurrences(of: self.locale.groupingSeparator, with: "")) {
			annotate(stack.push(Literal(Value.double(n.doubleValue))))
		}
		else {
			annotate(stack.push(Literal(Value.invalid)))
			error = true
		}
	}
	
	private func pushTimestamp() {
		let ts = self.text.substring(from: self.text.characters.index(self.text.startIndex, offsetBy: 1))
		if let n = self.locale.numberFormatter.number(from: ts) {
			annotate(stack.push(Literal(Value.date(n.doubleValue))))
		}
		else {
			annotate(stack.push(Literal(Value.invalid)))
		}
	}
	
	private func pushString() {
		let text = self.text.replacingOccurrences(of: "\"\"", with: "\"")
		annotate(stack.push(Literal(Value(text))))
	}
	
	private func pushAddition() {
		pushBinary(Binary.addition)
	}
	
	private func pushSubtraction() {
		pushBinary(Binary.subtraction)
	}
	
	private func pushMultiplication() {
		pushBinary(Binary.multiplication)
	}

	private func pushModulus() {
		pushBinary(Binary.modulus)
	}
	
	private func pushDivision() {
		pushBinary(Binary.division)
	}
	
	private func pushPower() {
		pushBinary(Binary.power)
	}
	
	private func pushConcat() {
		pushBinary(Binary.concatenation)
	}
	
	private func pushNegate() {
		let a = stack.pop()
		stack.push(Call(arguments: [a], type: Function.Negate));
	}
	
	private func pushSibling() {
		annotate(stack.push(Sibling(Column(self.text))))
	}
	
	private func pushForeign() {
		annotate(stack.push(Foreign(Column(self.text))))
	}
	
	private func pushConstant() {
		for (constant, name) in locale.constants {
			if name.caseInsensitiveCompare(self.text) == ComparisonResult.orderedSame {
				annotate(stack.push(Literal(constant)))
				return
			}
		}
	}

	private func pushPostfixMultiplier(_ factor: Value) {
		let a = stack.pop()
		annotate(stack.push(Comparison(first: Literal(factor), second: a, type: Binary.multiplication)))
	}
	
	private func pushBinary(_ type: Binary) {
		let a = stack.pop()
		let b = stack.pop()
		stack.push(Comparison(first:a, second: b, type: type))
	}

	private func pushIndex() {
		let a = stack.pop()
		let b = stack.pop()
		stack.push(Call(arguments: [b, a], type: .Nth))
	}
	
	private func pushGreater() {
		pushBinary(Binary.greater)
	}
	
	private func pushGreaterEqual() {
		pushBinary(Binary.greaterEqual)
	}
	
	private func pushLesser() {
		pushBinary(Binary.lesser)
	}
	
	private func pushLesserEqual() {
		pushBinary(Binary.lesserEqual)
	}
	
	private func pushContainsString() {
		pushBinary(Binary.containsString)
	}
	
	private func pushContainsStringStrict() {
		pushBinary(Binary.containsStringStrict)
	}
	
	private func pushEqual() {
		pushBinary(Binary.equal)
	}
	
	private func pushNotEqual() {
		pushBinary(Binary.notEqual)
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
			.map({ return self.locale.nameForFunction($0) ?? "" })
			.sorted(by: { (a,b) in return a.characters.count > b.characters.count})
		
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
		add_named_rule("indexedValue", rule: ^"value" ~~ (("[" ~~ ^"value" ~~ "]") => pushIndex)*)
		add_named_rule("exponent", rule: ^"indexedValue" ~~ (("^" ~~ ^"indexedValue") => pushPower)*)
		let factor = ^"exponent" ~~ ((("*" ~~ ^"exponent") => pushMultiplication) | (("/" ~~ ^"exponent") => pushDivision) | (("~" ~~ ^"exponent") => pushModulus))*
		let addition = factor ~~ (("+" ~~ factor => pushAddition) | ("-" ~~ factor => pushSubtraction))*
		add_named_rule("concatenation", rule: addition ~~ (("&" ~~ addition) => pushConcat)*)
		
		// Comparisons
		add_named_rule("containsString", rule: ("~=" ~~ ^"concatenation") => pushContainsString)
		add_named_rule("containsStringStrict", rule: ("~~=" ~~ ^"concatenation") => pushContainsStringStrict)
		add_named_rule("matchesRegex", rule: ("±=" ~~ ^"concatenation") => { [unowned self] in self.pushBinary(Binary.matchesRegex) })
		add_named_rule("matchesRegexStrict", rule: ("±±=" ~~ ^"concatenation") => { [unowned self] in self.pushBinary(Binary.matchesRegexStrict)})
		add_named_rule("greater", rule: (">" ~~ ^"concatenation") => pushGreater)
		add_named_rule("greaterEqual", rule: (">=" ~~ ^"concatenation") => pushGreaterEqual)
		add_named_rule("lesser", rule: ("<" ~~ ^"concatenation") => pushLesser)
		add_named_rule("lesserEqual", rule: ("<=" ~~ ^"concatenation") => pushLesserEqual)
		add_named_rule("equal", rule: ("=" ~~ ^"concatenation") => pushEqual)
		add_named_rule("notEqual", rule: ("<>" ~~ ^"concatenation") => pushNotEqual)
		add_named_rule("logic", rule: ^"concatenation" ~~ (^"greaterEqual" | ^"greater" | ^"lesserEqual" | ^"lesser" | ^"equal" | ^"notEqual" | ^"containsString" | ^"containsStringStrict" | ^"matchesRegex" | ^"matchesRegexStrict" )*)
		let formula = (Formula.prefix)/~ ~~ self.whitespace ~~ (^"logic")*!*
		start_rule = formula
	}
}

internal extension Parser {
	static func matchAnyCharacterExcept(_ characters: [Character]) -> ParserRule {
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
	
	static func matchAnyFrom(_ rules: [ParserRule]) -> ParserRule {
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
	
	static func matchList(_ item: ParserRule, separator: ParserRule) -> ParserRule {
		return item/~ ~~ (separator ~~ item)*
	}
	
	static func matchLiteralInsensitive(_ string:String) -> ParserRule {
		return {(parser: Parser, reader: Reader) -> Bool in
			let pos = reader.position
			
			for ch in string.characters {
				let flag = (String(ch).caseInsensitiveCompare(String(reader.read())) == ComparisonResult.orderedSame)
				
				if !flag {
					reader.seek(pos)
					return false
				}
			}
			return true
		}
	}

	static func matchLiteral(_ string:String) -> ParserRule {
		return {(parser: Parser, reader: Reader) -> Bool in
			let pos = reader.position

			for ch in string.characters {
				if ch != reader.read() {
					reader.seek(pos)
					return false
				}
			}
			return true
		}
	}
}

private struct CallSite {
	let function: Function
	var args: [Expression] = []
	
	init(function: Function) {
		self.function = function
	}
}
