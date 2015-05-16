import Foundation
import SwiftParser

private struct QBEStack<T> {
	var items = [T]()

	mutating func push(item: T) -> T {
		items.append(item)
		return item
	}
	
	mutating func pop() -> T {
		return items.removeLast()
	}
	
	var head: T { get {
		return items.last!
	} }
}

private func matchAnyCharacterExcept(characters: [Character]) -> ParserRule {
	return {(parser: Parser, reader: Reader) -> Bool in
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

private func matchAnyFrom(rules: [ParserRule]) -> ParserRule {
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

private func matchList(item: ParserRule, separator: ParserRule) -> ParserRule {
	return (item ~~ separator)* ~~ item/~
}

private func matchLiteralInsensitive(string:String) -> ParserRule {
	return {(parser: Parser, reader: Reader) -> Bool in
		let pos = reader.position
		
		for ch in string {
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
a ~~ b means: a followed by b with whitespace allowed in between). **/
private let matchWhitespace: ParserRule = (" " | "\t" | "\r\n" | "\r" | "\n")*

infix operator  ~~ {associativity left precedence 10}
private func ~~ (left: String, right: String) -> ParserRule {
	return literal(left) ~~ literal(right)
}

private func ~~ (left: String, right: ParserRule) -> ParserRule {
	return literal(left) ~~ right
}

private func ~~ (left: ParserRule, right: String) -> ParserRule {
	return left ~~ literal(right)
}

private func ~~ (left : ParserRule, right: ParserRule) -> ParserRule {
	return {(parser: Parser, reader: Reader) -> Bool in
		return left(parser: parser, reader: reader) && matchWhitespace(parser: parser, reader: reader) && right(parser: parser, reader: reader)
	}
}

private struct QBECall {
	let function: QBEFunction
	var args: [QBEExpression] = []
	
	init(function: QBEFunction) {
		self.function = function
	}
}

/** QBEFormula parses formulas written down in an Excel-like syntax (e.g. =SUM(SQRT(1+2/3);IF(1>2;3;4))) as a QBEExpression
that can be used to calculate values. Like in Excel, the language used for the formulas (e.g. for function names) depends
on the user's preference and is therefore variable (QBELocale implements this). **/
class QBEFormula: Parser {
	struct Fragment {
		let start: Int
		let end: Int
		let expression: QBEExpression
		
		var length: Int { get {
			return end - start
		} }
	}
	
	private var stack = QBEStack<QBEExpression>()
	private var callStack = QBEStack<QBECall>()
	let locale: QBELocale
	var fragments: [Fragment] = []
	
	var root: QBEExpression {
		get {
			return stack.head
		}
	}
	
	init?(formula: String, locale: QBELocale) {
		self.locale = locale
		self.fragments = []
		super.init()
		if !self.parse(formula) {
			return nil
		}
	}
	
	private func annotate(expression: QBEExpression) {
		if let cc = super.current_capture {
			fragments.append(Fragment(start: cc.start, end: cc.end, expression: expression))
		}
	}
	
	private func pushInt() {
		annotate(stack.push(QBELiteralExpression(QBEValue(self.text.toInt()!))))
	}
	
	private func pushDouble() {
		annotate(stack.push(QBELiteralExpression(QBEValue(self.text.toDouble()!))))
	}
	
	private func pushString() {
		let text = self.text.stringByReplacingOccurrencesOfString("\"\"", withString: "\"")
		annotate(stack.push(QBELiteralExpression(QBEValue(text))))
	}
	
	private func pushAddition() {
		pushBinary(QBEBinary.Addition)
	}
	
	private func pushSubtraction() {
		pushBinary(QBEBinary.Subtraction)
	}
	
	private func pushMultiplication() {
		pushBinary(QBEBinary.Multiplication)
	}
	
	private func pushDivision() {
		pushBinary(QBEBinary.Division)
	}
	
	private func pushPower() {
		pushBinary(QBEBinary.Power)
	}
	
	private func pushConcat() {
		pushBinary(QBEBinary.Concatenation)
	}
	
	private func pushNegate() {
		let a = stack.pop()
		stack.push(QBEFunctionExpression(arguments: [a], type: QBEFunction.Negate));
	}
	
	private func pushSibling() {
		annotate(stack.push(QBESiblingExpression(columnName: QBEColumn(self.text))))
	}
	
	private func pushForeign() {
		annotate(stack.push(QBEForeignExpression(columnName: QBEColumn(self.text))))
	}
	
	private func pushConstant() {
		for (constant, name) in locale.constants {
			if name.caseInsensitiveCompare(self.text) == NSComparisonResult.OrderedSame {
				annotate(stack.push(QBELiteralExpression(constant)))
				return
			}
		}
	}
	
	private func pushPercentagePostfix() {
		let a = stack.pop()
		annotate(stack.push(QBEBinaryExpression(first: QBELiteralExpression(QBEValue(100)), second: a, type: QBEBinary.Division)))
	}
	
	private func pushBinary(type: QBEBinary) {
		let a = stack.pop()
		let b = stack.pop()
		stack.push(QBEBinaryExpression(first:a, second: b, type: type))
	}
	
	private func pushGreater() {
		pushBinary(QBEBinary.Greater)
	}
	
	private func pushGreaterEqual() {
		pushBinary(QBEBinary.GreaterEqual)
	}
	
	private func pushLesser() {
		pushBinary(QBEBinary.Lesser)
	}
	
	private func pushLesserEqual() {
		pushBinary(QBEBinary.LesserEqual)
	}
	
	private func pushContainsString() {
		pushBinary(QBEBinary.ContainsString)
	}
	
	private func pushContainsStringStrict() {
		pushBinary(QBEBinary.ContainsStringStrict)
	}
	
	private func pushEqual() {
		pushBinary(QBEBinary.Equal)
	}
	
	private func pushNotEqual() {
		pushBinary(QBEBinary.NotEqual)
	}
	
	private func pushCall() {
		if let qu = locale.functionWithName(self.text) {
			callStack.push(QBECall(function: qu))
			return
		}
		
		// This should not happen
		fatalError("Parser rule lead to pushing a function that doesn't exist!")
	}
	
	private func pushIdentity() {
		annotate(stack.push(QBEIdentityExpression()))
	}
	
	private func popCall() {
		var q = callStack.pop()
		
		// For some reason the parser doubly adds the last argument, remove it
		assert(q.args.count != 1, "The parser doubly adds the last parameter to a function, so there cannot be just one argument")
		if q.args.count > 0 {
			q.args.removeLast()
		}
		annotate(stack.push(QBEFunctionExpression(arguments: q.args, type: q.function)))
	}
	
	private func pushArgument() {
		let q = stack.pop()
		var call = callStack.pop()
		call.args.append(q)
		callStack.push(call)
	}
	
	override func rules() {
		/* We need to sort the function names by length (longest first) to make sure the right one gets matched. If the 
		shorter functions come first, they match with the formula before we get a chance to see whether the longer one 
		would also match  (parser is dumb) */
		var functionRules: [ParserRule] = []
		let functionNames = QBEFunction.allFunctions
			.map({return self.locale.nameForFunction($0) ?? ""})
			.sorted({(a,b) in return count(a) > count(b)})
		
		functionNames.each({(functionName) in
			if !functionName.isEmpty {
				functionRules.append(matchLiteralInsensitive(functionName))
			}
		})
		
		// String literals & constants
		add_named_rule("arguments",			rule: (("(" ~~ matchList(^"logic" => pushArgument, literal(locale.argumentSeparator)) ~~ ")")))
		add_named_rule("unaryFunction",		rule: ((matchAnyFrom(functionRules) => pushCall) ~~ ^"arguments") => popCall)
		add_named_rule("constant",			rule: matchAnyFrom(locale.constants.values.array.map({matchLiteralInsensitive($0)})) => pushConstant)
		add_named_rule("stringLiteral",		rule: literal(String(locale.stringQualifier)) ~  ((matchAnyCharacterExcept([locale.stringQualifier]) | locale.stringQualifierEscape)* => pushString) ~ literal(String(locale.stringQualifier)))
		
		add_named_rule("currentCell",		rule: literal(locale.currentCellIdentifier) => pushIdentity)
		
		add_named_rule("sibling",			rule: "[@" ~  (matchAnyCharacterExcept(["]"])+ => pushSibling) ~ "]")
		add_named_rule("foreign",			rule: "[#" ~  (matchAnyCharacterExcept(["]"])+ => pushForeign) ~ "]")
		add_named_rule("subexpression",		rule: (("(" ~~ (^"logic") ~~ ")")))
		
		// Number literals
		add_named_rule("digits",			rule: ("0"-"9")+)
		add_named_rule("integerNumber",		rule: (^"digits") => pushInt)
		add_named_rule("percentagePostfix", rule: (literal("%") => pushPercentagePostfix)/~)
		add_named_rule("doubleNumber",		rule: (^"digits" ~ (locale.decimalSeparator ~ ^"digits")/~) => pushDouble)
		add_named_rule("negativeNumber",	rule: ("-" ~ ^"doubleNumber") => pushNegate)
		add_named_rule("percentageNumber",  rule: (^"negativeNumber" | ^"doubleNumber") ~ ^"percentagePostfix")
		
		add_named_rule("value", rule: ^"percentageNumber" | ^"stringLiteral" | ^"unaryFunction" | ^"currentCell" | ^"constant" | ^"sibling" | ^"foreign" | ^"subexpression")
		add_named_rule("exponent", rule: ^"value" ~~ (("^" ~~ ^"value") => pushPower)*)
		
		let factor = ^"exponent" ~~ ((("*" ~~ ^"exponent") => pushMultiplication) | (("/" ~~ ^"exponent") => pushDivision))*
		let addition = factor ~~ (("+" ~~ factor => pushAddition) | ("-" ~~ factor => pushSubtraction))*
		add_named_rule("concatenation", rule: addition ~~ (("&" ~~ addition) => pushConcat)*)
		
		// Comparisons
		add_named_rule("containsString", rule: ("~=" ~~ ^"concatenation") => pushContainsString)
		add_named_rule("containsStringStrict", rule: ("~~=" ~~ ^"concatenation") => pushContainsStringStrict)
		add_named_rule("matchesRegex", rule: ("±=" ~~ ^"concatenation") => {self.pushBinary(QBEBinary.MatchesRegex)})
		add_named_rule("matchesRegexStrict", rule: ("±±=" ~~ ^"concatenation") => {self.pushBinary(QBEBinary.MatchesRegexStrict)})
		add_named_rule("greater", rule: (">" ~~ ^"concatenation") => pushGreater)
		add_named_rule("greaterEqual", rule: (">=" ~~ ^"concatenation") => pushGreaterEqual)
		add_named_rule("lesser", rule: ("<" ~~ ^"concatenation") => pushLesser)
		add_named_rule("lesserEqual", rule: ("<=" ~~ ^"concatenation") => pushLesserEqual)
		add_named_rule("equal", rule: ("=" ~~ ^"concatenation") => pushEqual)
		add_named_rule("notEqual", rule: ("<>" ~~ ^"concatenation") => pushNotEqual)
		add_named_rule("logic", rule: ^"concatenation" ~~ (^"greater" | ^"greaterEqual" | ^"lesser" | ^"lesserEqual" | ^"equal" | ^"notEqual" | ^"containsString" | ^"containsStringStrict" | ^"matchesRegex" | ^"matchesRegexStrict" )*)
		let formula = matchWhitespace ~ "=" ~~ (^"logic")*!*
		start_rule = formula
	}
}