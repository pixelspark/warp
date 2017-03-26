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

/** A Reducer is a function that takes multiple arguments, but can receive them in batches in order to calculate the
result, and does not have to store all values. The 'average'  function for instance can maintain a sum of values received
as well as a count, and determine the result at any point by dividing the sum by the count. */
// TODO: implement hierarchical reducers (e.g. so that two SumReducers can be summed, and the reduction can be done in parallel)
public protocol Reducer {
	mutating func add(_ values: [Value])
	var result: Value { get }
}

/** A Function takes a list of Value arguments (which may be empty) and returns a single Value. Functions
each have a unique identifier (used for serializing), display names (which are localized), and arity (which indicates
which number of arguments is allowed) and an implementation. Functions may also be implemented in other ways in other
ways (e.g. by compilation to SQL). Functions that have 'any' arity can be considered to be aggregation functions. */
public enum Function: String {
	case uppercase = "upper"
	case lowercase = "lower"
	case negate = "negate"
	case identity = "identity"
	case absolute = "abs"
	case and = "and"
	case or = "or"
	case xor = "xor"
	case `if` = "if"
	case concat = "concat"
	case cos = "cos"
	case sin = "sin"
	case tan = "tan"
	case cosh = "cosh"
	case sinh = "sinh"
	case tanh = "tanh"
	case acos = "acos"
	case asin = "asin"
	case atan = "atan"
	case sqrt = "sqrt"
	case left = "left"
	case right = "right"
	case mid = "mid"
	case length = "length"
	case log = "log"
	case not = "not"
	case substitute = "substitute"
	case trim = "trim"
	case coalesce = "coalesce"
	case ifError = "iferror"
	case count = "count"
	case sum = "sum"
	case average = "average"
	case min = "min"
	case max = "max"
	case randomItem = "randomItem"
	case countAll = "countAll"
	case pack = "pack"
	case exp = "exp"
	case ln = "ln"
	case round = "round"
	case choose = "choose"
	case randomBetween = "randomBetween"
	case random = "random"
	case regexSubstitute = "regexSubstitute"
	case normalInverse = "normalInverse"
	case sign = "sign"
	case split = "split"
	case nth = "nth"
	case items = "items"
	case levenshtein = "levenshtein"
	case urlEncode = "urlencode"
	case `in` = "in"
	case notIn = "notIn"
	case capitalize = "capitalize"
	case now = "now"
	case fromUnixTime = "fromUnix"
	case toUnixTime = "toUnix"
	case fromISO8601 = "fromISO8601"
	case toLocalISO8601 = "toLocalISO8601"
	case toUTCISO8601 = "toUTCISO8601"
	case fromExcelDate = "fromExcelDate"
	case toExcelDate = "toExcelDate"
	case utcDate = "date"
	case utcDay = "day"
	case utcMonth = "month"
	case utcYear = "year"
	case utcMinute = "minute"
	case utcHour = "hour"
	case utcSecond = "second"
	case duration = "duration"
	case after = "after"
	case ceiling = "ceiling"
	case floor = "floor"
	case randomString = "randomString"
	case fromUnicodeDateString = "fromUnicodeDateString"
	case toUnicodeDateString = "toUnicodeDateString"
	case power = "power"
	case uuid = "uuid"
	case countDistinct = "countDistinct"
	case medianLow = "medianLow"
	case medianHigh = "medianHigh"
	case median = "median"
	case medianPack = "medianPack"
	case variancePopulation = "variancePopulation"
	case varianceSample = "varianceSample"
	case standardDeviationPopulation = "stdevPopulation"
	case standardDeviationSample = "stdevSample"
	case isEmpty = "isEmpty"
	case isInvalid = "isInvalid"
	case jsonDecode = "jsonArrayToPack"
	case parseNumber = "parseNumber"
	case valueForKey = "valueForKey"
	case hilbertXYToD = "hilbertXYtoD"
	case hilbertDToX = "hilbertDtoX"
	case hilbertDToY = "hilbertDtoY"
	case powerDown = "powerDown"
	case powerUp = "powerUp"
	case base64Encode = "base64Encode"
	case base64Decode = "base64Decode"
	case hexEncode = "hexEncode"
	case hexDecode = "hexDecode"
	case numberOfBytes = "numberOfBytes"
	case encodeString = "encodeString"
	case decodeString = "decodeString"


	/** This function optimizes an expression that is an application of this function to the indicates arguments to a
	more efficient or succint expression. Note that other optimizations are applied elsewhere as well (e.g. if a function
	is deterministic and all arguments are constants, it is automatically replaced with a literal expression containing
	its constant result). */
	func prepare(_ args: [Expression]) -> Expression {
		if self.isIdentityWithSingleArgument && args.count == 1 && self.arity.valid(1) {
			return args.first!
		}

		var prepared = args.map({$0.prepare()})
		
		switch self {
		case .not:
			if args.count == 1 {
				// NOT(a=b) should be replaced with simply a!=b
				if let a = args[0] as? Comparison, a.type == Binary.equal {
					return Comparison(first: a.first, second: a.second, type: Binary.notEqual).prepare()
				}
					// Not(In(..)) should be written as NotIn(..)
				else if let a = args[0] as? Call, a.type == Function.`in` {
					return Call(arguments: a.arguments, type: Function.notIn).prepare()
				}
					// Not(Not(..)) cancels out
				else if let a = args[0] as? Call, a.type == Function.not && a.arguments.count == 1 {
					return a.arguments[0].prepare()
				}
			}

		case .and:
			// Insert arguments that are Ands themselves in this and
			prepared = prepared.mapMany {(item) -> [Expression] in
				if let a = item as? Call, a.type == Function.and {
					return a.arguments
				}
				else {
					return [item]
				}
			}

			// If at least one of the arguments to an AND is a constant false, then this And always evaluates to false
			for p in prepared {
				if p.isConstant && p.apply(Row(), foreign: nil, inputValue: nil) == Value.bool(false) {
					return Literal(Value.bool(false))
				}
			}

		case .or:
			// Insert arguments that are Ors themselves in this or
			prepared = prepared.mapMany({
				if let a = $0 as? Call, a.type == Function.or {
					return a.arguments
				}
				return [$0]
			})

			// If at least one of the arguments to an OR is a constant true, this OR always evaluates to true
			for p in prepared {
				if p.isConstant && p.apply(Row(), foreign: nil, inputValue: nil) == Value.bool(true) {
					return Literal(Value.bool(true))
				}
			}

			// If this OR consists of (x = y) pairs where x is the same column (or foreign, this can be translated to an IN(x, y1, y2, ..)
			var columnExpression: ColumnReferencingExpression? = nil
			var valueExpressions: [Expression] = []
			var binaryType: Binary? = nil
			let allowedBinaryTypes = [Binary.equal]

			for p in prepared {
				if let binary = p as? Comparison, allowedBinaryTypes.contains(binary.type) && (binaryType == nil || binaryType == binary.type) {
					binaryType = binary.type

					// See if one of the sides of this binary expression is a column reference
					let column: ColumnReferencingExpression?
					let value: Expression?
					if binary.first is ColumnReferencingExpression {
						column = binary.first as? ColumnReferencingExpression
						value = binary.second
					}
					else if binary.second is ColumnReferencingExpression {
						column = binary.second as? ColumnReferencingExpression
						value = binary.first
					}
					else {
						column = nil
						value = nil
					}

					if let c = column, let v = value {
						// is this column referencing expression the same
						valueExpressions.append(v)
						if let ce = columnExpression {
							let sameType = (c is Sibling && columnExpression is Sibling) ||
								(c is Foreign && columnExpression is Foreign)
							if sameType && c.column != ce.column {
								columnExpression = nil
								break;
							}
						}
						else {
							columnExpression = c
						}
					}
					else {
						// Some other constant, break for now
						// TODO: create an OR(IN(); other stuff) expression
						columnExpression = nil
						break
					}
				}
				else {
					columnExpression = nil
					break
				}
			}

			if let ce = columnExpression as? Expression, let bt = binaryType, valueExpressions.count > 1 {
				valueExpressions.insert(ce, at: 0)

				switch bt {
				case .equal:
					return Call(arguments: valueExpressions, type: Function.`in`)

				case .notEqual:
					return Call(arguments: valueExpressions, type: Function.notIn)

				default:
					fatalError("Cannot produce an IN()-like expression for this binary type")
				}
			}
		default:
			break
		}

		// Single-argument functions for which double execution makes no sense (e.g. lowercase(lowercase(x)) === lowercase(x))
		// TODO: other functions that cancel out, e.g. lowercase(uppercase(x))
		if self.isIdempotent && prepared.count == 1 {
			if let v = prepared[0] as? Call, v.type == self {
				return prepared[0]
			}
		}

		return Call(arguments: prepared, type: self)
	}

	public var localizedName: String {
		switch self {
		// TODO: make tihs more detailed. E.g., "5 leftmost characters of" instead of just "leftmost characters"
		case .uppercase: return translationForString("uppercase")
		case .lowercase: return translationForString("lowercase")
		case .negate: return translationForString("-")
		case .absolute: return translationForString("absolute")
		case .identity: return translationForString("the")
		case .and: return translationForString("and")
		case .or: return translationForString("or")
		case .`if`: return translationForString("if")
		case .concat: return translationForString("concatenate")
		case .cos: return translationForString("cose")
		case .sin: return translationForString("sine")
		case .tan: return translationForString("tangens")
		case .cosh: return translationForString("cosine hyperbolic")
		case .sinh: return translationForString("sine hyperbolic")
		case .tanh: return translationForString("tangens hyperbolic")
		case .acos: return translationForString("arc cosine")
		case .asin: return translationForString("arc sine")
		case .atan: return translationForString("arc tangens")
		case .sqrt: return translationForString("square root")
		case .left: return translationForString("leftmost characters")
		case .right: return translationForString("rightmost characters")
		case .length: return translationForString("length of text")
		case .mid: return translationForString("substring")
		case .log: return translationForString("logarithm")
		case .not: return translationForString("not")
		case .substitute: return translationForString("substitute")
		case .xor: return translationForString("xor")
		case .trim: return translationForString("trim spaces")
		case .coalesce: return translationForString("first non-empty value")
		case .ifError: return translationForString("if error")
		case .count: return translationForString("number of numeric values")
		case .sum: return translationForString("sum")
		case .average: return translationForString("average")
		case .min: return translationForString("lowest")
		case .max: return translationForString("highest")
		case .randomItem: return translationForString("random item")
		case .countAll: return translationForString("number of items")
		case .pack: return translationForString("pack")
		case .exp: return translationForString("e^")
		case .ln: return translationForString("natural logarithm")
		case .round: return translationForString("round")
		case .choose: return translationForString("choose")
		case .randomBetween: return translationForString("random number between")
		case .random: return translationForString("random number between 0 and 1")
		case .regexSubstitute: return translationForString("replace using pattern")
		case .normalInverse: return translationForString("inverse normal")
		case .sign: return translationForString("sign")
		case .split: return translationForString("split")
		case .nth: return translationForString("nth item")
		case .valueForKey: return translationForString("value for")
		case .items: return translationForString("number of items")
		case .levenshtein: return translationForString("text similarity")
		case .urlEncode: return translationForString("url encode")
		case .`in`: return translationForString("contains")
		case .notIn: return translationForString("does not contain")
		case .capitalize: return translationForString("capitalize")
		case .now: return translationForString("current time")
		case .fromUnixTime: return translationForString("interpret UNIX timestamp")
		case .toUnixTime: return translationForString("to UNIX timestamp")
		case .fromISO8601: return translationForString("interpret ISO-8601 formatted date")
		case .toLocalISO8601: return translationForString("to ISO-8601 formatted date in local timezone")
		case .toUTCISO8601: return translationForString("to ISO-8601 formatted date in UTC")
		case .toExcelDate: return translationForString("to Excel timestamp")
		case .fromExcelDate: return translationForString("from Excel timestamp")
		case .utcDate: return translationForString("make a date (in UTC)")
		case .utcDay: return translationForString("day in month (in UTC) of date")
		case .utcMonth: return translationForString("month (in UTC) of")
		case .utcYear: return translationForString("year (in UTC) of date")
		case .utcMinute: return translationForString("minute (in UTC) of time")
		case .utcHour: return translationForString("hour (in UTC) of time")
		case .utcSecond: return translationForString("seconds (in UTC) of time")
		case .duration: return translationForString("number of seconds that passed between dates")
		case .after: return translationForString("date after a number of seconds has passed after date")
		case .floor: return translationForString("round down to integer")
		case .ceiling: return translationForString("round up to integer")
		case .randomString: return translationForString("random string with pattern")
		case .toUnicodeDateString: return translationForString("write date in format")
		case .fromUnicodeDateString: return translationForString("read date in format")
		case .power: return translationForString("to the power")
		case .uuid: return translationForString("generate UUID")
		case .countDistinct: return translationForString("number of unique items")
		case .medianLow: return translationForString("median value (lowest in case of a draw)")
		case .medianHigh: return translationForString("median value (highest in case of a draw)")
		case .median: return translationForString("median value (average in case of a draw)")
		case .medianPack: return translationForString("median value (pack in case of a draw)")
		case .variancePopulation: return translationForString("variance (of population)")
		case .varianceSample: return translationForString("variance (of sample)")
		case .standardDeviationPopulation: return translationForString("standard deviation (of population)")
		case .standardDeviationSample: return translationForString("standard deviation (of sample)")
		case .isInvalid: return translationForString("is invalid")
		case .isEmpty: return translationForString("is empty")
		case .jsonDecode: return translationForString("read JSON value")
		case .parseNumber: return translationForString("read number")
		case .hilbertXYToD: return translationForString("to Hilbert index")
		case .hilbertDToX: return translationForString("Hilbert index to X")
		case .hilbertDToY: return translationForString("Hilbert index to Y")
		case .powerUp: return translationForString("to upper power of")
		case .powerDown: return translationForString("to lower power of")
		case .base64Decode: return translationForString("decode base64")
		case .base64Encode: return translationForString("encode base64")
		case .hexDecode: return translationForString("decode hex")
		case .hexEncode: return translationForString("encode hex")
		case .encodeString: return translationForString("encode text")
		case .decodeString: return translationForString("decode text")
		case .numberOfBytes: return translationForString("number of bytes")
		}
	}

	/** Return a localized explanation of what this function does. */
	public func explain(_ locale: Language, arguments: [Expression]) -> String {
		let explainedArguments = arguments.map({$0.explain(locale, topLevel: false)})

		switch self {
		case .nth where explainedArguments.count == 2:
			return String(format: translationForString("%@th item in %@"), explainedArguments[1], explainedArguments[0])

		case .valueForKey where explainedArguments.count == 2:
			return String(format: translationForString("%@ of %@"), explainedArguments[1], explainedArguments[0])

		default:
			break
		}

		let argumentsList = explainedArguments.joined(separator: ", ")
		return "\(self.localizedName)(\(argumentsList))"
	}

	/** Returns true if this function is guaranteed to return the same result when called multiple times in succession
	with the exact same set of arguments, between different evaluations of the bigger expression it is part of, as well 
	as within a single expression (e.g. NOW() is not deterministic because it will return different values between
	excutions of the expression as a whole, whereas RANDOM() is non-deterministic because its value may even differ within
	a single executions). As a rule, functions that depend on/return randomness or the current date/time are not
	deterministic. */
	public var isDeterministic: Bool {
		switch self {
		case .randomItem: return false
		case .randomBetween: return false
		case .random: return false
		case .randomString: return false
		case .now: return false
		case .uuid: return false
		default: return true
		}
	}

	func toFormula(_ locale: Language, arguments: [Expression]) -> String {
		let name = locale.nameForFunction(self) ?? ""

		switch self {
		case .nth where arguments.count == 2:
			let args = arguments.map({$0.toFormula(locale)})
			return "\(args[0])[\(args[1])]"

		case .valueForKey where arguments.count == 2:
			let args = arguments.map({$0.toFormula(locale)})
			return "\(args[0])->\(args[1])"

		default:
			let args = arguments.map({$0.toFormula(locale)}).joined(separator: locale.argumentSeparator)
			return "\(name)(\(args))"
		}
	}

	/** Whether applying this function again on the result of applying it to a value is equivalent to applying it a single
	time, i.e. f(f(x)) === f(x). */
	public var isIdempotent: Bool {
		switch self {
		case .uppercase, .lowercase, .trim, .absolute, .capitalize, .floor, .ceiling:
			return true
		default:
			return false
		}
	}
	
	/** Returns information about the parameters a function can receive.  */
	public var parameters: [Parameter]? { get {
		switch self {
		case .uppercase: return [Parameter(name: translationForString("text"), exampleValue: Value("foo"))]
		case .lowercase: return [Parameter(name: translationForString("text"), exampleValue: Value("FOO"))]
		
		case .left, .right:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("john doe")),
				Parameter(name: translationForString("index"), exampleValue: Value.int(3))
			]
			
		case .mid:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("john doe")),
				Parameter(name: translationForString("index"), exampleValue: Value.int(5)),
				Parameter(name: translationForString("length"), exampleValue: Value.int(3))
			]
			
		case .not:
			return [Parameter(name: translationForString("boolean"), exampleValue: Value.bool(false))]
			
		case .and, .or, .xor:
			return [
				Parameter(name: translationForString("boolean"), exampleValue: Value.bool(false)),
				Parameter(name: translationForString("boolean"), exampleValue: Value.bool(true))
			]
			
		case .`if`:
			return [
				Parameter(name: translationForString("boolean"), exampleValue: Value.bool(false)),
				Parameter(name: translationForString("value if true"), exampleValue: Value(translationForString("yes"))),
				Parameter(name: translationForString("value if false"), exampleValue: Value(translationForString("no")))
			]
			
		case .ifError:
			return [
				Parameter(name: translationForString("value"), exampleValue: Value(1346)),
				Parameter(name: translationForString("value if error"), exampleValue: Value(translationForString("(error)")))
			]
		
		case .duration:
			return [
				Parameter(name: translationForString("start date"), exampleValue: Value(Date(timeIntervalSinceReferenceDate: 0.0))),
				Parameter(name: translationForString("end date"), exampleValue: Value(Date()))
			]
			
		case .after:
			return [
				Parameter(name: translationForString("start date"), exampleValue: Value(Date())),
				Parameter(name: translationForString("seconds"), exampleValue: Value(3600.0))
			]
			
		case .capitalize, .length:
			return [Parameter(name: translationForString("text"), exampleValue: Value("john doe"))]
			
		case .urlEncode:
			return [Parameter(name: translationForString("text"), exampleValue: Value("warp [core]"))]
			
		case .trim:
			return [Parameter(name: translationForString("text"), exampleValue: Value(" warp core "))]
			
		case .split:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("1337AB#12#C")),
				Parameter(name: translationForString("separator"), exampleValue: Value("#"))
			]
			
		case .substitute:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("warpcore")),
				Parameter(name: translationForString("find"), exampleValue: Value("warp")),
				Parameter(name: translationForString("replacement"), exampleValue: Value("transwarp"))
			]
			
		case .regexSubstitute:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("1337AB")),
				Parameter(name: translationForString("find"), exampleValue: Value("[0-9]+")),
				Parameter(name: translationForString("replacement"), exampleValue: Value("#"))
			]
			
		case .utcDay, .utcYear, .utcMonth, .utcHour, .utcMinute, .utcSecond:
			return [Parameter(name: translationForString("date"), exampleValue: Value(Date()))]
			
		case .fromUnixTime:
			return [Parameter(name: translationForString("UNIX timestamp"), exampleValue: Value.double(Date().timeIntervalSince1970))]
			
		case .fromISO8601:
			return [Parameter(name: translationForString("UNIX timestamp"), exampleValue: Value.string(Date().iso8601FormattedLocalDate))]
		
		case .fromExcelDate:
			return [Parameter(name: translationForString("Excel timestamp"), exampleValue: Value.double(Date().excelDate ?? 0))]
			
		case .toUnixTime, .toUTCISO8601, .toLocalISO8601, .toExcelDate:
			return [Parameter(name: translationForString("date"), exampleValue: Value(Date()))]
			
		case .levenshtein:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("warp")),
				Parameter(name: translationForString("text"), exampleValue: Value("warpcore"))
			]
			
		case .normalInverse:
			return [
				Parameter(name: translationForString("p"), exampleValue: Value(0.5)),
				Parameter(name: translationForString("mu"), exampleValue: Value(10)),
				Parameter(name: translationForString("sigma"), exampleValue: Value(1))
			]
		
		case .utcDate:
			return [
				Parameter(name: translationForString("year"), exampleValue: Value.int(1988)),
				Parameter(name: translationForString("month"), exampleValue: Value.int(8)),
				Parameter(name: translationForString("day"), exampleValue: Value.int(11))
			]
			
		case .randomBetween:
			return [
				Parameter(name: translationForString("lower bound"), exampleValue: Value.int(0)),
				Parameter(name: translationForString("upper bound"), exampleValue: Value.int(100))
			]
		
		case .round:
			return [
				Parameter(name: translationForString("number"), exampleValue: Value(3.1337)),
				Parameter(name: translationForString("decimals"), exampleValue: Value(2))
			]
			
		case .ceiling, .floor:
			return [
				Parameter(name: translationForString("number"), exampleValue: Value(3.1337))
			]
		
		case .sin, .cos, .tan, .sinh, .cosh, .tanh, .exp, .ln, .log, .acos, .asin, .atan:
			return [Parameter(name: translationForString("number"), exampleValue: Value(M_PI_4))]
			
		case .sqrt:
			return [Parameter(name: translationForString("number"), exampleValue: Value(144))]
			
		case .sign, .absolute, .negate:
			return [Parameter(name: translationForString("number"), exampleValue: Value(-1337))]
			
		case .sum, .count, .countAll, .average, .min, .max, .randomItem, .countDistinct, .median, .medianHigh,
			.medianLow, .medianPack, .standardDeviationSample, .standardDeviationPopulation, .variancePopulation, .varianceSample:
			return [
				Parameter(name: translationForString("value"), exampleValue: Value(1)),
				Parameter(name: translationForString("value"), exampleValue: Value(2)),
				Parameter(name: translationForString("value"), exampleValue: Value(3)),
				Parameter(name: translationForString("value"), exampleValue: Value(3))
			]
			
		case .pack:
			return [
				Parameter(name: translationForString("value"), exampleValue: Value("horse")),
				Parameter(name: translationForString("value"), exampleValue: Value("correct")),
				Parameter(name: translationForString("value"), exampleValue: Value("battery")),
				Parameter(name: translationForString("value"), exampleValue: Value("staple"))
			]
			
		case .choose:
			return [
				Parameter(name: translationForString("index"), exampleValue: Value.int(2)),
				Parameter(name: translationForString("value"), exampleValue: Value("horse")),
				Parameter(name: translationForString("value"), exampleValue: Value("correct")),
				Parameter(name: translationForString("value"), exampleValue: Value("battery")),
				Parameter(name: translationForString("value"), exampleValue: Value("staple"))
			]
			
		case .`in`, .notIn:
			return [
				Parameter(name: translationForString("value"), exampleValue: Value("horse")),
				Parameter(name: translationForString("value"), exampleValue: Value("correct")),
				Parameter(name: translationForString("value"), exampleValue: Value("battery")),
				Parameter(name: translationForString("value"), exampleValue: Value("horse")),
				Parameter(name: translationForString("value"), exampleValue: Value("staple"))
			]
			
		case .nth:
			return [
				Parameter(name: translationForString("pack"), exampleValue: Value(WarpCore.Pack(["correct","horse", "battery", "staple"]).stringValue)),
				Parameter(name: translationForString("index"), exampleValue: Value.int(2))
			]

		case .valueForKey:
			return [
				Parameter(name: translationForString("pack"), exampleValue: Value(WarpCore.Pack(["firstName","John", "lastName", "Doe"]).stringValue)),
				Parameter(name: translationForString("index"), exampleValue: Value.string("lastName"))
			]
			
		case .items:
			return [
				Parameter(name: translationForString("pack"), exampleValue: Value(WarpCore.Pack(["correct","horse", "battery", "staple"]).stringValue))
			]
			
		case .concat:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("foo")),
				Parameter(name: translationForString("text"), exampleValue: Value("bar"))
			]
			
		case .now, .random:
			return []
			
		case .identity:
			return [Parameter(name: translationForString("value"), exampleValue: Value("horse"))]
			
		case .coalesce:
			return [
				Parameter(name: translationForString("value"), exampleValue: Value.invalid),
				Parameter(name: translationForString("value"), exampleValue: Value("horse"))
			]
			
		case .randomString:
			return [Parameter(name: translationForString("pattern"), exampleValue: Value("[0-9]{4}[A-Z]{2}"))]
			
		case .fromUnicodeDateString:
			return [Parameter(name: translationForString("text"), exampleValue: Value("1988-08-11")), Parameter(name: translationForString("format"), exampleValue: Value("yyyy-MM-dd"))]
			
		case .toUnicodeDateString:
			return [Parameter(name: translationForString("date"), exampleValue: Value(Date())), Parameter(name: translationForString("format"), exampleValue: Value("yyyy-MM-dd"))]
			
		case .power:
			return [
				Parameter(name: translationForString("base"), exampleValue: Value.int(2)),
				Parameter(name: translationForString("exponent"), exampleValue: Value.int(32))
			]

		case .uuid:
			return []

		case .isInvalid:
			return [Parameter(name: translationForString("value"), exampleValue: Value.int(3))]

		case .isEmpty:
			return [Parameter(name: translationForString("value"), exampleValue: Value.int(3))]

		case .jsonDecode:
			return [Parameter(name: translationForString("JSON"), exampleValue: Value.string("[1,2,3]"))]

		case .parseNumber:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value.string("1.337,12")),
				Parameter(name: translationForString("decimal separator"), exampleValue: Value.string(",")),
				Parameter(name: translationForString("thousands separator"), exampleValue: Value.string("."))
			]

		case .hilbertXYToD:
			return [
				Parameter(name: translationForString("n"), exampleValue: Value.int(1024)),
				Parameter(name: translationForString("x"), exampleValue: Value.int(100)),
				Parameter(name: translationForString("y"), exampleValue: Value.int(50))
			]

		case .hilbertDToX:
			return [
				Parameter(name: translationForString("n"), exampleValue: Value.int(1024)),
				Parameter(name: translationForString("d"), exampleValue: Value.int(100))
			]

		case .hilbertDToY:
			return [
				Parameter(name: translationForString("n"), exampleValue: Value.int(1024)),
				Parameter(name: translationForString("d"), exampleValue: Value.int(100))
			]

		case .powerUp:
			return [
				Parameter(name: translationForString("n"), exampleValue: Value.int(510)),
				Parameter(name: translationForString("base"), exampleValue: Value.int(2))
			]

		case .powerDown:
			return [
				Parameter(name: translationForString("n"), exampleValue: Value.int(510)),
				Parameter(name: translationForString("base"), exampleValue: Value.int(2))
			]

		case .base64Decode:
			return [
				Parameter(name: "data", exampleValue: Value.string("SGVsbG8gd29ybGQh"))
			]

		case .base64Encode:
			let d = "SGVsbG8gd29ybGQh".data(using: .utf8)
			return [
				Parameter(name: "data", exampleValue: Value.blob(d!))
			]

		case .hexDecode:
			return [
				Parameter(name: "data", exampleValue: Value.string("SGVsbG8gd29ybGQh"))
			]

		case .hexEncode:
			let d = "SGVsbG8gd29ybGQh".data(using: .utf8)
			return [
				Parameter(name: "data", exampleValue: Value.blob(d!))
			]

		case .encodeString:
			return [
				Parameter(name: "text", exampleValue: Value.string("Hello world!")),
				Parameter(name: "encoding", exampleValue: Value.string("UTF-16"))
			]

		case .decodeString:
			let d = "Hello world!".data(using: .utf16)
			return [
				Parameter(name: "data", exampleValue: Value.blob(d!)),
				Parameter(name: "encoding", exampleValue: Value.string("UTF-16"))
			]

		case .numberOfBytes:
			let d = "Hello world!".data(using: .utf16)
			return [
				Parameter(name: "data", exampleValue: Value.blob(d!)),
			]
		}
	} }
	
	public var arity: Arity {
		switch self {
		case .uppercase: return Arity.fixed(1)
		case .lowercase: return Arity.fixed(1)
		case .negate: return Arity.fixed(1)
		case .absolute: return Arity.fixed(1)
		case .identity: return Arity.fixed(1)
		case .and: return Arity.any
		case .or: return Arity.any
		case .cos: return Arity.fixed(1)
		case .sin: return Arity.fixed(1)
		case .tan: return Arity.fixed(1)
		case .cosh: return Arity.fixed(1)
		case .sinh: return Arity.fixed(1)
		case .tanh: return Arity.fixed(1)
		case .acos: return Arity.fixed(1)
		case .asin: return Arity.fixed(1)
		case .atan: return Arity.fixed(1)
		case .sqrt: return Arity.fixed(1)
		case .`if`: return Arity.fixed(3)
		case .concat: return Arity.any
		case .left: return Arity.fixed(2)
		case .right: return Arity.fixed(2)
		case .length: return Arity.fixed(1)
		case .mid: return Arity.fixed(3)
		case .log: return Arity.between(1,2)
		case .not: return Arity.fixed(1)
		case .substitute: return Arity.fixed(3)
		case .xor: return Arity.fixed(2)
		case .trim: return Arity.fixed(1)
		case .coalesce: return Arity.any
		case .ifError: return Arity.fixed(2)
		case .count: return Arity.any
		case .sum: return Arity.any
		case .average: return Arity.any
		case .max: return Arity.any
		case .min: return Arity.any
		case .randomItem: return Arity.any
		case .countAll: return Arity.any
		case .pack: return Arity.any
		case .exp: return Arity.fixed(1)
		case .ln: return Arity.fixed(1)
		case .round: return Arity.between(1,2)
		case .choose: return Arity.any
		case .randomBetween: return Arity.fixed(2)
		case .random: return Arity.fixed(0)
		case .regexSubstitute: return Arity.fixed(3)
		case .normalInverse: return Arity.fixed(3)
		case .sign: return Arity.fixed(1)
		case .split: return Arity.fixed(2)
		case .nth: return Arity.fixed(2)
		case .valueForKey: return Arity.fixed(2)
		case .items: return Arity.fixed(1)
		case .levenshtein: return Arity.fixed(2)
		case .urlEncode: return Arity.fixed(1)
		case .`in`: return Arity.atLeast(2)
		case .notIn: return Arity.atLeast(2)
		case .capitalize: return Arity.fixed(1)
		case .now: return Arity.fixed(0)
		case .fromUnixTime: return Arity.fixed(1)
		case .toUnixTime: return Arity.fixed(1)
		case .fromISO8601: return Arity.fixed(1)
		case .toLocalISO8601: return Arity.fixed(1)
		case .toUTCISO8601: return Arity.fixed(1)
		case .toExcelDate: return Arity.fixed(1)
		case .fromExcelDate: return Arity.fixed(1)
		case .utcDate: return Arity.fixed(3)
		case .utcDay: return Arity.fixed(1)
		case .utcMonth: return Arity.fixed(1)
		case .utcYear: return Arity.fixed(1)
		case .utcMinute: return Arity.fixed(1)
		case .utcHour: return Arity.fixed(1)
		case .utcSecond: return Arity.fixed(1)
		case .duration: return Arity.fixed(2)
		case .after: return Arity.fixed(2)
		case .ceiling: return Arity.fixed(1)
		case .floor: return Arity.fixed(1)
		case .randomString: return Arity.fixed(1)
		case .toUnicodeDateString: return Arity.fixed(2)
		case .fromUnicodeDateString: return Arity.fixed(2)
		case .power: return Arity.fixed(2)
		case .uuid: return Arity.fixed(0)
		case .countDistinct: return Arity.any
		case .medianPack: return Arity.any
		case .medianHigh: return Arity.any
		case .medianLow: return Arity.any
		case .median: return Arity.any
		case .standardDeviationPopulation: return Arity.any
		case .standardDeviationSample: return Arity.any
		case .variancePopulation: return Arity.any
		case .varianceSample: return Arity.any
		case .isInvalid: return Arity.fixed(1)
		case .isEmpty: return Arity.fixed(1)
		case .jsonDecode: return Arity.fixed(1)
		case .parseNumber: return Arity.between(1, 3)
		case .hilbertXYToD: return Arity.fixed(3)
		case .hilbertDToX: return Arity.fixed(2)
		case .hilbertDToY: return Arity.fixed(2)
		case .powerDown: return Arity.fixed(2)
		case .powerUp: return Arity.fixed(2)
		case .base64Encode: return Arity.fixed(1)
		case .base64Decode: return Arity.fixed(1)
		case .hexEncode: return Arity.fixed(1)
		case .hexDecode: return Arity.fixed(1)
		case .encodeString: return Arity.fixed(2)
		case .decodeString: return Arity.fixed(2)
		case .numberOfBytes: return Arity.fixed(1)
		}
	}
	
	public func apply(_ arguments: [Value]) -> Value {
		// Check arity
		if !arity.valid(arguments.count) {
			return Value.invalid
		}
		
		switch self {
		case .negate:
			return -arguments[0]
			
		case .uppercase:
			if let s = arguments[0].stringValue {
				return Value(s.uppercased())
			}
			return Value.invalid
			
		case .lowercase:
			if let s = arguments[0].stringValue {
				return Value(s.lowercased())
			}
			return Value.invalid
			
		case .absolute:
			return arguments[0].absolute
			
		case .identity:
			return arguments[0]
			
		case .and:
			for a in arguments {
				if !a.isValid {
					return Value.invalid
				}
				
				if a != Value(true) {
					return Value(false)
				}
			}
			return Value(true)
			
		case .coalesce:
			for a in arguments {
				if a.isValid && !a.isEmpty {
					return a
				}
			}
			return Value.empty
			
		case .not:
			if let b = arguments[0].boolValue {
				return Value(!b)
			}
			return Value.invalid
		
		case .or:
			for a in arguments {
				if !a.isValid {
					return Value.invalid
				}
			}
			
			for a in arguments {
				if a == Value(true) {
					return Value(true)
				}
			}
			return Value(false)
			
		case .xor:
			if let a = arguments[0].boolValue {
				if let b = arguments[1].boolValue {
					return Value((a != b) && (a || b))
				}
			}
			return Value.invalid
			
		case .`if`:
			if let d = arguments[0].boolValue {
				return d ? arguments[1] : arguments[2]
			}
			return Value.invalid
			
		case .ifError:
			return (!arguments[0].isValid) ? arguments[1] : arguments[0]
			
		case .cos:
			if let d = arguments[0].doubleValue {
				return Value(Darwin.cos(d))
			}
			return Value.invalid
		
		case .ln:
			if let d = arguments[0].doubleValue {
				return Value(log10(d) / log10(Darwin.exp(1.0)))
			}
			return Value.invalid
			
		case .exp:
			if let d = arguments[0].doubleValue {
				return Value(Darwin.exp(d))
			}
			return Value.invalid
			
		case .log:
			if let d = arguments[0].doubleValue {
				if arguments.count == 2 {
					if let base = arguments[1].doubleValue {
						return Value(Darwin.log(d) / Darwin.log(base))
					}
					return Value.invalid
				}
				return Value(log10(d))
			}
			return Value.invalid
			
		case .sin:
			if let d = arguments[0].doubleValue {
				return Value(Darwin.sin(d))
			}
			return Value.invalid
			
		case .tan:
			if let d = arguments[0].doubleValue {
				return Value(Darwin.tan(d))
			}
			return Value.invalid
			
		case .cosh:
			if let d = arguments[0].doubleValue {
				return Value(Darwin.cosh(d))
			}
			return Value.invalid
			
		case .sinh:
			if let d = arguments[0].doubleValue {
				return Value(Darwin.sinh(d))
			}
			return Value.invalid
			
		case .tanh:
			if let d = arguments[0].doubleValue {
				return Value(Darwin.tanh(d))
			}
			return Value.invalid
			
		case .acos:
			if let d = arguments[0].doubleValue {
				return Value(Darwin.acos(d))
			}
			return Value.invalid
			
		case .asin:
			if let d = arguments[0].doubleValue {
				return Value(Darwin.asin(d))
			}
			return Value.invalid
			
		case .atan:
			if let d = arguments[0].doubleValue {
				return Value(Darwin.atan(d))
			}
			return Value.invalid
			
		case .sqrt:
			if let d = arguments[0].doubleValue {
				return Value(Darwin.sqrt(d))
			}
			return Value.invalid
			
		case .left:
			if let s = arguments[0].stringValue {
				if let idx = arguments[1].intValue {
					if s.characters.count >= idx {
						let index = s.characters.index(s.startIndex, offsetBy: idx)
						return Value(s.substring(to: index))
					}
				}
			}
			return Value.invalid
			
		case .right:
			if let s = arguments[0].stringValue {
				if let idx = arguments[1].intValue {
					if s.characters.count >= idx {
						let index = s.characters.index(s.endIndex, offsetBy: -idx)
						return Value(s.substring(from: index))
					}
				}
			}
			return Value.invalid
			
		case .mid:
			if let s = arguments[0].stringValue {
				if let start = arguments[1].intValue {
					if let length = arguments[2].intValue {
						let sourceLength = s.characters.count
						if sourceLength >= start {
							let index = s.characters.index(s.startIndex, offsetBy: start)
							let end = sourceLength >= (start+length) ? s.characters.index(index, offsetBy: length) : s.endIndex
							
							return Value(s.substring(with: index..<end))
						}
					}
				}
			}
			return Value.invalid
			
		case .length:
			if let s = arguments[0].stringValue {
				return Value(s.characters.count)
			}
			return Value.invalid
		
		case .substitute:
			if let source = arguments[0].stringValue {
				if let replace = arguments[1].stringValue {
					if let replaceWith = arguments[2].stringValue {
						// TODO: add case-insensitive and regex versions of this
						return Value(source.replacingOccurrences(of: replace, with: replaceWith))
					}
				}
			}
			return Value.invalid
		
		case .trim:
			if let s = arguments[0].stringValue {
				return Value(s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
			}
			return Value.invalid
			
		case .randomItem:
			if arguments.isEmpty {
				return Value.empty
			}
			else {
				let index = Int.random(0..<arguments.count)
				return arguments[index]
			}
			
			
		case .round:
			var decimals = 0
			if arguments.count == 2 {
				decimals = arguments[1].intValue ?? 0
			}
			
			if decimals < 0 {
				return Value.invalid
			}
			
			if let d = arguments[0].doubleValue {
				if decimals == 0 {
					return Value.int(Int(Darwin.round(d)))
				}
				else {
					let filler = pow(10.0, Double(decimals))
					return Value(Darwin.round(filler * d) / filler)
				}
			}
			
			return Value.invalid
			
		case .choose:
			if arguments.count < 2 {
				return Value.invalid
			}
			
			if let index = arguments[0].intValue {
				if index < arguments.count && index > 0 {
					return arguments[index]
				}
			}
			return Value.invalid
			
		case .randomBetween:
			if let bottom = arguments[0].intValue {
				if let top = arguments[1].intValue {
					if top <= bottom {
						return Value.invalid
					}
					
					return Value(Int.random(bottom, upper: top+1))
				}
			}
			return Value.invalid
			
		case .random:
			return Value(Double.random())
			
		case .regexSubstitute:
			// Note: by default, this is case-sensitive (like .Substitute)
			if	let source = arguments[0].stringValue,
				let pattern = arguments[1].stringValue,
				let replacement = arguments[2].stringValue,
				let result = source.replace(pattern, withTemplate: replacement, caseSensitive: true) {
					return Value.string(result)
			}
			return Value.invalid
			
		case .normalInverse:
			if	let p = arguments[0].doubleValue,
				let mu = arguments[1].doubleValue,
				let sigma = arguments[2].doubleValue {
				if p < 0.0 || p > 1.0 {
					return Value.invalid
				}
					
				let deviations = NormalDistribution().inverse(p)
				return Value.double(mu + sigma * deviations)
			}
			return Value.invalid
			
		case .sign:
			if let d = arguments[0].doubleValue {
				let sign = (d==0) ? 0 : (d>0 ? 1 : -1)
				return Value.int(sign)
			}
			return Value.invalid
			
			
		case .split:
			if let s = arguments[0].stringValue {
				let separator = (arguments.count > 1 ? arguments[1].stringValue : nil) ?? " "
				let splitted = s.components(separatedBy: separator)
				let pack = WarpCore.Pack(splitted)
				return Value.string(pack.stringValue)
			}
			return Value.invalid
			
			
		case .nth:
			if let pack = WarpCore.Pack(arguments[0]) {
				if let index = arguments[1].intValue {
					let adjustedIndex = index-1
					if adjustedIndex < pack.count && adjustedIndex >= 0 {
						return Value.string(pack[adjustedIndex])
					}
				}
			}
			return Value.invalid

		case .valueForKey:
			if let pack = WarpCore.Pack(arguments[0]) {
				if let index = arguments[1].stringValue, let value = pack[index] {
					return Value.string(value)
				}
			}
			return Value.invalid
			
		case .items:
			if let pack = WarpCore.Pack(arguments[0]) {
				return Value.int(pack.count)
			}
			return Value.invalid
			
		case .levenshtein:
			if let a = arguments[0].stringValue, let b = arguments[1].stringValue {
				return Value.int(a.levenshteinDistance(b))
			}
			return Value.invalid
			
		case .urlEncode:
			if let s = arguments[0].stringValue, let enc = s.urlEncoded {
				return Value(enc)
			}
			return Value.invalid
			
		case .`in`:
			if arguments.count < 2 {
				return Value.invalid
			}
			else {
				let needle = arguments[0]
				for hay in 1..<arguments.count {
					if needle == arguments[hay] {
						return Value(true)
					}
				}
				return Value(false)
			}
			
		case .notIn:
			if arguments.count < 2 {
				return Value.invalid
			}
			else {
				let needle = arguments[0]
				for hay in 1..<arguments.count {
					if needle == arguments[hay] {
						return Value(false)
					}
				}
				return Value(true)
			}
			
		case .capitalize:
			if let s = arguments[0].stringValue {
				return Value.string(s.capitalized)
			}
			return Value.invalid
			
		case .now:
			return Value(Date())
			
		case .fromUnixTime:
			if let s = arguments[0].doubleValue {
				return Value(Date(timeIntervalSince1970: s))
			}
			return Value.invalid
			
		case .toUnixTime:
			if let d = arguments[0].dateValue {
				return Value(d.timeIntervalSince1970)
			}
			return Value.invalid
			
		case .fromISO8601:
			if let s = arguments[0].stringValue, let d = Date.fromISO8601FormattedDate(s) {
				return Value(d)
			}
			return Value.invalid
			
		case .toLocalISO8601:
			if let d = arguments[0].dateValue {
				return Value(d.iso8601FormattedLocalDate)
			}
			return Value.invalid
			
		case .toUTCISO8601:
			if let d = arguments[0].dateValue {
				return Value(d.iso8601FormattedUTCDate)
			}
			return Value.invalid
			
		case .toExcelDate:
			if let d = arguments[0].dateValue, let e = d.excelDate {
				return Value(e)
			}
			return Value.invalid
			
		case .fromExcelDate:
			if let d = arguments[0].doubleValue, let x = Date.fromExcelDate(d) {
				return Value(x)
			}
			return Value.invalid
			
		case .utcDate:
			if let year = arguments[0].intValue, let month = arguments[1].intValue, let day = arguments[2].intValue {
				return Value(Date.startOfGregorianDateInUTC(year, month: month, day: day))
			}
			return Value.invalid
			
		case .utcDay:
			if let date = arguments[0].dateValue, let d = date.gregorianComponentsInUTC.day {
				return Value(d)
			}
			return Value.invalid

		case .utcMonth:
			if let date = arguments[0].dateValue, let m = date.gregorianComponentsInUTC.month {
				return Value(m)
			}
			return Value.invalid

		case .utcYear:
			if let date = arguments[0].dateValue, let y = date.gregorianComponentsInUTC.year {
				return Value(y)
			}
			return Value.invalid

		case .utcHour:
			if let date = arguments[0].dateValue, let h = date.gregorianComponentsInUTC.hour {
				return Value(h)
			}
			return Value.invalid

		case .utcMinute:
			if let date = arguments[0].dateValue, let m = date.gregorianComponentsInUTC.minute {
				return Value(m)
			}
			return Value.invalid

		case .utcSecond:
			if let date = arguments[0].dateValue, let s = date.gregorianComponentsInUTC.second {
				return Value(s)
			}
			return Value.invalid
			
		case .duration:
			if let start = arguments[0].dateValue, let end = arguments[1].dateValue {
				return Value(end.timeIntervalSinceReferenceDate - start.timeIntervalSinceReferenceDate)
			}
			return Value.invalid
			
		case .after:
			if let start = arguments[0].dateValue, let duration = arguments[1].doubleValue {
				return Value(Date(timeInterval: duration, since: start as Date))
			}
			return Value.invalid
			
		case .floor:
			if let d = arguments[0].doubleValue {
				return Value(Darwin.floor(d))
			}
			return Value.invalid
			
		case .ceiling:
			if let d = arguments[0].doubleValue {
				return Value(ceil(d))
			}
			return Value.invalid
			
		case .randomString:
			if let p = arguments[0].stringValue, let sequencer = Sequencer(p) {
				return sequencer.randomValue ?? Value.empty
			}
			return Value.invalid
			
		case .toUnicodeDateString:
			if let d = arguments[0].dateValue, let format = arguments[1].stringValue {
				let formatter = DateFormatter()
				formatter.dateFormat = format
				formatter.timeZone = TimeZone(abbreviation: "UTC")
				return Value.string(formatter.string(from: d as Date))
			}
			return Value.invalid
			
		case .fromUnicodeDateString:
			if let d = arguments[0].stringValue, let format = arguments[1].stringValue {
				let formatter = DateFormatter()
				formatter.dateFormat = format
				formatter.timeZone = TimeZone(abbreviation: "UTC")
				if let date = formatter.date(from: d) {
					return Value(date)
				}
			}
			return Value.invalid
			
		case .power:
			return arguments[0] ^ arguments[1]

		case .uuid:
			return .string(Foundation.UUID().uuidString)

		case .isInvalid:
			return Value.bool(!arguments[0].isValid)

		case .isEmpty:
			return Value.bool(arguments[0].isEmpty)

		case .jsonDecode:
			do {
				if let s = arguments[0].stringValue, let stringDataset = s.data(using: String.Encoding.utf8) {
					let jsonDecoded = try JSONSerialization.jsonObject(with: stringDataset, options: [.allowFragments])
					return Value(jsonObject: jsonDecoded as AnyObject)
				}
			}
			catch {
				return Value.invalid
			}
			return Value.invalid

		case .parseNumber:
			if let text = arguments[0].stringValue {
				let decimalSeparator = arguments.count >= 2 ? (arguments[1].stringValue ?? ".") : "."
				let thousandsSeparator = arguments.count == 3 ? (arguments[2].stringValue ?? ",") : ","

				let withoutThousands = text.replacingOccurrences(of: thousandsSeparator, with: "")
				let withPoint = withoutThousands.replacingOccurrences(of: decimalSeparator, with: ".")
				if let d = Value.string(withPoint).doubleValue {
					return Value.double(d)
				}
			}
			return Value.invalid

		case .hilbertXYToD:
			if let n = arguments[0].intValue, let x = arguments[1].intValue, let y = arguments[2].intValue {
				// N must be a power of two
				if n < 1 || n.powerUp(base: 2) != n || n.powerDown(base: 2) != n {
					return Value.invalid
				}

				if x >= n || y >= n {
					return Value.invalid
				}
				let h = Hilbert(size: n)
				if let d = h[x, y] {
					return Value.int(d)
				}
			}
			return Value.invalid

		case .hilbertDToX:
			if let n = arguments[0].intValue, let d = arguments[1].intValue {
				// N must be a power of two
				if n < 1 || n.powerUp(base: 2) != n || n.powerDown(base: 2) != n || d < 0 {
					return Value.invalid
				}

				let h = Hilbert(size: n)
				if let coord = h[d] {
					return Value.int(coord.x)
				}
			}
			return Value.invalid

		case .hilbertDToY:
			if let n = arguments[0].intValue, let d = arguments[1].intValue {
				// N must be a power of two
				if n < 1 || n.powerUp(base: 2) != n || n.powerDown(base: 2) != n || d < 0 {
					return Value.invalid
				}

				let h = Hilbert(size: n)
				if let coord = h[d] {
					return Value.int(coord.y)
				}
			}
			return Value.invalid

		case .powerUp:
			if let n = arguments[0].intValue, let base = arguments[1].intValue {
				if base <= 1 {
					return Value.invalid
				}

				if let d = n.powerUp(base: base) {
					return Value.int(d)
				}
			}
			return Value.invalid

		case .powerDown:
			if let n = arguments[0].intValue, let base = arguments[1].intValue {
				if base <= 1 || n < 1 {
					return Value.invalid
				}

				if let d = n.powerDown(base: base) {
					return Value.int(d)
				}
			}
			return Value.invalid

		case .base64Encode:
			if case .blob(let data) = arguments[0] {
				return Value.string(data.base64EncodedString())
			}
			return .invalid

		case .base64Decode:
			if let s = arguments[0].stringValue, let data = Data(base64Encoded: s) {
				return .blob(data)
			}
			return .invalid

		case .hexEncode:
			if case .blob(let data) = arguments[0] {
				return Value.string(data.map { String(format: "%02hhx", $0) }.joined())
			}
			return .invalid

		case .hexDecode:
			if let s = arguments[0].stringValue {
				let chars = Array(s.characters)
				let numbers = stride(from: 0, to: chars.count, by: 2).map() {
					UInt8(strtoul(String(chars[$0 ..< Swift.min($0 + 2, chars.count)]), nil, 16))
				}
				return .blob(Data(bytes: numbers))
			}
			return .invalid

		case .numberOfBytes:
			if case .blob(let data) = arguments[0] {
				return .int(data.count)
			}
			return .invalid

		case .encodeString:
			if let s = arguments[0].stringValue, let encoding = arguments[1].stringValue, let encType = Language.encodings[encoding], let data = s.data(using: encType) {
				return .blob(data)
			}
			return .invalid

		case .decodeString:
			if case .blob(let data) = arguments[0], let encoding = arguments[1].stringValue, let encType = Language.encodings[encoding], let s = String(data: data, encoding: encType) {
				return .string(s)
			}
			return .invalid


		// The following functions are already implemented as a Reducer, just use that
		case .sum, .min, .max, .count, .countAll, .average, .concat, .pack, .countDistinct, .median, .medianHigh,
			.medianLow, .medianPack, .varianceSample, .variancePopulation, .standardDeviationPopulation, .standardDeviationSample:
			var r = self.reducer!
			r.add(arguments)
			return r.result
		}
	}

	public var reducer: Reducer? {
		switch self {
		case .sum: return SumReducer()
		case .min: return MinReducer()
		case .max: return MaxReducer()
		case .countDistinct: return CountDistinctReducer()
		case .count: return CountReducer(all: false)
		case .countAll: return CountReducer(all: true)
		case .average: return AverageReducer()
		case .concat: return ConcatenationReducer()
		case .pack: return PackReducer()
		case .medianPack: return MedianReducer(medianType: .pack)
		case .medianHigh: return MedianReducer(medianType: .high)
		case .medianLow: return MedianReducer(medianType: .low)
		case .median: return MedianReducer(medianType: .average)
		case .variancePopulation: return VarianceReducer(varianceType: .population)
		case .varianceSample: return VarianceReducer(varianceType: .sample)
		case .standardDeviationPopulation: return StandardDeviationReducer(varianceType: .population)
		case .standardDeviationSample: return StandardDeviationReducer(varianceType: .sample)

		default:
			return nil
		}
	}

	/** True if the function - when called with just a single argument - would always return that single argument. */
	public var isIdentityWithSingleArgument: Bool {
		// Functions that require more than one argument are never identity for a single argument - they cannot even be called
		if !self.arity.valid(1) {
			return false
		}

		switch self {
		case .sum, .min, .max, .average, .concat, .pack, .median, .medianLow, .medianHigh, .and, .or, .randomItem: return true
		default: return false
		}
	}

	public static let allFunctions = [
		uppercase, lowercase, negate, absolute, and, or, acos, asin, atan, cosh, sinh, tanh, cos, sin, tan, sqrt, concat,
		`if`, left, right, mid, length, substitute, count, sum, trim, average, min, max, randomItem, countAll, pack, ifError,
		exp, log, ln, round, choose, random, randomBetween, regexSubstitute, normalInverse, sign, split, nth, items,
		levenshtein, urlEncode, `in`, notIn, not, capitalize, now, toUnixTime, fromUnixTime, fromISO8601, toLocalISO8601,
		toUTCISO8601, toExcelDate, fromExcelDate, utcDate, utcDay, utcMonth, utcYear, utcHour, utcMinute, utcSecond,
		duration, after, xor, floor, ceiling, randomString, toUnicodeDateString, fromUnicodeDateString, power, uuid,
		countDistinct, medianLow, medianHigh, medianPack, median, varianceSample, variancePopulation, standardDeviationSample,
		standardDeviationPopulation, isEmpty, isInvalid, jsonDecode, parseNumber, valueForKey, hilbertXYToD, hilbertDToX,
		hilbertDToY, powerDown, powerUp, base64Encode, base64Decode, encodeString, decodeString, hexEncode, hexDecode, numberOfBytes
	]
}

/** Represents a function that operates on two operands. Binary operators are treated differently from 'normal' functions
because they have a special place in formula syntax, and they have certain special properties (e.g. some can be 'mirrorred':
a>=b can be mirrorred to b<a). Otherwise, SUM(a;b) and a+b are equivalent. */
public enum Binary: String {
	case addition = "add"
	case subtraction = "sub"
	case multiplication = "mul"
	case division = "div"
	case modulus = "mod"
	case concatenation = "cat"
	case power = "pow"
	case greater = "gt"
	case lesser = "lt"
	case greaterEqual = "gte"
	case lesserEqual = "lte"
	case equal = "eq"
	case notEqual = "neq"
	case containsString = "contains" // case-insensitive
	case containsStringStrict = "containsStrict" // case-sensitive
	case matchesRegex = "matchesRegex" // not case-sensitive
	case matchesRegexStrict = "matchesRegexStrict" // case-sensitive

	public static let allBinaries = [addition, subtraction, multiplication, division, modulus, concatenation, power,
	                                 equal, notEqual, greater, lesser, greaterEqual, lesserEqual, containsString,
	                                 containsStringStrict, matchesRegex, matchesRegexStrict]

	/** Returns a human-readable, localized explanation of what this binary operator does. */
	public func explain(_ locale: Language) -> String {
		switch self {
		case .addition: return "+"
		case .subtraction: return "-"
		case .multiplication: return "*"
		case .division: return "/"
		case .modulus: return "%"
		case .concatenation: return "&"
		case .power: return "^"
		case .greater: return translationForString("is greater than")
		case .lesser: return translationForString("is less than")
		case .greaterEqual: return translationForString("is greater than or equal to")
		case .lesserEqual: return translationForString("is less than or equal to")
		case .equal: return translationForString("is equal to")
		case .notEqual: return translationForString("is not equal to")
		case .containsString: return translationForString("contains text")
		case .containsStringStrict: return translationForString("contains text (case-sensitive)")
		case .matchesRegex: return translationForString("matches pattern")
		case .matchesRegexStrict: return translationForString("matches pattern (case-sensitive)")
		}
	}
	
	public func toFormula(_ locale: Language) -> String {
		switch self {
		case .addition: return "+"
		case .subtraction: return "-"
		case .multiplication: return "*"
		case .division: return "/"
		case .modulus: return "%"
		case .concatenation: return "&"
		case .power: return "^"
		case .greater: return ">"
		case .lesser: return "<"
		case .greaterEqual: return ">="
		case .lesserEqual: return "<="
		case .equal: return "="
		case .notEqual: return "<>"
		case .containsString: return "~="
		case .containsStringStrict: return "~~="
		case .matchesRegex: return "±="
		case .matchesRegexStrict: return "±±="
		}
	}

	/** True if this operator accepts two arbitrary values and returns a boolean (at least for non-invalid values). */
	public var isComparative: Bool {
		switch self {
		case .greater, .lesser, .greaterEqual, .lesserEqual, .equal, .notEqual, .containsStringStrict, .containsString, .matchesRegex, .matchesRegexStrict:
			return true
		case .addition, .subtraction, .multiplication, .division, .modulus, .concatenation, .power:
			return false
		}
	}

	/** Returns whether this operator is guaranteed to return the same result when its operands are swapped. */
	public var isCommutative: Bool { get {
		switch self {
		case .equal, .notEqual, .addition, .multiplication: return true
		default: return false
		}
	} }
	
	/** The binary operator that is equivalent to this one given that the parameters are swapped (e.g. for a<b the mirror
	operator is '>=', since b>=a is equivalent to a<b). */
	var mirror: Binary? {
		// These operators don't care about what comes first or second at all
		if isCommutative {
			return self
		}
		
		switch self {
		case .greater: return .lesserEqual
		case .lesser: return .greaterEqual
		case .greaterEqual: return .lesser
		case .lesserEqual: return .greater
		default: return nil
		}
	}
	
	public func apply(_ left: Value, _ right: Value) -> Value {
		switch self {
		case .addition:
			return left + right
			
		case .subtraction:
			return left - right
			
		case .multiplication:
			return left * right
			
		case .modulus:
			return left % right
			
		case .division:
			return left / right
			
		case .concatenation:
			return left & right
			
		case .power:
			return left ^ right
			
		case .greater:
			return left > right
			
		case .lesser:
			return left < right
			
		case .greaterEqual:
			return left >= right
			
		case .lesserEqual:
			return left <= right
			
		case .equal:
			return left == right
			
		case .notEqual:
			return left != right
			
		case .containsString:
			return left ~= right
			
		case .containsStringStrict:
			return left ~~= right
			
		case .matchesRegex:
			return left ±= right
			
		case .matchesRegexStrict:
			return left ±±= right
		}
	}
}

/** Description of a function parameter. */
public struct Parameter {
	public let name: String
	public let exampleValue: Value
}

/** Arity represents the 'arity' of a function (the number of arguments a function requires or supports). The arity
of a function can either be 'fixed' (a function with an arity of '1' is called unary, a function with arity '2' is a
binary), constrained ('between x and y') or anything. Functions that can take any number of arguments can also be used
as aggregating functions (if they are adhere to the property that (e.g.) SUM(1;2;3;4) == SUM(SUM(1;2);SUM(3;4)). */
public enum Arity: Equatable {
	case fixed(Int)
	case atLeast(Int)
	case between(Int, Int)
	case any
	
	public func valid(_ count: Int) -> Bool {
		switch self {
		case .fixed(let i):
			return count == i
			
		case .atLeast(let i):
			return count >= i
			
		case .between(let a, let b):
			return count >= a && count <= b
			
		case .any:
			return true
		}
	}
	
	public var explanation: String {
		switch self {
		case .fixed(let i):
			return String(format: translationForString("exactly %d"), i)
			
		case .atLeast(let i):
			return String(format: translationForString("at least %d"), i)
			
		case .between(let a, let b):
			return String(format: translationForString("between %d and %d"), a, b)
			
		case .any:
			return String(format: translationForString("zero or more"))
		}
	}
}

public func ==(lhs: Arity, rhs: Arity) -> Bool {
	switch (lhs, rhs) {
	case (.any, .any):
		return true
	case (.fixed(let lf), .fixed(let rf)):
		return lf == rf
	default:
		return false
	}
}

private struct AverageReducer: Reducer {
	var total: Value = Value(0.0)
	var count: Int = 0

	mutating func add(_ values: [Value]) {
		values.forEach { v in
			// Ignore any invalid values
			if v.isValid {
				self.count += 1
				self.total  = self.total + v
			}
		}
	}

	var result: Value { return self.total / Value(self.count) }
}

private struct SumReducer: Reducer {
	var result: Value = Value(0.0)

	mutating func add(_ values: [Value]) {
		values.forEach { v in
			// Ignore any invalid values
			if v.isValid {
				self.result = self.result + v
			}
		}
	}
}

private struct MaxReducer: Reducer {
	var result: Value = Value.invalid

	mutating func add(_ values: [Value]) {
		for value in values {
			if !self.result.isValid || (value.isValid && value > self.result) {
				self.result = value
			}
		}
	}
}

private struct MinReducer: Reducer {
	var result: Value = Value.invalid

	mutating func add(_ values: [Value]) {
		for value in values {
			if !self.result.isValid || (value.isValid && value < self.result) {
				self.result = value
			}
		}
	}
}

private struct CountReducer: Reducer {
	private var count = 0
	private let all: Bool

	init(all: Bool) {
		self.all = all
	}

	mutating func add(_ values: [Value]) {
		if all {
			self.count += values.count
		}
		else {
			// Count only counts the number of numeric values
			values.forEach {
				if let _ = $0.doubleValue {
					self.count += 1
				}
			}
		}
	}

	var result: Value {
		return Value(self.count)
	}
}

private struct ConcatenationReducer: Reducer {
	var result: Value = Value("")

	mutating func add(_ values: [Value]) {
		for a in values {
			result = result & a
		}
	}
}

private struct PackReducer: Reducer {
	var pack = Pack()

	mutating func add(_ values: [Value]) {
		for a in values {
			pack.append(a)
		}
	}

	var result: Value {
		return Value(pack.stringValue)
	}
}

private struct CountDistinctReducer: Reducer {
	var valueSet = Set<Value>()

	mutating func add(_ values: [Value]) {
		for a in values {
			if a.isValid && !a.isEmpty {
				valueSet.insert(a)
			}
		}
	}

	var result: Value {
		return Value(valueSet.count)
	}
}

private enum MedianType {
	case low
	case high
	case average
	case pack
}

private struct MedianReducer: Reducer {
	let medianType: MedianType
	var values = [Value]()

	init(medianType: MedianType) {
		self.medianType = medianType
	}

	mutating func add(_ values: [Value]) {
		self.values += values.filter { return $0.isValid && !$0.isEmpty }
	}

	var result: Value {
		let sorted = values.sorted(by: { return $0 < $1 })
		let count = sorted.count

		if count == 0 {
			return Value.invalid
		}

		/* The code below is adapted from SigmaSwift (https://github.com/evgenyneu/SigmaSwiftStatistics) used under MIT license. */
		if count % 2 == 0 {
			let leftIndex = Int(count / 2 - 1)
			let leftValue = sorted[leftIndex]
			let rightValue = sorted[leftIndex + 1]

			switch medianType {
			case .average:
				// FIXME: this messes up string values, obviously.
				return (leftValue + rightValue) / Value(2.0)

			case .low:
				return leftValue

			case .high:
				return rightValue

			case .pack:
				return Value(Pack([leftValue, rightValue]).stringValue)
			}
		}
		else {
			// Odd number of items - take the middle item.
			return sorted[Int(count / 2)]
		}
	}
}

private enum VarianceType {
	case population
	case sample
}

private struct VarianceReducer: Reducer {
	let varianceType: VarianceType
	var values = [Double]()
	var invalid = false

	init(varianceType: VarianceType) {
		self.varianceType = varianceType
	}

	mutating func add(_ values: [Value]) {
		for v in values {
			if v.isValid && !v.isEmpty {
				if let d = v.doubleValue {
					self.values.append(d)
				}
				else {
					self.invalid = true
					self.values = []
					return
				}
			}
		}
	}

	var result: Value {
		if self.invalid {
			return Value.invalid
		}

		// An empty list of values does not have variance
		if self.values.count == 0 {
			return Value.invalid
		}

		// Sample variance is undefined for a list of values with only one value
		if self.varianceType == .sample && self.values.count == 1 {
			return Value.invalid
		}

		let sum = self.values.reduce(0.0) { t, v in t + v }
		let average = sum / Double(self.values.count)

		let numerator = self.values.reduce(0.0) { total, value in
			total + pow(average - value, 2.0)
		}

		switch self.varianceType {
		case .population: return Value.double(numerator / Double(self.values.count))
		case .sample: return Value.double(numerator / Double(self.values.count - 1))
		}
	}
}

private struct StandardDeviationReducer: Reducer {
	var varianceReducer: VarianceReducer

	init(varianceType: VarianceType) {
		self.varianceReducer = VarianceReducer(varianceType: varianceType)
	}

	mutating func add(_ values: [Value]) {
		self.varianceReducer.add(values)
	}

	var result: Value {
		let r = varianceReducer.result

		if let d = r.doubleValue {
			return Value.double(sqrt(d))
		}
		return Value.invalid
	}
}
