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
class QBESequencer: Parser {
	private var stack = QBEStack<QBEValueSequence>()
	
	init?(_ formula: String) {
		super.init()
		if !self.parse(formula) {
			return nil
		}
	}
	
	var root: AnySequence<QBEValue>? {
		get {
			return AnySequence(stack.head)
		}
	}
	
	private func pushFollowing() {
		let r = stack.pop()
		let l = stack.pop()
		stack.push(QBECombinatorSequence(left: l, right: r))
	}
	
	private func pushAfter() {
		let then = stack.pop()
		let first = stack.pop()
		stack.push(QBEAfterSequence(first: first, then: then))
	}
	
	private func pushCharset() {
		stack.push(QBEValueSetSequence())
	}
	
	private func pushValue() {
		if let r = stack.head as? QBEValueSetSequence {
			r.values.insert(QBEValue(self.text))
		}
		else {
			fatalError("Not supported!")
		}
	}
	
	private func pushString() {
		stack.push(QBEValueSetSequence(Set([QBEValue(self.text)])))
	}
	
	private func pushMaybe() {
		let r = stack.pop()
		stack.push(QBEMaybeSequence(r))
	}
	
	private func pushRange() {
		if let r = stack.head as? QBEValueSetSequence {
			let items = self.text.componentsSeparatedByString("-")
			assert(items.count == 2, "Invalid range")
			let startChar: unichar = items[0].utf16.first!
			let endChar: unichar = items[1].utf16.first!
			
			if endChar > startChar {
				for character in startChar...endChar {
					r.values.insert(QBEValue(String(Character(UnicodeScalar(character)))))
				}
			}
		}
		else {
			fatalError("Not supported!")
		}
	}
	
	override func rules() {
		let reservedCharacters: [Character] = ["[", "]", "(", ")", "-", "\\", "'", "|", "?"]
		
		add_named_rule("escapedCharacter", rule: "\\" ~~ (Parser.matchAnyCharacterExcept([]) => pushValue))
		add_named_rule("character", rule: (Parser.matchAnyCharacterExcept(reservedCharacters) => pushValue))
		add_named_rule("string", rule: ((Parser.matchAnyCharacterExcept(reservedCharacters)++) => pushString))
		add_named_rule("charRange", rule: (^"character" ~~ "-" ~~ ^"character") => pushRange)
		add_named_rule("charSpec", rule: (^"charRange" | ^"escapedCharacter" | ^"character")*)
		
		add_named_rule("charset", rule: ((Parser.matchLiteralInsensitive("[") => pushCharset) ~~ ^"charSpec" ~~ "]"))
		add_named_rule("component", rule: ^"subsequence" | ^"charset" | ^"string")
		add_named_rule("maybe", rule: ^"component" ~~ (Parser.matchLiteralInsensitive("?") => pushMaybe)/~)
		add_named_rule("following", rule: ^"maybe" ~~ ((^"maybe") => pushFollowing)*)
		add_named_rule("alternatives", rule: ^"following" ~~ (("|" ~ ^"following") => pushAfter)*)
		add_named_rule("subsequence", rule: "(" ~~ ^"alternatives" ~~ ")")
		
		start_rule = ^"alternatives"
	}
}

private class QBEValueGenerator: AnyGenerator<QBEValue> {
	override func next() -> Element? {
		return nil
	}
}

private class QBEProxyValueGenerator<G: GeneratorType where G.Element == QBEValue>: QBEValueGenerator {
	private var generator: G
	
	init(_ generator: G) {
		self.generator = generator
	}
	
	override func next() -> QBEValue? {
		return generator.next()
	}
}

private class QBEValueSequence: SequenceType {
	typealias Generator = QBEValueGenerator
	
	func generate() -> QBEValueGenerator {
		return QBEValueGenerator()
	}
}

private class QBEValueSetSequence: QBEValueSequence {
	var values: Set<QBEValue> = []
	
	override init() {
	}
	
	init(_ values: Set<QBEValue>) {
		self.values = values
	}
	
	override func generate() -> Generator {
		return QBEProxyValueGenerator(values.generate())
	}
}

private class QBEMaybeGenerator: QBEValueGenerator {
	var generator: QBEValueGenerator? = nil
	let sequence: QBEValueSequence
	
	init(_ sequence: QBEValueSequence) {
		self.sequence = sequence
	}
	
	private override func next() -> QBEValue? {
		if let g = generator {
			return g.next()
		}
		else {
			generator = sequence.generate()
			return QBEValue("")
		}
	}
}

private class QBEMaybeSequence: QBEValueSequence {
	let sequence: QBEValueSequence
	
	init(_ sequence: QBEValueSequence) {
		self.sequence = sequence
	}
	
	private override func generate() -> QBEValueGenerator {
		return QBEMaybeGenerator(sequence)
	}
}

private class QBECombinatorGenerator: QBEValueGenerator {
	private var leftGenerator: QBEValueGenerator
	private var rightGenerator: QBEValueGenerator
	private let rightSequence: QBEValueSequence
	private var leftValue: QBEValue?
	
	init(left: QBEValueSequence, right: QBEValueSequence) {
		self.leftGenerator = left.generate()
		self.rightGenerator = right.generate()
		self.rightSequence = right
		self.leftValue = self.leftGenerator.next()
	}
	
	override func next() -> QBEValue? {
		if let l = leftValue {
			// Fetch a new right value
			if let r = self.rightGenerator.next() {
				return l & r
			}
			else {
				// need a new left value, reset right value
				self.rightGenerator = self.rightSequence.generate()
				leftValue = self.leftGenerator.next()
				return next()
			}
		}
		else {
			return nil
		}
	}
}

private class QBEAfterGenerator: QBEValueGenerator {
	private var firstGenerator: QBEValueGenerator
	private var thenGenerator: QBEValueGenerator
	
	init(first: QBEValueSequence, then: QBEValueSequence) {
		self.firstGenerator = first.generate()
		self.thenGenerator = then.generate()
	}
	
	override func next() -> QBEValue? {
		if let l = firstGenerator.next() {
			return l
		}
		else {
			return thenGenerator.next()
		}
	}
}

private class QBECombinatorSequence: QBEValueSequence {
	let left: QBEValueSequence
	let right: QBEValueSequence
	
	init(left: QBEValueSequence, right: QBEValueSequence) {
		self.left = left
		self.right = right
	}
	
	override func generate() -> QBEValueGenerator {
		return QBECombinatorGenerator(left: self.left, right: self.right)
	}
}

private class QBEAfterSequence: QBEValueSequence {
	let first: QBEValueSequence
	let then: QBEValueSequence
	
	init(first: QBEValueSequence, then: QBEValueSequence) {
		self.first = first
		self.then = then
	}
	
	override func generate() -> QBEValueGenerator {
		return QBEAfterGenerator(first: self.first, then: self.then)
	}
}