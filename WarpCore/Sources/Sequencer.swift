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
import SwiftParser

/** The sequencer generates series of values based on a pattern that looks like a regex. For example, the sequencer with
formula "[abc]" will generate values "a", "b" and "c". The syntax is as follows:

- ab: a follows b (e.g. ["ab"])
- a|b: a or b (["a","b"])
- a?: a or nothing (["a",""]). Note that unlike regexes the '?' operator applies to the full string before it (e.g. 
  'test?' will generate 'test'  and '').
- [abc]: a, b or c (["a","b","c"])
- [a-z]: any character from a to z inclusive (["a"..."z"])
- (a): subsequence

The sequencer will return any possible combination, e.g. [abc][def] will lead to a sequence of the values ad,ae,af...cf.
*/
public class Sequencer: Parser {
	private let reservedCharacters: [Character] = ["[", "]", "(", ")", "-", "\\", "'", "|", "?", "{", "}"]
	private let specialCharacters: [Character: Character] = [
		"t": "\t",
		"n": "\n",
		"r": "\r",
		" ": " "
	]
	private var stack = Stack<ValueSequence>()
	
	public init?(_ formula: String) {
		let reservedCharactersRule = Parser.matchAnyFrom(reservedCharacters.map({ return Parser.matchLiteral(String($0)) }))
		let specialCharactersRule = Parser.matchAnyFrom(specialCharacters.keys.map({ return Parser.matchLiteral(String($0)) }))
		let escapes = Parser.matchLiteral("\\") ~ (reservedCharactersRule | specialCharactersRule)

		let grammar = Grammar();
		super.init(grammar: grammar)

		grammar["number"] = (("0" - "9")++)
		grammar["escapedCharacter"] = escapes => pushValue
		grammar["character"] = Parser.matchAnyCharacterExcept(reservedCharacters) => pushValue
		grammar["string"] = (Parser.matchAnyCharacterExcept(reservedCharacters) | escapes)++ => pushString
		grammar["charRange"] = (Parser.matchAnyCharacterExcept(reservedCharacters) ~~ "-" ~~ Parser.matchAnyCharacterExcept(reservedCharacters)) => pushRange
		grammar["charSpec"] = (^"charRange" | ^"escapedCharacter" | ^"character")*

		grammar["charset"] = (Parser.matchLiteral("[") => pushCharset) ~~ ^"charSpec" ~~ "]"
		grammar["component"] = ^"subsequence" | ^"charset" | ^"string"
		grammar["maybe"] = ^"component" ~~ (Parser.matchLiteral("?") => pushMaybe)/~
		grammar["repeat"] = ^"maybe" ~~ (Parser.matchLiteral("{") ~~ (^"number" => pushRepeat) ~~ Parser.matchLiteral("}"))/~

		grammar["following"] = ^"repeat" ~~ ((^"repeat") => pushFollowing)*
		grammar["alternatives"] = ^"following" ~~ (("|" ~~ ^"following") => pushAfter)*
		grammar["subsequence"] = "(" ~~ ^"alternatives" ~~ ")"
		grammar.startRule = ^"alternatives"

		do {
			try _ = self.parse(formula)
		}
		catch {
			return nil
		}

		if stack.items.isEmpty {
			return nil
		}
	}
	
	public var randomValue: Value? {
		return stack.head.random()
	}
	
	public var root: AnySequence<Value>? {
		return AnySequence(stack.head)
	}
	
	public var cardinality: Int? {
		return stack.head.cardinality
	}
	
	private func pushFollowing() {
		let r = stack.pop()
		let l = stack.pop()
		stack.push(CombinatorSequence(left: l, right: r))
	}
	
	private func pushAfter() {
		let then = stack.pop()
		let first = stack.pop()
		stack.push(AfterSequence(first: first, then: then))
	}
	
	private func pushCharset() {
		stack.push(ValueSetSequence())
	}
	
	private func pushValue() {
		if let r = stack.head as? ValueSetSequence {
			r.values.append(Value(unescape(self.text)))
		}
		else {
			fatalError("Not supported!")
		}
	}
	
	private func unescape(_ text: String) -> String {
		var unescapedText = text
		for reserved in reservedCharacters {
			unescapedText = unescapedText.replacingOccurrences(of: "\\\(reserved)", with: String(reserved))
		}
		
		for (specialBefore, specialAfter) in specialCharacters {
			unescapedText = unescapedText.replacingOccurrences(of: "\\\(specialBefore)", with: String(specialAfter))
		}
		return unescapedText
	}
	
	private func pushString() {
		let text = unescape(self.text)
		stack.push(ValueSetSequence([Value(text)]))
	}
	
	private func pushMaybe() {
		let r = stack.pop()
		stack.push(MaybeSequence(r))
	}
	
	private func pushRepeat() {
		if let n = self.text.toInt() {
			let r = stack.pop()
			stack.push(RepeatSequence(r, count: n))
		}
	}
	
	private func pushRange() {
		if let r = stack.head as? ValueSetSequence {
			let items = self.text.components(separatedBy: "-")
			assert(items.count == 2, "Invalid range")
			let startChar: unichar = items[0].utf16.first!
			let endChar: unichar = items[1].utf16.first!

			// [a-Z] and [A-z] are supposed to be equal to [a-zA-Z]
			if (startChar == "a".utf16.first! && endChar == "Z".utf16.first!) ||
				(startChar == "A".utf16.first! && endChar == "z".utf16.first!) {
				for character in ("a".utf16.first!)...("z".utf16.first!) {
					r.values.append(Value(String(Character(UnicodeScalar(character)!))))
				}
				for character in ("A".utf16.first!)...("Z".utf16.first!) {
					r.values.append(Value(String(Character(UnicodeScalar(character)!))))
				}
			}
			else if endChar > startChar {
				for character in startChar...endChar {
					r.values.append(Value(String(Character(UnicodeScalar(character)!))))
				}
			}
		}
		else {
			fatalError("Not supported!")
		}
	}
	
	public func stream(_ column: Column) -> Stream {
		return SequenceStream(AnySequence<Fallible<Tuple>>({ () -> SequencerRowGenerator in
			return SequencerRowGenerator(source: self.root!)
		}), columns: [column], rowCount: stack.head.cardinality)
	}
}

private class ValueGenerator: IteratorProtocol {
	typealias Element = Value

	func next() -> Value? {
		return nil
	}
}

private class ProxyValueGenerator<G: IteratorProtocol>: ValueGenerator where G.Element == Value {
	private var generator: G
	
	init(_ generator: G) {
		self.generator = generator
	}
	
	override func next() -> Value? {
		return generator.next()
	}
}

private class ValueSequence: Sequence {
	typealias Iterator = ValueGenerator
	
	func random() -> Value? {
		fatalError("This should never be called")
	}
	
	func makeIterator() -> ValueGenerator {
		return ValueGenerator()
	}
	
	/** The number of elements this sequence will generate. Nil indicates that the length of this sequence is unknown
	(e.g. very large or infinite) */
	var cardinality: Int? { get {
		return 0
	} }
}

private class ValueSetSequence: ValueSequence {
	var values: [Value] = []
	
	override init() {
	}
	
	init(_ values: [Value]) {
		self.values = values
	}
	
	fileprivate override func random() -> Value? {
		return Array(values).randomElement
	}
	
	override func makeIterator() -> Iterator {
		return ProxyValueGenerator(values.makeIterator())
	}
	
	override var cardinality: Int { get {
		return values.count
	} }
}

private class MaybeGenerator: ValueGenerator {
	var generator: ValueGenerator? = nil
	let sequence: ValueSequence
	
	init(_ sequence: ValueSequence) {
		self.sequence = sequence
	}
	
	fileprivate override func next() -> Value? {
		if let g = generator {
			return g.next()
		}
		else {
			generator = sequence.makeIterator()
			return Value("")
		}
	}
}

private class RepeatGenerator: ValueGenerator {
	var generators: [ValueGenerator] = []
	var values: [Value] = []
	let sequence: ValueSequence
	var done = false
	
	init(_ sequence: ValueSequence, count: Int) {
		self.sequence = sequence
		for _ in 0..<count {
			let gen = sequence.makeIterator()
			self.generators.append(gen)
			values.append(gen.next() ?? Value.invalid)
		}
		self.generators[self.generators.count-1] = sequence.makeIterator()
	}
	
	fileprivate override func next() -> Value? {
		if done {
			return nil
		}

		// Increment
		for i in 0..<generators.count {
			let index = generators.count - i - 1
			let generator = generators[index]
			if let next = generator.next() {
				values[index] = next
				break
			}
			else {
				if index == 0 {
					done = true
					return nil
				}
				
				generators[index] = sequence.makeIterator()
				values[index] = generators[index].next() ?? Value.invalid
				// And do not break, go on to increment next (carry)
			}
		}
		
		// Return value
		return Value(values.map({ return $0.stringValue ?? "" }).joined(separator: ""))
	}
}

private class RepeatSequence: ValueSequence {
	let sequence: ValueSequence
	let repeatCount: Int
	
	init(_ sequence: ValueSequence, count: Int) {
		self.sequence = sequence
		self.repeatCount = count
	}
	
	fileprivate override func random() -> Value? {
		var str = Value("")
		for _ in 0..<repeatCount {
			str = str & (self.sequence.random() ?? Value.invalid)
		}
		return str
	}
	
	fileprivate override func makeIterator() -> ValueGenerator {
		return RepeatGenerator(sequence, count: repeatCount)
	}
	
	
	override var cardinality: Int? { get {
		if let base = sequence.cardinality {
			let d = pow(Double(base), Double(repeatCount))
			if d > Double(Int.max) {
				return nil
			}
			return Int(d)
		}
		return nil
	} }
	
}

private class MaybeSequence: ValueSequence {
	let sequence: ValueSequence
	
	init(_ sequence: ValueSequence) {
		self.sequence = sequence
	}
	
	fileprivate override func random() -> Value? {
		if Bool.random {
			return Value("")
		}
		return self.sequence.random()
	}
	
	fileprivate override func makeIterator() -> ValueGenerator {
		return MaybeGenerator(sequence)
	}
	
	override var cardinality: Int { get {
		return 2
	} }
}

private class CombinatorGenerator: ValueGenerator {
	private var leftGenerator: ValueGenerator
	private var rightGenerator: ValueGenerator
	private let rightSequence: ValueSequence
	private var leftValue: Value?
	
	init(left: ValueSequence, right: ValueSequence) {
		self.leftGenerator = left.makeIterator()
		self.rightGenerator = right.makeIterator()
		self.rightSequence = right
		self.leftValue = self.leftGenerator.next()
	}
	
	override func next() -> Value? {
		if let l = leftValue {
			// Fetch a new right value
			if let r = self.rightGenerator.next() {
				return l & r
			}
			else {
				// need a new left value, reset right value
				self.rightGenerator = self.rightSequence.makeIterator()
				leftValue = self.leftGenerator.next()
				if let l = leftValue {
					if let r = self.rightGenerator.next() {
						return l & r
					}
					else {
						return nil
					}
				}
				else {
					return nil
				}
			}
		}
		else {
			return nil
		}
	}
}

private class AfterGenerator: ValueGenerator {
	private var firstGenerator: ValueGenerator
	private var thenGenerator: ValueGenerator
	
	init(first: ValueSequence, then: ValueSequence) {
		self.firstGenerator = first.makeIterator()
		self.thenGenerator = then.makeIterator()
	}
	
	override func next() -> Value? {
		if let l = firstGenerator.next() {
			return l
		}
		else {
			return thenGenerator.next()
		}
	}
}

private class CombinatorSequence: ValueSequence {
	let left: ValueSequence
	let right: ValueSequence
	
	init(left: ValueSequence, right: ValueSequence) {
		self.left = left
		self.right = right
	}
	
	fileprivate override func random() -> Value? {
		if let a = left.random(), let b = right.random() {
			return a & b
		}
		return nil
	}
	
	override func makeIterator() -> ValueGenerator {
		return CombinatorGenerator(left: self.left, right: self.right)
	}
	
	override var cardinality: Int? { get {
		if let l = left.cardinality, let r = right.cardinality {
			return l * r
		}
		return nil
	} }
}

private class AfterSequence: ValueSequence {
	let first: ValueSequence
	let then: ValueSequence
	
	init(first: ValueSequence, then: ValueSequence) {
		self.first = first
		self.then = then
	}
	
	fileprivate override func random() -> Value? {
		if Bool.random {
			return first.random()
		}
		else {
			return then.random()
		}
	}
	
	override func makeIterator() -> ValueGenerator {
		return AfterGenerator(first: self.first, then: self.then)
	}
	
	override var cardinality: Int? { get {
		if let f = first.cardinality, let s = then.cardinality {
			return f + s
		}
		return nil
	} }
}

private class SequencerRowGenerator: IteratorProtocol {
	let source: AnyIterator<Value>
	typealias Element = Fallible<Tuple>
	
	init(source: AnySequence<Value>) {
		self.source = source.makeIterator()
	}
	
	func next() -> Fallible<Tuple>? {
		if let n = source.next() {
			return .success([n])
		}
		return nil
	}
}
