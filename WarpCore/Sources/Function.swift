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
	case Uppercase = "upper"
	case Lowercase = "lower"
	case Negate = "negate"
	case Identity = "identity"
	case Absolute = "abs"
	case And = "and"
	case Or = "or"
	case Xor = "xor"
	case If = "if"
	case Concat = "concat"
	case Cos = "cos"
	case Sin = "sin"
	case Tan = "tan"
	case Cosh = "cosh"
	case Sinh = "sinh"
	case Tanh = "tanh"
	case Acos = "acos"
	case Asin = "asin"
	case Atan = "atan"
	case Sqrt = "sqrt"
	case Left = "left"
	case Right = "right"
	case Mid = "mid"
	case Length = "length"
	case Log = "log"
	case Not = "not"
	case Substitute = "substitute"
	case Trim = "trim"
	case Coalesce = "coalesce"
	case IfError = "iferror"
	case Count = "count"
	case Sum = "sum"
	case Average = "average"
	case Min = "min"
	case Max = "max"
	case RandomItem = "randomItem"
	case CountAll = "countAll"
	case Pack = "pack"
	case Exp = "exp"
	case Ln = "ln"
	case Round = "round"
	case Choose = "choose"
	case RandomBetween = "randomBetween"
	case Random = "random"
	case RegexSubstitute = "regexSubstitute"
	case NormalInverse = "normalInverse"
	case Sign = "sign"
	case Split = "split"
	case Nth = "nth"
	case Items = "items"
	case Levenshtein = "levenshtein"
	case URLEncode = "urlencode"
	case In = "in"
	case NotIn = "notIn"
	case Capitalize = "capitalize"
	case Now = "now"
	case FromUnixTime = "fromUnix"
	case ToUnixTime = "toUnix"
	case FromISO8601 = "fromISO8601"
	case ToLocalISO8601 = "toLocalISO8601"
	case ToUTCISO8601 = "toUTCISO8601"
	case FromExcelDate = "fromExcelDate"
	case ToExcelDate = "toExcelDate"
	case UTCDate = "date"
	case UTCDay = "day"
	case UTCMonth = "month"
	case UTCYear = "year"
	case UTCMinute = "minute"
	case UTCHour = "hour"
	case UTCSecond = "second"
	case Duration = "duration"
	case After = "after"
	case Ceiling = "ceiling"
	case Floor = "floor"
	case RandomString = "randomString"
	case FromUnicodeDateString = "fromUnicodeDateString"
	case ToUnicodeDateString = "toUnicodeDateString"
	case Power = "power"
	case UUID = "uuid"
	case CountDistinct = "countDistinct"
	case MedianLow = "medianLow"
	case MedianHigh = "medianHigh"
	case Median = "median"
	case MedianPack = "medianPack"
	case VariancePopulation = "variancePopulation"
	case VarianceSample = "varianceSample"
	case StandardDeviationPopulation = "stdevPopulation"
	case StandardDeviationSample = "stdevSample"
	case IsEmpty = "isEmpty"
	case IsInvalid = "isInvalid"
	case JSONDecode = "jsonArrayToPack"
	case ParseNumber = "parseNumber"
	case ValueForKey = "valueForKey"
	case HilbertXYToD = "hilbertXYtoD"
	case HilbertDToX = "hilbertDtoX"
	case HilbertDToY = "hilbertDtoY"
	case PowerDown = "powerDown"
	case PowerUp = "powerUp"

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
		case .Not:
			if args.count == 1 {
				// NOT(a=b) should be replaced with simply a!=b
				if let a = args[0] as? Comparison, a.type == Binary.equal {
					return Comparison(first: a.first, second: a.second, type: Binary.notEqual).prepare()
				}
					// Not(In(..)) should be written as NotIn(..)
				else if let a = args[0] as? Call, a.type == Function.In {
					return Call(arguments: a.arguments, type: Function.NotIn).prepare()
				}
					// Not(Not(..)) cancels out
				else if let a = args[0] as? Call, a.type == Function.Not && a.arguments.count == 1 {
					return a.arguments[0].prepare()
				}
			}

		case .And:
			// Insert arguments that are Ands themselves in this and
			prepared = prepared.mapMany {(item) -> [Expression] in
				if let a = item as? Call, a.type == Function.And {
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

		case .Or:
			// Insert arguments that are Ors themselves in this or
			prepared = prepared.mapMany({
				if let a = $0 as? Call, a.type == Function.Or {
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
					return Call(arguments: valueExpressions, type: Function.In)

				case .notEqual:
					return Call(arguments: valueExpressions, type: Function.NotIn)

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
		case .Uppercase: return translationForString("uppercase")
		case .Lowercase: return translationForString("lowercase")
		case .Negate: return translationForString("-")
		case .Absolute: return translationForString("absolute")
		case .Identity: return translationForString("the")
		case .And: return translationForString("and")
		case .Or: return translationForString("or")
		case .If: return translationForString("if")
		case .Concat: return translationForString("concatenate")
		case .Cos: return translationForString("cose")
		case .Sin: return translationForString("sine")
		case .Tan: return translationForString("tangens")
		case .Cosh: return translationForString("cosine hyperbolic")
		case .Sinh: return translationForString("sine hyperbolic")
		case .Tanh: return translationForString("tangens hyperbolic")
		case .Acos: return translationForString("arc cosine")
		case .Asin: return translationForString("arc sine")
		case .Atan: return translationForString("arc tangens")
		case .Sqrt: return translationForString("square root")
		case .Left: return translationForString("leftmost characters")
		case .Right: return translationForString("rightmost characters")
		case .Length: return translationForString("length of text")
		case .Mid: return translationForString("substring")
		case .Log: return translationForString("logarithm")
		case .Not: return translationForString("not")
		case .Substitute: return translationForString("substitute")
		case .Xor: return translationForString("xor")
		case .Trim: return translationForString("trim spaces")
		case .Coalesce: return translationForString("first non-empty value")
		case .IfError: return translationForString("if error")
		case .Count: return translationForString("number of numeric values")
		case .Sum: return translationForString("sum")
		case .Average: return translationForString("average")
		case .Min: return translationForString("lowest")
		case .Max: return translationForString("highest")
		case .RandomItem: return translationForString("random item")
		case .CountAll: return translationForString("number of items")
		case .Pack: return translationForString("pack")
		case .Exp: return translationForString("e^")
		case .Ln: return translationForString("natural logarithm")
		case .Round: return translationForString("round")
		case .Choose: return translationForString("choose")
		case .RandomBetween: return translationForString("random number between")
		case .Random: return translationForString("random number between 0 and 1")
		case .RegexSubstitute: return translationForString("replace using pattern")
		case .NormalInverse: return translationForString("inverse normal")
		case .Sign: return translationForString("sign")
		case .Split: return translationForString("split")
		case .Nth: return translationForString("nth item")
		case .ValueForKey: return translationForString("value for")
		case .Items: return translationForString("number of items")
		case .Levenshtein: return translationForString("text similarity")
		case .URLEncode: return translationForString("url encode")
		case .In: return translationForString("contains")
		case .NotIn: return translationForString("does not contain")
		case .Capitalize: return translationForString("capitalize")
		case .Now: return translationForString("current time")
		case .FromUnixTime: return translationForString("interpret UNIX timestamp")
		case .ToUnixTime: return translationForString("to UNIX timestamp")
		case .FromISO8601: return translationForString("interpret ISO-8601 formatted date")
		case .ToLocalISO8601: return translationForString("to ISO-8601 formatted date in local timezone")
		case .ToUTCISO8601: return translationForString("to ISO-8601 formatted date in UTC")
		case .ToExcelDate: return translationForString("to Excel timestamp")
		case .FromExcelDate: return translationForString("from Excel timestamp")
		case .UTCDate: return translationForString("make a date (in UTC)")
		case .UTCDay: return translationForString("day in month (in UTC) of date")
		case .UTCMonth: return translationForString("month (in UTC) of")
		case .UTCYear: return translationForString("year (in UTC) of date")
		case .UTCMinute: return translationForString("minute (in UTC) of time")
		case .UTCHour: return translationForString("hour (in UTC) of time")
		case .UTCSecond: return translationForString("seconds (in UTC) of time")
		case .Duration: return translationForString("number of seconds that passed between dates")
		case .After: return translationForString("date after a number of seconds has passed after date")
		case .Floor: return translationForString("round down to integer")
		case .Ceiling: return translationForString("round up to integer")
		case .RandomString: return translationForString("random string with pattern")
		case .ToUnicodeDateString: return translationForString("write date in format")
		case .FromUnicodeDateString: return translationForString("read date in format")
		case .Power: return translationForString("to the power")
		case .UUID: return translationForString("generate UUID")
		case .CountDistinct: return translationForString("number of unique items")
		case .MedianLow: return translationForString("median value (lowest in case of a draw)")
		case .MedianHigh: return translationForString("median value (highest in case of a draw)")
		case .Median: return translationForString("median value (average in case of a draw)")
		case .MedianPack: return translationForString("median value (pack in case of a draw)")
		case .VariancePopulation: return translationForString("variance (of population)")
		case .VarianceSample: return translationForString("variance (of sample)")
		case .StandardDeviationPopulation: return translationForString("standard deviation (of population)")
		case .StandardDeviationSample: return translationForString("standard deviation (of sample)")
		case .IsInvalid: return translationForString("is invalid")
		case .IsEmpty: return translationForString("is empty")
		case .JSONDecode: return translationForString("read JSON value")
		case .ParseNumber: return translationForString("read number")
		case .HilbertXYToD: return translationForString("to Hilbert index")
		case .HilbertDToX: return translationForString("Hilbert index to X")
		case .HilbertDToY: return translationForString("Hilbert index to Y")
		case .PowerUp: return translationForString("to upper power of")
		case .PowerDown: return translationForString("to lower power of")
		}
	}

	/** Return a localized explanation of what this function does. */
	public func explain(_ locale: Language, arguments: [Expression]) -> String {
		let explainedArguments = arguments.map({$0.explain(locale, topLevel: false)})

		switch self {
		case .Nth where explainedArguments.count == 2:
			return String(format: translationForString("%@th item in %@"), explainedArguments[1], explainedArguments[0])

		case .ValueForKey where explainedArguments.count == 2:
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
		case .RandomItem: return false
		case .RandomBetween: return false
		case .Random: return false
		case .RandomString: return false
		case .Now: return false
		case .UUID: return false
		default: return true
		}
	}

	func toFormula(_ locale: Language, arguments: [Expression]) -> String {
		let name = locale.nameForFunction(self) ?? ""

		switch self {
		case .Nth where arguments.count == 2:
			let args = arguments.map({$0.toFormula(locale)})
			return "\(args[0])[\(args[1])]"

		case .ValueForKey where arguments.count == 2:
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
		case .Uppercase, .Lowercase, .Trim, .Absolute, .Capitalize, .Floor, .Ceiling:
			return true
		default:
			return false
		}
	}
	
	/** Returns information about the parameters a function can receive.  */
	public var parameters: [Parameter]? { get {
		switch self {
		case .Uppercase: return [Parameter(name: translationForString("text"), exampleValue: Value("foo"))]
		case .Lowercase: return [Parameter(name: translationForString("text"), exampleValue: Value("FOO"))]
		
		case .Left, .Right:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("john doe")),
				Parameter(name: translationForString("index"), exampleValue: Value.int(3))
			]
			
		case .Mid:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("john doe")),
				Parameter(name: translationForString("index"), exampleValue: Value.int(5)),
				Parameter(name: translationForString("length"), exampleValue: Value.int(3))
			]
			
		case .Not:
			return [Parameter(name: translationForString("boolean"), exampleValue: Value.bool(false))]
			
		case .And, .Or, .Xor:
			return [
				Parameter(name: translationForString("boolean"), exampleValue: Value.bool(false)),
				Parameter(name: translationForString("boolean"), exampleValue: Value.bool(true))
			]
			
		case .If:
			return [
				Parameter(name: translationForString("boolean"), exampleValue: Value.bool(false)),
				Parameter(name: translationForString("value if true"), exampleValue: Value(translationForString("yes"))),
				Parameter(name: translationForString("value if false"), exampleValue: Value(translationForString("no")))
			]
			
		case .IfError:
			return [
				Parameter(name: translationForString("value"), exampleValue: Value(1346)),
				Parameter(name: translationForString("value if error"), exampleValue: Value(translationForString("(error)")))
			]
		
		case .Duration:
			return [
				Parameter(name: translationForString("start date"), exampleValue: Value(Date(timeIntervalSinceReferenceDate: 0.0))),
				Parameter(name: translationForString("end date"), exampleValue: Value(Date()))
			]
			
		case .After:
			return [
				Parameter(name: translationForString("start date"), exampleValue: Value(Date())),
				Parameter(name: translationForString("seconds"), exampleValue: Value(3600.0))
			]
			
		case .Capitalize, .Length:
			return [Parameter(name: translationForString("text"), exampleValue: Value("john doe"))]
			
		case .URLEncode:
			return [Parameter(name: translationForString("text"), exampleValue: Value("warp [core]"))]
			
		case .Trim:
			return [Parameter(name: translationForString("text"), exampleValue: Value(" warp core "))]
			
		case .Split:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("1337AB#12#C")),
				Parameter(name: translationForString("separator"), exampleValue: Value("#"))
			]
			
		case .Substitute:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("warpcore")),
				Parameter(name: translationForString("find"), exampleValue: Value("warp")),
				Parameter(name: translationForString("replacement"), exampleValue: Value("transwarp"))
			]
			
		case .RegexSubstitute:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("1337AB")),
				Parameter(name: translationForString("find"), exampleValue: Value("[0-9]+")),
				Parameter(name: translationForString("replacement"), exampleValue: Value("#"))
			]
			
		case .UTCDay, .UTCYear, .UTCMonth, .UTCHour, .UTCMinute, .UTCSecond:
			return [Parameter(name: translationForString("date"), exampleValue: Value(Date()))]
			
		case .FromUnixTime:
			return [Parameter(name: translationForString("UNIX timestamp"), exampleValue: Value.double(Date().timeIntervalSince1970))]
			
		case .FromISO8601:
			return [Parameter(name: translationForString("UNIX timestamp"), exampleValue: Value.string(Date().iso8601FormattedLocalDate))]
		
		case .FromExcelDate:
			return [Parameter(name: translationForString("Excel timestamp"), exampleValue: Value.double(Date().excelDate ?? 0))]
			
		case .ToUnixTime, .ToUTCISO8601, .ToLocalISO8601, .ToExcelDate:
			return [Parameter(name: translationForString("date"), exampleValue: Value(Date()))]
			
		case .Levenshtein:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("warp")),
				Parameter(name: translationForString("text"), exampleValue: Value("warpcore"))
			]
			
		case .NormalInverse:
			return [
				Parameter(name: translationForString("p"), exampleValue: Value(0.5)),
				Parameter(name: translationForString("mu"), exampleValue: Value(10)),
				Parameter(name: translationForString("sigma"), exampleValue: Value(1))
			]
		
		case .UTCDate:
			return [
				Parameter(name: translationForString("year"), exampleValue: Value.int(1988)),
				Parameter(name: translationForString("month"), exampleValue: Value.int(8)),
				Parameter(name: translationForString("day"), exampleValue: Value.int(11))
			]
			
		case .RandomBetween:
			return [
				Parameter(name: translationForString("lower bound"), exampleValue: Value.int(0)),
				Parameter(name: translationForString("upper bound"), exampleValue: Value.int(100))
			]
		
		case .Round:
			return [
				Parameter(name: translationForString("number"), exampleValue: Value(3.1337)),
				Parameter(name: translationForString("decimals"), exampleValue: Value(2))
			]
			
		case .Ceiling, .Floor:
			return [
				Parameter(name: translationForString("number"), exampleValue: Value(3.1337))
			]
		
		case .Sin, .Cos, .Tan, .Sinh, .Cosh, .Tanh, .Exp, .Ln, .Log, .Acos, .Asin, .Atan:
			return [Parameter(name: translationForString("number"), exampleValue: Value(M_PI_4))]
			
		case .Sqrt:
			return [Parameter(name: translationForString("number"), exampleValue: Value(144))]
			
		case .Sign, .Absolute, .Negate:
			return [Parameter(name: translationForString("number"), exampleValue: Value(-1337))]
			
		case .Sum, .Count, .CountAll, .Average, .Min, .Max, .RandomItem, .CountDistinct, .Median, .MedianHigh,
			.MedianLow, .MedianPack, .StandardDeviationSample, .StandardDeviationPopulation, .VariancePopulation, .VarianceSample:
			return [
				Parameter(name: translationForString("value"), exampleValue: Value(1)),
				Parameter(name: translationForString("value"), exampleValue: Value(2)),
				Parameter(name: translationForString("value"), exampleValue: Value(3)),
				Parameter(name: translationForString("value"), exampleValue: Value(3))
			]
			
		case .Pack:
			return [
				Parameter(name: translationForString("value"), exampleValue: Value("horse")),
				Parameter(name: translationForString("value"), exampleValue: Value("correct")),
				Parameter(name: translationForString("value"), exampleValue: Value("battery")),
				Parameter(name: translationForString("value"), exampleValue: Value("staple"))
			]
			
		case .Choose:
			return [
				Parameter(name: translationForString("index"), exampleValue: Value.int(2)),
				Parameter(name: translationForString("value"), exampleValue: Value("horse")),
				Parameter(name: translationForString("value"), exampleValue: Value("correct")),
				Parameter(name: translationForString("value"), exampleValue: Value("battery")),
				Parameter(name: translationForString("value"), exampleValue: Value("staple"))
			]
			
		case .In, .NotIn:
			return [
				Parameter(name: translationForString("value"), exampleValue: Value("horse")),
				Parameter(name: translationForString("value"), exampleValue: Value("correct")),
				Parameter(name: translationForString("value"), exampleValue: Value("battery")),
				Parameter(name: translationForString("value"), exampleValue: Value("horse")),
				Parameter(name: translationForString("value"), exampleValue: Value("staple"))
			]
			
		case .Nth:
			return [
				Parameter(name: translationForString("pack"), exampleValue: Value(WarpCore.Pack(["correct","horse", "battery", "staple"]).stringValue)),
				Parameter(name: translationForString("index"), exampleValue: Value.int(2))
			]

		case .ValueForKey:
			return [
				Parameter(name: translationForString("pack"), exampleValue: Value(WarpCore.Pack(["firstName","John", "lastName", "Doe"]).stringValue)),
				Parameter(name: translationForString("index"), exampleValue: Value.string("lastName"))
			]
			
		case .Items:
			return [
				Parameter(name: translationForString("pack"), exampleValue: Value(WarpCore.Pack(["correct","horse", "battery", "staple"]).stringValue))
			]
			
		case .Concat:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value("foo")),
				Parameter(name: translationForString("text"), exampleValue: Value("bar"))
			]
			
		case .Now, .Random:
			return []
			
		case .Identity:
			return [Parameter(name: translationForString("value"), exampleValue: Value("horse"))]
			
		case .Coalesce:
			return [
				Parameter(name: translationForString("value"), exampleValue: Value.invalid),
				Parameter(name: translationForString("value"), exampleValue: Value("horse"))
			]
			
		case .RandomString:
			return [Parameter(name: translationForString("pattern"), exampleValue: Value("[0-9]{4}[A-Z]{2}"))]
			
		case .FromUnicodeDateString:
			return [Parameter(name: translationForString("text"), exampleValue: Value("1988-08-11")), Parameter(name: translationForString("format"), exampleValue: Value("yyyy-MM-dd"))]
			
		case .ToUnicodeDateString:
			return [Parameter(name: translationForString("date"), exampleValue: Value(Date())), Parameter(name: translationForString("format"), exampleValue: Value("yyyy-MM-dd"))]
			
		case .Power:
			return [
				Parameter(name: translationForString("base"), exampleValue: Value.int(2)),
				Parameter(name: translationForString("exponent"), exampleValue: Value.int(32))
			]

		case .UUID:
			return []

		case .IsInvalid:
			return [Parameter(name: translationForString("value"), exampleValue: Value.int(3))]

		case .IsEmpty:
			return [Parameter(name: translationForString("value"), exampleValue: Value.int(3))]

		case .JSONDecode:
			return [Parameter(name: translationForString("JSON"), exampleValue: Value.string("[1,2,3]"))]

		case .ParseNumber:
			return [
				Parameter(name: translationForString("text"), exampleValue: Value.string("1.337,12")),
				Parameter(name: translationForString("decimal separator"), exampleValue: Value.string(",")),
				Parameter(name: translationForString("thousands separator"), exampleValue: Value.string("."))
			]

		case .HilbertXYToD:
			return [
				Parameter(name: translationForString("n"), exampleValue: Value.int(1024)),
				Parameter(name: translationForString("x"), exampleValue: Value.int(100)),
				Parameter(name: translationForString("y"), exampleValue: Value.int(50))
			]

		case .HilbertDToX:
			return [
				Parameter(name: translationForString("n"), exampleValue: Value.int(1024)),
				Parameter(name: translationForString("d"), exampleValue: Value.int(100))
			]

		case .HilbertDToY:
			return [
				Parameter(name: translationForString("n"), exampleValue: Value.int(1024)),
				Parameter(name: translationForString("d"), exampleValue: Value.int(100))
			]

		case .PowerUp:
			return [
				Parameter(name: translationForString("n"), exampleValue: Value.int(510)),
				Parameter(name: translationForString("base"), exampleValue: Value.int(2))
			]

		case .PowerDown:
			return [
				Parameter(name: translationForString("n"), exampleValue: Value.int(510)),
				Parameter(name: translationForString("base"), exampleValue: Value.int(2))
			]
		}
	} }
	
	public var arity: Arity {
		switch self {
		case .Uppercase: return Arity.fixed(1)
		case .Lowercase: return Arity.fixed(1)
		case .Negate: return Arity.fixed(1)
		case .Absolute: return Arity.fixed(1)
		case .Identity: return Arity.fixed(1)
		case .And: return Arity.any
		case .Or: return Arity.any
		case .Cos: return Arity.fixed(1)
		case .Sin: return Arity.fixed(1)
		case .Tan: return Arity.fixed(1)
		case .Cosh: return Arity.fixed(1)
		case .Sinh: return Arity.fixed(1)
		case .Tanh: return Arity.fixed(1)
		case .Acos: return Arity.fixed(1)
		case .Asin: return Arity.fixed(1)
		case .Atan: return Arity.fixed(1)
		case .Sqrt: return Arity.fixed(1)
		case .If: return Arity.fixed(3)
		case .Concat: return Arity.any
		case .Left: return Arity.fixed(2)
		case .Right: return Arity.fixed(2)
		case .Length: return Arity.fixed(1)
		case .Mid: return Arity.fixed(3)
		case .Log: return Arity.between(1,2)
		case .Not: return Arity.fixed(1)
		case .Substitute: return Arity.fixed(3)
		case .Xor: return Arity.fixed(2)
		case .Trim: return Arity.fixed(1)
		case .Coalesce: return Arity.any
		case .IfError: return Arity.fixed(2)
		case .Count: return Arity.any
		case .Sum: return Arity.any
		case .Average: return Arity.any
		case .Max: return Arity.any
		case .Min: return Arity.any
		case .RandomItem: return Arity.any
		case .CountAll: return Arity.any
		case .Pack: return Arity.any
		case .Exp: return Arity.fixed(1)
		case .Ln: return Arity.fixed(1)
		case .Round: return Arity.between(1,2)
		case .Choose: return Arity.any
		case .RandomBetween: return Arity.fixed(2)
		case .Random: return Arity.fixed(0)
		case .RegexSubstitute: return Arity.fixed(3)
		case .NormalInverse: return Arity.fixed(3)
		case .Sign: return Arity.fixed(1)
		case .Split: return Arity.fixed(2)
		case .Nth: return Arity.fixed(2)
		case .ValueForKey: return Arity.fixed(2)
		case .Items: return Arity.fixed(1)
		case .Levenshtein: return Arity.fixed(2)
		case .URLEncode: return Arity.fixed(1)
		case .In: return Arity.atLeast(2)
		case .NotIn: return Arity.atLeast(2)
		case .Capitalize: return Arity.fixed(1)
		case .Now: return Arity.fixed(0)
		case .FromUnixTime: return Arity.fixed(1)
		case .ToUnixTime: return Arity.fixed(1)
		case .FromISO8601: return Arity.fixed(1)
		case .ToLocalISO8601: return Arity.fixed(1)
		case .ToUTCISO8601: return Arity.fixed(1)
		case .ToExcelDate: return Arity.fixed(1)
		case .FromExcelDate: return Arity.fixed(1)
		case .UTCDate: return Arity.fixed(3)
		case .UTCDay: return Arity.fixed(1)
		case .UTCMonth: return Arity.fixed(1)
		case .UTCYear: return Arity.fixed(1)
		case .UTCMinute: return Arity.fixed(1)
		case .UTCHour: return Arity.fixed(1)
		case .UTCSecond: return Arity.fixed(1)
		case .Duration: return Arity.fixed(2)
		case .After: return Arity.fixed(2)
		case .Ceiling: return Arity.fixed(1)
		case .Floor: return Arity.fixed(1)
		case .RandomString: return Arity.fixed(1)
		case .ToUnicodeDateString: return Arity.fixed(2)
		case .FromUnicodeDateString: return Arity.fixed(2)
		case .Power: return Arity.fixed(2)
		case .UUID: return Arity.fixed(0)
		case .CountDistinct: return Arity.any
		case .MedianPack: return Arity.any
		case .MedianHigh: return Arity.any
		case .MedianLow: return Arity.any
		case .Median: return Arity.any
		case .StandardDeviationPopulation: return Arity.any
		case .StandardDeviationSample: return Arity.any
		case .VariancePopulation: return Arity.any
		case .VarianceSample: return Arity.any
		case .IsInvalid: return Arity.fixed(1)
		case .IsEmpty: return Arity.fixed(1)
		case .JSONDecode: return Arity.fixed(1)
		case .ParseNumber: return Arity.between(1, 3)
		case .HilbertXYToD: return Arity.fixed(3)
		case .HilbertDToX: return Arity.fixed(2)
		case .HilbertDToY: return Arity.fixed(2)
		case .PowerDown: return Arity.fixed(2)
		case .PowerUp: return Arity.fixed(2)
		}
	}
	
	public func apply(_ arguments: [Value]) -> Value {
		// Check arity
		if !arity.valid(arguments.count) {
			return Value.invalid
		}
		
		switch self {
		case .Negate:
			return -arguments[0]
			
		case .Uppercase:
			if let s = arguments[0].stringValue {
				return Value(s.uppercased())
			}
			return Value.invalid
			
		case .Lowercase:
			if let s = arguments[0].stringValue {
				return Value(s.lowercased())
			}
			return Value.invalid
			
		case .Absolute:
			return arguments[0].absolute
			
		case .Identity:
			return arguments[0]
			
		case .And:
			for a in arguments {
				if !a.isValid {
					return Value.invalid
				}
				
				if a != Value(true) {
					return Value(false)
				}
			}
			return Value(true)
			
		case .Coalesce:
			for a in arguments {
				if a.isValid && !a.isEmpty {
					return a
				}
			}
			return Value.empty
			
		case .Not:
			if let b = arguments[0].boolValue {
				return Value(!b)
			}
			return Value.invalid
		
		case .Or:
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
			
		case .Xor:
			if let a = arguments[0].boolValue {
				if let b = arguments[1].boolValue {
					return Value((a != b) && (a || b))
				}
			}
			return Value.invalid
			
		case .If:
			if let d = arguments[0].boolValue {
				return d ? arguments[1] : arguments[2]
			}
			return Value.invalid
			
		case .IfError:
			return (!arguments[0].isValid) ? arguments[1] : arguments[0]
			
		case .Cos:
			if let d = arguments[0].doubleValue {
				return Value(cos(d))
			}
			return Value.invalid
		
		case .Ln:
			if let d = arguments[0].doubleValue {
				return Value(log10(d) / log10(exp(1.0)))
			}
			return Value.invalid
			
		case .Exp:
			if let d = arguments[0].doubleValue {
				return Value(exp(d))
			}
			return Value.invalid
			
		case .Log:
			if let d = arguments[0].doubleValue {
				if arguments.count == 2 {
					if let base = arguments[1].doubleValue {
						return Value(log(d) / log(base))
					}
					return Value.invalid
				}
				return Value(log10(d))
			}
			return Value.invalid
			
		case .Sin:
			if let d = arguments[0].doubleValue {
				return Value(sin(d))
			}
			return Value.invalid
			
		case .Tan:
			if let d = arguments[0].doubleValue {
				return Value(tan(d))
			}
			return Value.invalid
			
		case .Cosh:
			if let d = arguments[0].doubleValue {
				return Value(cosh(d))
			}
			return Value.invalid
			
		case .Sinh:
			if let d = arguments[0].doubleValue {
				return Value(sinh(d))
			}
			return Value.invalid
			
		case .Tanh:
			if let d = arguments[0].doubleValue {
				return Value(tanh(d))
			}
			return Value.invalid
			
		case .Acos:
			if let d = arguments[0].doubleValue {
				return Value(acos(d))
			}
			return Value.invalid
			
		case .Asin:
			if let d = arguments[0].doubleValue {
				return Value(asin(d))
			}
			return Value.invalid
			
		case .Atan:
			if let d = arguments[0].doubleValue {
				return Value(atan(d))
			}
			return Value.invalid
			
		case .Sqrt:
			if let d = arguments[0].doubleValue {
				return Value(sqrt(d))
			}
			return Value.invalid
			
		case .Left:
			if let s = arguments[0].stringValue {
				if let idx = arguments[1].intValue {
					if s.characters.count >= idx {
						let index = s.characters.index(s.startIndex, offsetBy: idx)
						return Value(s.substring(to: index))
					}
				}
			}
			return Value.invalid
			
		case .Right:
			if let s = arguments[0].stringValue {
				if let idx = arguments[1].intValue {
					if s.characters.count >= idx {
						let index = s.characters.index(s.endIndex, offsetBy: -idx)
						return Value(s.substring(from: index))
					}
				}
			}
			return Value.invalid
			
		case .Mid:
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
			
		case .Length:
			if let s = arguments[0].stringValue {
				return Value(s.characters.count)
			}
			return Value.invalid
		
		case .Substitute:
			if let source = arguments[0].stringValue {
				if let replace = arguments[1].stringValue {
					if let replaceWith = arguments[2].stringValue {
						// TODO: add case-insensitive and regex versions of this
						return Value(source.replacingOccurrences(of: replace, with: replaceWith))
					}
				}
			}
			return Value.invalid
		
		case .Trim:
			if let s = arguments[0].stringValue {
				return Value(s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
			}
			return Value.invalid
			
		case .RandomItem:
			if arguments.isEmpty {
				return Value.empty
			}
			else {
				let index = Int.random(0..<arguments.count)
				return arguments[index]
			}
			
			
		case .Round:
			var decimals = 0
			if arguments.count == 2 {
				decimals = arguments[1].intValue ?? 0
			}
			
			if decimals < 0 {
				return Value.invalid
			}
			
			if let d = arguments[0].doubleValue {
				if decimals == 0 {
					return Value.int(Int(round(d)))
				}
				else {
					let filler = pow(10.0, Double(decimals))
					return Value(round(filler * d) / filler)
				}
			}
			
			return Value.invalid
			
		case .Choose:
			if arguments.count < 2 {
				return Value.invalid
			}
			
			if let index = arguments[0].intValue {
				if index < arguments.count && index > 0 {
					return arguments[index]
				}
			}
			return Value.invalid
			
		case .RandomBetween:
			if let bottom = arguments[0].intValue {
				if let top = arguments[1].intValue {
					if top <= bottom {
						return Value.invalid
					}
					
					return Value(Int.random(bottom, upper: top+1))
				}
			}
			return Value.invalid
			
		case .Random:
			return Value(Double.random())
			
		case .RegexSubstitute:
			// Note: by default, this is case-sensitive (like .Substitute)
			if	let source = arguments[0].stringValue,
				let pattern = arguments[1].stringValue,
				let replacement = arguments[2].stringValue,
				let result = source.replace(pattern, withTemplate: replacement, caseSensitive: true) {
					return Value.string(result)
			}
			return Value.invalid
			
		case .NormalInverse:
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
			
		case .Sign:
			if let d = arguments[0].doubleValue {
				let sign = (d==0) ? 0 : (d>0 ? 1 : -1)
				return Value.int(sign)
			}
			return Value.invalid
			
			
		case .Split:
			if let s = arguments[0].stringValue {
				let separator = (arguments.count > 1 ? arguments[1].stringValue : nil) ?? " "
				let splitted = s.components(separatedBy: separator)
				let pack = WarpCore.Pack(splitted)
				return Value.string(pack.stringValue)
			}
			return Value.invalid
			
			
		case .Nth:
			if let pack = WarpCore.Pack(arguments[0]) {
				if let index = arguments[1].intValue {
					let adjustedIndex = index-1
					if adjustedIndex < pack.count && adjustedIndex >= 0 {
						return Value.string(pack[adjustedIndex])
					}
				}
			}
			return Value.invalid

		case .ValueForKey:
			if let pack = WarpCore.Pack(arguments[0]) {
				if let index = arguments[1].stringValue, let value = pack[index] {
					return Value.string(value)
				}
			}
			return Value.invalid
			
		case .Items:
			if let pack = WarpCore.Pack(arguments[0]) {
				return Value.int(pack.count)
			}
			return Value.invalid
			
		case .Levenshtein:
			if let a = arguments[0].stringValue, let b = arguments[1].stringValue {
				return Value.int(a.levenshteinDistance(b))
			}
			return Value.invalid
			
		case .URLEncode:
			if let s = arguments[0].stringValue, let enc = s.urlEncoded {
				return Value(enc)
			}
			return Value.invalid
			
		case .In:
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
			
		case .NotIn:
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
			
		case .Capitalize:
			if let s = arguments[0].stringValue {
				return Value.string(s.capitalized)
			}
			return Value.invalid
			
		case .Now:
			return Value(Date())
			
		case .FromUnixTime:
			if let s = arguments[0].doubleValue {
				return Value(Date(timeIntervalSince1970: s))
			}
			return Value.invalid
			
		case .ToUnixTime:
			if let d = arguments[0].dateValue {
				return Value(d.timeIntervalSince1970)
			}
			return Value.invalid
			
		case .FromISO8601:
			if let s = arguments[0].stringValue, let d = Date.fromISO8601FormattedDate(s) {
				return Value(d)
			}
			return Value.invalid
			
		case .ToLocalISO8601:
			if let d = arguments[0].dateValue {
				return Value(d.iso8601FormattedLocalDate)
			}
			return Value.invalid
			
		case .ToUTCISO8601:
			if let d = arguments[0].dateValue {
				return Value(d.iso8601FormattedUTCDate)
			}
			return Value.invalid
			
		case .ToExcelDate:
			if let d = arguments[0].dateValue, let e = d.excelDate {
				return Value(e)
			}
			return Value.invalid
			
		case .FromExcelDate:
			if let d = arguments[0].doubleValue, let x = Date.fromExcelDate(d) {
				return Value(x)
			}
			return Value.invalid
			
		case .UTCDate:
			if let year = arguments[0].intValue, let month = arguments[1].intValue, let day = arguments[2].intValue {
				return Value(Date.startOfGregorianDateInUTC(year, month: month, day: day))
			}
			return Value.invalid
			
		case .UTCDay:
			if let date = arguments[0].dateValue, let d = date.gregorianComponentsInUTC.day {
				return Value(d)
			}
			return Value.invalid

		case .UTCMonth:
			if let date = arguments[0].dateValue, let m = date.gregorianComponentsInUTC.month {
				return Value(m)
			}
			return Value.invalid

		case .UTCYear:
			if let date = arguments[0].dateValue, let y = date.gregorianComponentsInUTC.year {
				return Value(y)
			}
			return Value.invalid

		case .UTCHour:
			if let date = arguments[0].dateValue, let h = date.gregorianComponentsInUTC.hour {
				return Value(h)
			}
			return Value.invalid

		case .UTCMinute:
			if let date = arguments[0].dateValue, let m = date.gregorianComponentsInUTC.minute {
				return Value(m)
			}
			return Value.invalid

		case .UTCSecond:
			if let date = arguments[0].dateValue, let s = date.gregorianComponentsInUTC.second {
				return Value(s)
			}
			return Value.invalid
			
		case .Duration:
			if let start = arguments[0].dateValue, let end = arguments[1].dateValue {
				return Value(end.timeIntervalSinceReferenceDate - start.timeIntervalSinceReferenceDate)
			}
			return Value.invalid
			
		case .After:
			if let start = arguments[0].dateValue, let duration = arguments[1].doubleValue {
				return Value(Date(timeInterval: duration, since: start as Date))
			}
			return Value.invalid
			
		case .Floor:
			if let d = arguments[0].doubleValue {
				return Value(floor(d))
			}
			return Value.invalid
			
		case .Ceiling:
			if let d = arguments[0].doubleValue {
				return Value(ceil(d))
			}
			return Value.invalid
			
		case .RandomString:
			if let p = arguments[0].stringValue, let sequencer = Sequencer(p) {
				return sequencer.randomValue ?? Value.empty
			}
			return Value.invalid
			
		case .ToUnicodeDateString:
			if let d = arguments[0].dateValue, let format = arguments[1].stringValue {
				let formatter = DateFormatter()
				formatter.dateFormat = format
				formatter.timeZone = TimeZone(abbreviation: "UTC")
				return Value.string(formatter.string(from: d as Date))
			}
			return Value.invalid
			
		case .FromUnicodeDateString:
			if let d = arguments[0].stringValue, let format = arguments[1].stringValue {
				let formatter = DateFormatter()
				formatter.dateFormat = format
				formatter.timeZone = TimeZone(abbreviation: "UTC")
				if let date = formatter.date(from: d) {
					return Value(date)
				}
			}
			return Value.invalid
			
		case .Power:
			return arguments[0] ^ arguments[1]

		case .UUID:
			return .string(Foundation.UUID().uuidString)

		case .IsInvalid:
			return Value.bool(!arguments[0].isValid)

		case .IsEmpty:
			return Value.bool(arguments[0].isEmpty)

		case .JSONDecode:
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

		case .ParseNumber:
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

		case .HilbertXYToD:
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

		case .HilbertDToX:
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

		case .HilbertDToY:
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

		case .PowerUp:
			if let n = arguments[0].intValue, let base = arguments[1].intValue {
				if base <= 1 {
					return Value.invalid
				}

				if let d = n.powerUp(base: base) {
					return Value.int(d)
				}
			}
			return Value.invalid

		case .PowerDown:
			if let n = arguments[0].intValue, let base = arguments[1].intValue {
				if base <= 1 || n < 1 {
					return Value.invalid
				}

				if let d = n.powerDown(base: base) {
					return Value.int(d)
				}
			}
			return Value.invalid


		// The following functions are already implemented as a Reducer, just use that
		case .Sum, .Min, .Max, .Count, .CountAll, .Average, .Concat, .Pack, .CountDistinct, .Median, .MedianHigh,
			.MedianLow, .MedianPack, .VarianceSample, .VariancePopulation, .StandardDeviationPopulation, .StandardDeviationSample:
			var r = self.reducer!
			r.add(arguments)
			return r.result
		}
	}

	public var reducer: Reducer? {
		switch self {
		case .Sum: return SumReducer()
		case .Min: return MinReducer()
		case .Max: return MaxReducer()
		case .CountDistinct: return CountDistinctReducer()
		case .Count: return CountReducer(all: false)
		case .CountAll: return CountReducer(all: true)
		case .Average: return AverageReducer()
		case .Concat: return ConcatenationReducer()
		case .Pack: return PackReducer()
		case .MedianPack: return MedianReducer(medianType: .pack)
		case .MedianHigh: return MedianReducer(medianType: .high)
		case .MedianLow: return MedianReducer(medianType: .low)
		case .Median: return MedianReducer(medianType: .average)
		case .VariancePopulation: return VarianceReducer(varianceType: .population)
		case .VarianceSample: return VarianceReducer(varianceType: .sample)
		case .StandardDeviationPopulation: return StandardDeviationReducer(varianceType: .population)
		case .StandardDeviationSample: return StandardDeviationReducer(varianceType: .sample)

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
		case .Sum, .Min, .Max, .Average, .Concat, .Pack, .Median, .MedianLow, .MedianHigh, .And, .Or, .RandomItem: return true
		default: return false
		}
	}

	public static let allFunctions = [
		Uppercase, Lowercase, Negate, Absolute, And, Or, Acos, Asin, Atan, Cosh, Sinh, Tanh, Cos, Sin, Tan, Sqrt, Concat,
		If, Left, Right, Mid, Length, Substitute, Count, Sum, Trim, Average, Min, Max, RandomItem, CountAll, Pack, IfError,
		Exp, Log, Ln, Round, Choose, Random, RandomBetween, RegexSubstitute, NormalInverse, Sign, Split, Nth, Items,
		Levenshtein, URLEncode, In, NotIn, Not, Capitalize, Now, ToUnixTime, FromUnixTime, FromISO8601, ToLocalISO8601,
		ToUTCISO8601, ToExcelDate, FromExcelDate, UTCDate, UTCDay, UTCMonth, UTCYear, UTCHour, UTCMinute, UTCSecond,
		Duration, After, Xor, Floor, Ceiling, RandomString, ToUnicodeDateString, FromUnicodeDateString, Power, UUID,
		CountDistinct, MedianLow, MedianHigh, MedianPack, Median, VarianceSample, VariancePopulation, StandardDeviationSample,
		StandardDeviationPopulation, IsEmpty, IsInvalid, JSONDecode, ParseNumber, ValueForKey, HilbertXYToD, HilbertDToX,
		HilbertDToY, PowerDown, PowerUp
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
