import Foundation
import SwiftParser

struct QBEStack<T> {
	var items = [T]()

	mutating func push(item: T) {
		items.append(item)
	}
	mutating func pop() -> T {
		return items.removeLast()
	}
	
	var head: T { get {
		return items.last!
	} }
}

internal func matchAnyCharacterExcept(characters: [Character]) -> ParserRule {
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

internal func matchAnyFrom(rules: [ParserRule]) -> ParserRule {
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

class QBEFormula: Parser {
	private var stack = QBEStack<QBEFunction>()
	let locale: QBELocale
	
	var root: QBEFunction {
		get {
			return stack.head
		}
	}
	
	init?(formula: String, locale: QBELocale = QBEDefaultLocale()) {
		self.locale = locale
		super.init()
		if !self.parse(formula) {
			return nil
		}
		println("parsed \(root.explanation)")
	}
	
	private func pushInt() {
		stack.push(QBELiteralFunction(QBEValue(self.text.toInt()!)))
	}
	
	private func pushDouble() {
		stack.push(QBELiteralFunction(QBEValue(self.text.toDouble()!)))
	}
	
	private func pushString() {
		let text = self.text.stringByReplacingOccurrencesOfString("\"\"", withString: "\"")
		stack.push(QBELiteralFunction(QBEValue(text)))
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
		stack.push(QBECompoundFunction(first: a, second: QBENegateFunction()));
	}
	
	private func pushSibling() {
		stack.push(QBESiblingFunction(columnName: self.text))
	}
	
	private func pushConstant() {
		if let value = locale.constants[self.text] {
			stack.push(QBELiteralFunction(value));
		}
	}
	
	private func pushPercentagePostfix() {
		let a = stack.pop()
		stack.push(QBEBinaryFunction(first: QBELiteralFunction(QBEValue(100)), second: a, type: QBEBinary.Division))
	}
	
	private func pushBinary(type: QBEBinary) {
		let a = stack.pop()
		let b = stack.pop()
		stack.push(QBEBinaryFunction(first:a, second: b, type: type))
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
	
	private func pushEqual() {
		pushBinary(QBEBinary.Equal)
	}
	
	private func pushNotEqual() {
		pushBinary(QBEBinary.NotEqual)
	}
	
	override func rules() {
		// String literals & constants
		add_named_rule("constant",			rule: matchAnyFrom(locale.constants.keys.array.map({i in return literal(i)})) => pushConstant)
		add_named_rule("stringLiteral",		rule: "\"" ~  ((matchAnyCharacterExcept(["\""]) | "\"\"")* => pushString) ~ "\"")
		add_named_rule("sibling",			rule: "[@" ~  (matchAnyCharacterExcept(["]"])+ => pushSibling) ~ "]")
		add_named_rule("subexpression",		rule: (("(" ~ (^"logic") ~ ")")))
		
		// Number literals
		add_named_rule("digits",			rule: ("0"-"9")+)
		add_named_rule("integerNumber",		rule: (^"digits") => pushInt)
		add_named_rule("percentagePostfix", rule: (literal("%") => pushPercentagePostfix)/~)
		add_named_rule("doubleNumber",		rule: (^"digits" ~ (locale.decimalSeparator ~ ^"digits")/~) => pushDouble)
		add_named_rule("negativeNumber",	rule: ("-" ~ ^"doubleNumber") => pushNegate)
		add_named_rule("percentageNumber",  rule: (^"negativeNumber" | ^"doubleNumber") ~ ^"percentagePostfix")
		
		add_named_rule("value", rule: ^"percentageNumber" | ^"stringLiteral" | ^"constant" | ^"sibling" | ^"subexpression")
		add_named_rule("exponent", rule: ^"value" ~ (("^" ~ ^"value") => pushPower)*)
		
		let factor = ^"exponent" ~ ((("*" ~ ^"exponent") => pushMultiplication) | (("/" ~ ^"exponent") => pushDivision))*
		let addition = factor ~ (("+" ~ factor => pushAddition) | ("-" ~ factor => pushSubtraction))*
		add_named_rule("concatenation", rule: addition ~ (("&" ~ addition) => pushConcat)*)
		
		// Comparisons
		add_named_rule("greater", rule: (">" ~ ^"concatenation") => pushGreater)
		add_named_rule("greaterEqual", rule: (">=" ~ ^"concatenation") => pushGreaterEqual)
		add_named_rule("lesser", rule: ("<" ~ ^"concatenation") => pushLesser)
		add_named_rule("lesserEqual", rule: ("<=" ~ ^"concatenation") => pushLesserEqual)
		add_named_rule("equal", rule: ("=" ~ ^"concatenation") => pushEqual)
		add_named_rule("notEqual", rule: ("<>" ~ ^"concatenation") => pushNotEqual)
		add_named_rule("logic", rule: ^"concatenation" ~ (^"greater" | ^"greaterEqual" | ^"lesser" | ^"lesserEqual" | ^"equal" | ^"notEqual")*)
		let formula = "=" ~ ^"logic"
		start_rule = formula
	}
}