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

class QBEFormula: Parser {
	private var stack = QBEStack<QBEFunction>()
	
	var root: QBEFunction {
		get {
			return stack.head
		}
	}
	
	init?(formula: String) {
		super.init()
		if !self.parse(formula) {
			return nil
		}
	}
	
	private func pushNumber() {
		stack.push(QBELiteralFunction(QBEValue(self.text.toInt()!)))
	}
	
	private func pushString() {
		stack.push(QBELiteralFunction(QBEValue(self.text)))
	}
	
	private func pushAddition() {
		let a = stack.pop()
		let b = stack.pop()
		stack.push(QBEBinaryFunction(first:a, second: b, type: QBEBinary.Addition))
	}
	
	private func pushSubtraction() {
		let a = stack.pop()
		let b = stack.pop()
		stack.push(QBEBinaryFunction(first:a, second: b, type: QBEBinary.Subtraction))
	}
	
	private func pushMultiplication() {
		let a = stack.pop()
		let b = stack.pop()
		stack.push(QBEBinaryFunction(first:a, second: b, type: QBEBinary.Multiplication))
	}
	
	private func pushDivision() {
		let a = stack.pop()
		let b = stack.pop()
		stack.push(QBEBinaryFunction(first:a, second: b, type: QBEBinary.Division))
	}
	
	private func pushPower() {
		let a = stack.pop()
		let b = stack.pop()
		stack.push(QBEBinaryFunction(first:a, second: b, type: QBEBinary.Power))
	}
	
	private func pushConcat() {
		let a = stack.pop()
		let b = stack.pop()
		stack.push(QBEBinaryFunction(first:a, second: b, type: QBEBinary.Concatenation))
	}
	
	private func pushNegate() {
		let a = stack.pop()
		stack.push(QBECompoundFunction(first: a, second: QBENegateFunction()));
	}
	
	override func rules() {
		let stringLiteral = ("\"" ~ (("a"-"z") => pushString) ~ "\"")
		
		let positiveNumber = ("0"-"9")+ => pushNumber
		let negativeNumber = ("-" ~ positiveNumber) => pushNegate
		add_named_rule("number", rule: negativeNumber | positiveNumber | stringLiteral | (("(" ~ (^"concatenation") ~ ")")))
		add_named_rule("exponent", rule: ^"number" ~ (("^" ~ ^"number") => pushPower)*)
		
		let factor = ^"exponent" ~ ((("*" ~ ^"exponent") => pushMultiplication) | (("/" ~ ^"exponent") => pushDivision))*
		let addition = factor ~ (("+" ~ factor => pushAddition) | ("-" ~ factor => pushSubtraction))*
		add_named_rule("concatenation", rule: addition ~ (("&" ~ addition) => pushConcat)*)
		
		let formula = "=" ~ ^"concatenation"
		start_rule = formula
	}
}