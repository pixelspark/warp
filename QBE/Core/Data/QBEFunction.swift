import Foundation

/** Description of a function parameter. */
struct QBEParameter {
	let name: String
	let exampleValue: QBEValue
}

/** QBEArity represents the 'arity' of a function (the number of arguments a function requires or supports). The arity
of a function can either be 'fixed' (a function with an arity of '1' is called unary, a function with arity '2' is a 
binary), constrained ('between x and y') or anything. Functions that can take any number of arguments can also be used
as aggregating functions (if they are adhere to the property that (e.g.) SUM(1;2;3;4) == SUM(SUM(1;2);SUM(3;4)). */
enum QBEArity: Equatable {
	case Fixed(Int)
	case AtLeast(Int)
	case Between(Int, Int)
	case Any
	
	func valid(count: Int) -> Bool {
		switch self {
		case .Fixed(let i):
			return count == i
			
		case .AtLeast(let i):
			return count >= i
		
		case .Between(let a, let b):
			return count >= a && count <= b
			
		case .Any:
			return true
		}
	}
	
	var explanation: String { get {
		switch self {
			case .Fixed(let i):
				return String(format: NSLocalizedString("exactly %d", comment: ""), i)
			
			case .AtLeast(let i):
				return String(format: NSLocalizedString("at least %d", comment: ""), i)
			
			case .Between(let a, let b):
				return String(format: NSLocalizedString("between %d and %d", comment: ""), a, b)
			
			case .Any:
				return String(format: NSLocalizedString("zero or more", comment: ""))
		}
	} }
}

func ==(lhs: QBEArity, rhs: QBEArity) -> Bool {
	switch (lhs, rhs) {
		case (.Any, .Any):
			return true
		case (.Fixed(let lf), .Fixed(let rf)):
			return lf == rf
		default:
			return false
	}
}

/** A QBEFunction takes a list of QBEValue arguments (which may be empty) and returns a single QBEValue. QBEFunctions 
each have a unique identifier (used for serializing), display names (which are localized), and arity (which indicates
which number of arguments is allowed) and an implementation. QBEFunctions may also be implemented in other ways in other
ways (e.g. by compilation to SQL). Functions that have 'any' arity can be considered to be aggregation functions. */
enum QBEFunction: String {
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
	
	/** This function optimizes an expression that is an application of this function to the indicates arguments to a
	more efficient or succint expression. Note that other optimizations are applied elsewhere as well (e.g. if a function
	is deterministic and all arguments are constants, it is automatically replaced with a literal expression containing
	its constant result). */
	func prepare(args: [QBEExpression]) -> QBEExpression {
		var prepared = args.map({$0.prepare()})
		
		switch self {
			case .Not:
				if args.count == 1 {
					// NOT(a=b) should be replaced with simply a!=b
					if let a = args[0] as? QBEBinaryExpression where a.type == QBEBinary.Equal {
						return QBEBinaryExpression(first: a.first, second: a.second, type: QBEBinary.NotEqual).prepare()
					}
					// Not(In(..)) should be written as NotIn(..)
					else if let a = args[0] as? QBEFunctionExpression where a.type == QBEFunction.In {
						return QBEFunctionExpression(arguments: a.arguments, type: QBEFunction.NotIn).prepare()
					}
					// Not(Not(..)) cancels out
					else if let a = args[0] as? QBEFunctionExpression where a.type == QBEFunction.Not && a.arguments.count == 1 {
						return a.arguments[0].prepare()
					}
				}
			
			case .And:
				// Insert arguments that are Ands themselves in this and
				prepared = prepared.mapMany {(item) -> [QBEExpression] in
					if let a = item as? QBEFunctionExpression where a.type == QBEFunction.And {
						return a.arguments
					}
					else {
						return [item]
					}
				}
				
				// If at least one of the arguments to an AND is a constant false, then this And always evaluates to false
				for p in prepared {
					if p.isConstant && p.apply(QBERow(), foreign: nil, inputValue: nil) == QBEValue.BoolValue(false) {
						return QBELiteralExpression(QBEValue.BoolValue(false))
					}
				}
			
			case .Or:
				// Insert arguments that are Ors themselves in this or
				prepared = prepared.mapMany({
					if let a = $0 as? QBEFunctionExpression where a.type == QBEFunction.Or {
						return a.arguments
					}
					return [$0]
				})
				
				// If at least one of the arguments to an OR is a constant true, this OR always evaluates to true
				for p in prepared {
					if p.isConstant && p.apply(QBERow(), foreign: nil, inputValue: nil) == QBEValue.BoolValue(true) {
						return QBELiteralExpression(QBEValue.BoolValue(true))
					}
				}
				
				// If this OR consists of (x = y) pairs where x is the same column (or foreign, this can be translated to an IN(x, y1, y2, ..)
				var columnExpression: QBEColumnReferencingExpression? = nil
				var valueExpressions: [QBEExpression] = []
				var binaryType: QBEBinary? = nil
				let allowedBinaryTypes = [QBEBinary.Equal]
				
				for p in prepared {
					if let binary = p as? QBEBinaryExpression where allowedBinaryTypes.contains(binary.type) && (binaryType == nil || binaryType == binary.type) {
						binaryType = binary.type
						
						// See if one of the sides of this binary expression is a column reference
						let column: QBEColumnReferencingExpression?
						let value: QBEExpression?
						if binary.first is QBEColumnReferencingExpression {
							column = binary.first as? QBEColumnReferencingExpression
							value = binary.second
						}
						else if binary.second is QBEColumnReferencingExpression {
							column = binary.second as? QBEColumnReferencingExpression
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
								let sameType = (c is QBESiblingExpression && columnExpression is QBESiblingExpression) ||
									(c is QBEForeignExpression && columnExpression is QBEForeignExpression)
								if sameType && c.columnName != ce.columnName {
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
				
				if let ce = columnExpression as? QBEExpression, let bt = binaryType where valueExpressions.count > 1 {
					valueExpressions.insert(ce, atIndex: 0)

					switch bt {
						case .Equal:
							return QBEFunctionExpression(arguments: valueExpressions, type: QBEFunction.In)
						
						case .NotEqual:
							return QBEFunctionExpression(arguments: valueExpressions, type: QBEFunction.NotIn)
						
						default:
							fatalError("Cannot produce an IN()-like expression for this binary type")
					}
				}
		
			default:
				break
		}
	
		return QBEFunctionExpression(arguments: prepared, type: self)
	}
	
	func explain(locale: QBELocale) -> String {
		switch self {
			// TODO: make tihs more detailed. E.g., "5 leftmost characters of" instead of just "leftmost characters"
			case .Uppercase: return NSLocalizedString("uppercase", comment: "")
			case .Lowercase: return NSLocalizedString("lowercase", comment:"")
			case .Negate: return NSLocalizedString("-", comment:"")
			case .Absolute: return NSLocalizedString("absolute", comment:"")
			case .Identity: return NSLocalizedString("the", comment:"")
			case .And: return NSLocalizedString("and", comment:"")
			case .Or: return NSLocalizedString("or", comment:"")
			case .If: return NSLocalizedString("if", comment: "")
			case .Concat: return NSLocalizedString("concatenate", comment: "")
			case .Cos: return NSLocalizedString("cose", comment:"")
			case .Sin: return NSLocalizedString("sine", comment:"")
			case .Tan: return NSLocalizedString("tangens", comment:"")
			case .Cosh: return NSLocalizedString("cosine hyperbolic", comment:"")
			case .Sinh: return NSLocalizedString("sine hyperbolic", comment:"")
			case .Tanh: return NSLocalizedString("tangens hyperbolic", comment:"")
			case .Acos: return NSLocalizedString("arc cosine", comment:"")
			case .Asin: return NSLocalizedString("arc sine", comment:"")
			case .Atan: return NSLocalizedString("arc tangens", comment:"")
			case .Sqrt: return NSLocalizedString("square root", comment:"")
			case .Left: return NSLocalizedString("leftmost characters", comment: "")
			case .Right: return NSLocalizedString("rightmost characters", comment: "")
			case .Length: return NSLocalizedString("length of text", comment: "")
			case .Mid: return NSLocalizedString("substring", comment: "")
			case .Log: return NSLocalizedString("logarithm", comment: "")
			case .Not: return NSLocalizedString("not", comment: "")
			case .Substitute: return NSLocalizedString("substitute", comment: "")
			case .Xor: return NSLocalizedString("xor", comment: "")
			case .Trim: return NSLocalizedString("trim spaces", comment: "")
			case .Coalesce: return NSLocalizedString("first non-empty value", comment: "")
			case .IfError: return NSLocalizedString("if error", comment: "")
			case .Count: return NSLocalizedString("number of numeric values", comment: "")
			case .Sum: return NSLocalizedString("sum", comment: "")
			case .Average: return NSLocalizedString("average", comment: "")
			case .Min: return NSLocalizedString("lowest", comment: "")
			case .Max: return NSLocalizedString("highest", comment: "")
			case .RandomItem: return NSLocalizedString("random item", comment: "")
			case .CountAll: return NSLocalizedString("number of items", comment: "")
			case .Pack: return NSLocalizedString("pack", comment: "")
			case .Exp: return NSLocalizedString("e^", comment: "exponent function")
			case .Ln: return NSLocalizedString("natural logarithm", comment: "ln")
			case .Round: return NSLocalizedString("round", comment: "")
			case .Choose: return NSLocalizedString("choose", comment: "")
			case .RandomBetween: return NSLocalizedString("random number between", comment: "")
			case .Random: return NSLocalizedString("random number between 0 and 1", comment: "")
			case .RegexSubstitute: return NSLocalizedString("replace using pattern", comment: "")
			case .NormalInverse: return NSLocalizedString("inverse normal", comment: "")
			case .Sign: return NSLocalizedString("sign", comment: "")
			case .Split: return NSLocalizedString("split", comment: "")
			case .Nth: return NSLocalizedString("nth item", comment: "")
			case .Items: return NSLocalizedString("number of items", comment: "")
			case .Levenshtein: return NSLocalizedString("text similarity", comment: "")
			case .URLEncode: return NSLocalizedString("url encode", comment: "")
			case .In: return NSLocalizedString("contains", comment: "")
			case .NotIn: return NSLocalizedString("does not contain", comment: "")
			case .Capitalize: return NSLocalizedString("capitalize", comment: "")
			case .Now: return NSLocalizedString("current time", comment: "")
			case .FromUnixTime: return NSLocalizedString("interpret UNIX timestamp", comment: "")
			case .ToUnixTime: return NSLocalizedString("to UNIX timestamp", comment: "")
			case .FromISO8601: return NSLocalizedString("interpret ISO-8601 formatted date", comment: "")
			case .ToLocalISO8601: return NSLocalizedString("to ISO-8601 formatted date in local timezone", comment: "")
			case .ToUTCISO8601: return NSLocalizedString("to ISO-8601 formatted date in UTC", comment: "")
			case .ToExcelDate: return NSLocalizedString("to Excel timestamp", comment: "")
			case .FromExcelDate: return NSLocalizedString("from Excel timestamp", comment: "")
			case .UTCDate: return NSLocalizedString("make a date (in UTC)", comment: "")
			case .UTCDay: return NSLocalizedString("day in month (in UTC) of date", comment: "")
			case .UTCMonth: return NSLocalizedString("month (in UTC) of", comment: "")
			case .UTCYear: return NSLocalizedString("year (in UTC) of date", comment: "")
			case .UTCMinute: return NSLocalizedString("minute (in UTC) of time", comment: "")
			case .UTCHour: return NSLocalizedString("hour (in UTC) of time", comment: "")
			case .UTCSecond: return NSLocalizedString("seconds (in UTC) of time", comment: "")
			case .Duration: return NSLocalizedString("number of seconds that passed between dates", comment: "")
			case .After: return NSLocalizedString("date after a number of seconds has passed after date", comment: "")
		}
	}
	
	/** Returns true if this function is guaranteed to return the same result when called multiple times in succession
	with the exact same set of arguments. Functions that depend on/return randomness or the current date/time are not
	 deterministic. */
	var isDeterministic: Bool { get {
		switch self {
			case .RandomItem: return false
			case .RandomBetween: return false
			case .Random: return false
			case .Now: return false
			default: return true
		}
	} }
	
	func toFormula(locale: QBELocale) -> String {
		return locale.nameForFunction(self) ?? ""
	}
	
	/** Returns information about the parameters a function can receive.  */
	var parameters: [QBEParameter]? { get {
		switch self {
		case .Uppercase: return [QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("foo"))]
		case .Lowercase: return [QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("FOO"))]
		
		case .Left, .Right:
			return [
				QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("john doe")),
				QBEParameter(name: NSLocalizedString("index", comment: ""), exampleValue: QBEValue.IntValue(3))
			]
			
		case .Mid:
			return [
				QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("john doe")),
				QBEParameter(name: NSLocalizedString("index", comment: ""), exampleValue: QBEValue.IntValue(5)),
				QBEParameter(name: NSLocalizedString("length", comment: ""), exampleValue: QBEValue.IntValue(3))
			]
			
		case .Not:
			return [QBEParameter(name: NSLocalizedString("boolean", comment: ""), exampleValue: QBEValue.BoolValue(false))]
			
		case .And, .Or, .Xor:
			return [
				QBEParameter(name: NSLocalizedString("boolean", comment: ""), exampleValue: QBEValue.BoolValue(false)),
				QBEParameter(name: NSLocalizedString("boolean", comment: ""), exampleValue: QBEValue.BoolValue(true))
			]
			
		case .If:
			return [
				QBEParameter(name: NSLocalizedString("boolean", comment: ""), exampleValue: QBEValue.BoolValue(false)),
				QBEParameter(name: NSLocalizedString("value if true", comment: ""), exampleValue: QBEValue(NSLocalizedString("yes", comment: ""))),
				QBEParameter(name: NSLocalizedString("value if false", comment: ""), exampleValue: QBEValue(NSLocalizedString("no", comment: "")))
			]
			
		case .IfError:
			return [
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue(1346)),
				QBEParameter(name: NSLocalizedString("value if error", comment: ""), exampleValue: QBEValue(NSLocalizedString("(error)", comment: "")))
			]
		
		case .Duration:
			return [
				QBEParameter(name: NSLocalizedString("start date", comment: ""), exampleValue: QBEValue(NSDate(timeIntervalSinceReferenceDate: 0.0))),
				QBEParameter(name: NSLocalizedString("end date", comment: ""), exampleValue: QBEValue(NSDate()))
			]
			
		case .After:
			return [
				QBEParameter(name: NSLocalizedString("start date", comment: ""), exampleValue: QBEValue(NSDate())),
				QBEParameter(name: NSLocalizedString("seconds", comment: ""), exampleValue: QBEValue(3600.0))
			]
			
		case .Capitalize, .Length:
			return [QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("john doe"))]
			
		case .URLEncode:
			return [QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("warp [core]"))]
			
		case .Trim:
			return [QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue(" warp core "))]
			
		case .Split:
			return [
				QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("1337AB#12#C")),
				QBEParameter(name: NSLocalizedString("separator", comment: ""), exampleValue: QBEValue("#"))
			]
			
		case .Substitute:
			return [
				QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("warpcore")),
				QBEParameter(name: NSLocalizedString("find", comment: ""), exampleValue: QBEValue("warp")),
				QBEParameter(name: NSLocalizedString("replacement", comment: ""), exampleValue: QBEValue("transwarp"))
			]
			
		case .RegexSubstitute:
			return [
				QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("1337AB")),
				QBEParameter(name: NSLocalizedString("find", comment: ""), exampleValue: QBEValue("[0-9]+")),
				QBEParameter(name: NSLocalizedString("replacement", comment: ""), exampleValue: QBEValue("#"))
			]
			
		case .UTCDay, .UTCYear, .UTCMonth, .UTCHour, .UTCMinute, .UTCSecond:
			return [QBEParameter(name: NSLocalizedString("date", comment: ""), exampleValue: QBEValue(NSDate()))]
			
		case .FromUnixTime:
			return [QBEParameter(name: NSLocalizedString("UNIX timestamp", comment: ""), exampleValue: QBEValue.DoubleValue(NSDate().timeIntervalSince1970))]
			
		case .FromISO8601:
			return [QBEParameter(name: NSLocalizedString("UNIX timestamp", comment: ""), exampleValue: QBEValue.StringValue(NSDate().iso8601FormattedLocalDate))]
		
		case .FromExcelDate:
			return [QBEParameter(name: NSLocalizedString("Excel timestamp", comment: ""), exampleValue: QBEValue.DoubleValue(NSDate().excelDate ?? 0))]
			
		case .ToUnixTime, .ToUTCISO8601, .ToLocalISO8601, .ToExcelDate:
			return [QBEParameter(name: NSLocalizedString("date", comment: ""), exampleValue: QBEValue(NSDate()))]
			
		case .Levenshtein:
			return [
				QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("warp")),
				QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("warpcore"))
			]
			
		case .NormalInverse:
			return [
				QBEParameter(name: NSLocalizedString("p", comment: ""), exampleValue: QBEValue(0.5)),
				QBEParameter(name: NSLocalizedString("mu", comment: ""), exampleValue: QBEValue(10)),
				QBEParameter(name: NSLocalizedString("sigma", comment: ""), exampleValue: QBEValue(1))
			]
		
		case .UTCDate:
			return [
				QBEParameter(name: NSLocalizedString("year", comment: ""), exampleValue: QBEValue.IntValue(1988)),
				QBEParameter(name: NSLocalizedString("month", comment: ""), exampleValue: QBEValue.IntValue(8)),
				QBEParameter(name: NSLocalizedString("day", comment: ""), exampleValue: QBEValue.IntValue(11))
			]
			
		case .RandomBetween:
			return [
				QBEParameter(name: NSLocalizedString("lower bound", comment: ""), exampleValue: QBEValue.IntValue(0)),
				QBEParameter(name: NSLocalizedString("upper bound", comment: ""), exampleValue: QBEValue.IntValue(100))
			]
		
		case .Round:
			return [
				QBEParameter(name: NSLocalizedString("number", comment: ""), exampleValue: QBEValue(3.1337)),
				QBEParameter(name: NSLocalizedString("decimals", comment: ""), exampleValue: QBEValue(2))
			]
		
		case .Sin, .Cos, .Tan, .Sinh, .Cosh, .Tanh, .Exp, .Ln, .Log, .Acos, .Asin, .Atan:
			return [QBEParameter(name: NSLocalizedString("number", comment: ""), exampleValue: QBEValue(M_PI_4))]
			
		case .Sqrt:
			return [QBEParameter(name: NSLocalizedString("number", comment: ""), exampleValue: QBEValue(144))]
			
		case .Sign, .Absolute:
			return [QBEParameter(name: NSLocalizedString("number", comment: ""), exampleValue: QBEValue(-1337))]
			
		case .Sum, .Count, .CountAll, .Average, .Min, .Max, .RandomItem:
			return [
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue(1)),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue(2)),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue(3))
			]
			
		case .Pack:
			return [
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("horse")),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("correct")),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("battery")),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("staple"))
			]
			
		case .Choose:
			return [
				QBEParameter(name: NSLocalizedString("index", comment: ""), exampleValue: QBEValue.IntValue(2)),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("horse")),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("correct")),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("battery")),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("staple"))
			]
			
		case .In, .NotIn:
			return [
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("horse")),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("correct")),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("battery")),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("horse")),
				QBEParameter(name: NSLocalizedString("value", comment: ""), exampleValue: QBEValue("staple"))
			]
			
		case .Nth:
			return [
				QBEParameter(name: NSLocalizedString("pack", comment: ""), exampleValue: QBEValue(QBEPack(["correct","horse", "battery", "staple"]).stringValue)),
				QBEParameter(name: NSLocalizedString("index", comment: ""), exampleValue: QBEValue.IntValue(2))
			]
			
		case .Items:
			return [
				QBEParameter(name: NSLocalizedString("pack", comment: ""), exampleValue: QBEValue(QBEPack(["correct","horse", "battery", "staple"]).stringValue))
			]
			
		case .Concat:
			return [
				QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("foo")),
				QBEParameter(name: NSLocalizedString("text", comment: ""), exampleValue: QBEValue("bar"))
			]
			
		case .Now, .Random:
			return []
			
		default: return nil
		}
	} }
	
	var arity: QBEArity { get {
		switch self {
		case .Uppercase: return QBEArity.Fixed(1)
		case .Lowercase: return QBEArity.Fixed(1)
		case .Negate: return QBEArity.Fixed(1)
		case .Absolute: return QBEArity.Fixed(1)
		case .Identity: return QBEArity.Fixed(1)
		case .And: return QBEArity.Any
		case .Or: return QBEArity.Any
		case .Cos: return QBEArity.Fixed(1)
		case .Sin: return QBEArity.Fixed(1)
		case .Tan: return QBEArity.Fixed(1)
		case .Cosh: return QBEArity.Fixed(1)
		case .Sinh: return QBEArity.Fixed(1)
		case .Tanh: return QBEArity.Fixed(1)
		case .Acos: return QBEArity.Fixed(1)
		case .Asin: return QBEArity.Fixed(1)
		case .Atan: return QBEArity.Fixed(1)
		case .Sqrt: return QBEArity.Fixed(1)
		case .If: return QBEArity.Fixed(3)
		case .Concat: return QBEArity.Any
		case .Left: return QBEArity.Fixed(2)
		case .Right: return QBEArity.Fixed(2)
		case .Length: return QBEArity.Fixed(1)
		case .Mid: return QBEArity.Fixed(3)
		case .Log: return QBEArity.Between(1,2)
		case .Not: return QBEArity.Fixed(1)
		case .Substitute: return QBEArity.Fixed(3)
		case .Xor: return QBEArity.Fixed(2)
		case .Trim: return QBEArity.Fixed(1)
		case .Coalesce: return QBEArity.Any
		case .IfError: return QBEArity.Fixed(2)
		case .Count: return QBEArity.Any
		case .Sum: return QBEArity.Any
		case .Average: return QBEArity.Any
		case .Max: return QBEArity.Any
		case .Min: return QBEArity.Any
		case .RandomItem: return QBEArity.Any
		case .CountAll: return QBEArity.Any
		case .Pack: return QBEArity.Any
		case .Exp: return QBEArity.Fixed(1)
		case .Ln: return QBEArity.Fixed(1)
		case .Round: return QBEArity.Between(1,2)
		case .Choose: return QBEArity.Any
		case .RandomBetween: return QBEArity.Fixed(2)
		case .Random: return QBEArity.Fixed(0)
		case .RegexSubstitute: return QBEArity.Fixed(3)
		case .NormalInverse: return QBEArity.Fixed(3)
		case .Sign: return QBEArity.Fixed(1)
		case .Split: return QBEArity.Fixed(2)
		case .Nth: return QBEArity.Fixed(2)
		case .Items: return QBEArity.Fixed(1)
		case .Levenshtein: return QBEArity.Fixed(2)
		case .URLEncode: return QBEArity.Fixed(1)
		case .In: return QBEArity.AtLeast(2)
		case .NotIn: return QBEArity.AtLeast(2)
		case .Capitalize: return QBEArity.Fixed(1)
		case .Now: return QBEArity.Fixed(0)
		case .FromUnixTime: return QBEArity.Fixed(1)
		case .ToUnixTime: return QBEArity.Fixed(1)
		case .FromISO8601: return QBEArity.Fixed(1)
		case .ToLocalISO8601: return QBEArity.Fixed(1)
		case .ToUTCISO8601: return QBEArity.Fixed(1)
		case .ToExcelDate: return QBEArity.Fixed(1)
		case .FromExcelDate: return QBEArity.Fixed(1)
		case .UTCDate: return QBEArity.Fixed(3)
		case .UTCDay: return QBEArity.Fixed(1)
		case .UTCMonth: return QBEArity.Fixed(1)
		case .UTCYear: return QBEArity.Fixed(1)
		case .UTCMinute: return QBEArity.Fixed(1)
		case .UTCHour: return QBEArity.Fixed(1)
		case .UTCSecond: return QBEArity.Fixed(1)
		case .Duration: return QBEArity.Fixed(2)
		case .After: return QBEArity.Fixed(2)
		}
	} }
	
	func apply(arguments: [QBEValue]) -> QBEValue {
		// Check arity
		if !arity.valid(arguments.count) {
			return QBEValue.InvalidValue
		}
		
		switch self {
		case .Negate:
			return -arguments[0]
			
		case .Uppercase:
			if let s = arguments[0].stringValue {
				return QBEValue(s.uppercaseString)
			}
			return QBEValue.InvalidValue
			
		case .Lowercase:
			if let s = arguments[0].stringValue {
				return QBEValue(s.lowercaseString)
			}
			return QBEValue.InvalidValue
			
		case .Absolute:
			return arguments[0].absolute
			
		case .Identity:
			return arguments[0]
			
		case .And:
			for a in arguments {
				if !a.isValid {
					return QBEValue.InvalidValue
				}
				
				if a != QBEValue(true) {
					return QBEValue(false)
				}
			}
			return QBEValue(true)
			
		case .Coalesce:
			for a in arguments {
				if a.isValid && !a.isEmpty {
					return a
				}
			}
			return QBEValue.EmptyValue
			
		case .Not:
			if let b = arguments[0].boolValue {
				return QBEValue(!b)
			}
			return QBEValue.InvalidValue
		
		case .Or:
			for a in arguments {
				if !a.isValid {
					return QBEValue.InvalidValue
				}
			}
			
			for a in arguments {
				if a == QBEValue(true) {
					return QBEValue(true)
				}
			}
			return QBEValue(false)
			
		case .Xor:
			if let a = arguments[0].boolValue {
				if let b = arguments[1].boolValue {
					return QBEValue((a != b) && (a || b))
				}
			}
			return QBEValue.InvalidValue
			
		case .Concat:
			var s: String = ""
			for a in arguments {
				if let text = a.stringValue {
					s += text
				}
				else {
					return QBEValue.InvalidValue
				}
			}
			return QBEValue(s)
			
		case .Pack:
			let pack = QBEPack(arguments)
			return QBEValue.StringValue(pack.stringValue)
			
		case .If:
			if let d = arguments[0].boolValue {
				return d ? arguments[1] : arguments[2]
			}
			return QBEValue.InvalidValue
			
		case .IfError:
			return (!arguments[0].isValid) ? arguments[1] : arguments[0]
			
		case .Cos:
			if let d = arguments[0].doubleValue {
				return QBEValue(cos(d))
			}
			return QBEValue.InvalidValue
		
		case .Ln:
			if let d = arguments[0].doubleValue {
				return QBEValue(log10(d) / log10(exp(1.0)))
			}
			return QBEValue.InvalidValue
			
		case .Exp:
			if let d = arguments[0].doubleValue {
				return QBEValue(exp(d))
			}
			return QBEValue.InvalidValue
			
		case .Log:
			if let d = arguments[0].doubleValue {
				if arguments.count == 2 {
					if let base = arguments[1].doubleValue {
						return QBEValue(log(d) / log(base))
					}
					return QBEValue.InvalidValue
				}
				return QBEValue(log10(d))
			}
			return QBEValue.InvalidValue
			
		case .Sin:
			if let d = arguments[0].doubleValue {
				return QBEValue(sin(d))
			}
			return QBEValue.InvalidValue
			
		case .Tan:
			if let d = arguments[0].doubleValue {
				return QBEValue(tan(d))
			}
			return QBEValue.InvalidValue
			
		case .Cosh:
			if let d = arguments[0].doubleValue {
				return QBEValue(cosh(d))
			}
			return QBEValue.InvalidValue
			
		case .Sinh:
			if let d = arguments[0].doubleValue {
				return QBEValue(sinh(d))
			}
			return QBEValue.InvalidValue
			
		case .Tanh:
			if let d = arguments[0].doubleValue {
				return QBEValue(tanh(d))
			}
			return QBEValue.InvalidValue
			
		case .Acos:
			if let d = arguments[0].doubleValue {
				return QBEValue(acos(d))
			}
			return QBEValue.InvalidValue
			
		case .Asin:
			if let d = arguments[0].doubleValue {
				return QBEValue(asin(d))
			}
			return QBEValue.InvalidValue
			
		case .Atan:
			if let d = arguments[0].doubleValue {
				return QBEValue(atan(d))
			}
			return QBEValue.InvalidValue
			
		case .Sqrt:
			if let d = arguments[0].doubleValue {
				return QBEValue(sqrt(d))
			}
			return QBEValue.InvalidValue
			
		case .Left:
			if let s = arguments[0].stringValue {
				if let idx = arguments[1].intValue {
					if s.characters.count >= idx {
						let index = advance(s.startIndex, idx)
						return QBEValue(s.substringToIndex(index))
					}
				}
			}
			return QBEValue.InvalidValue
			
		case .Right:
			if let s = arguments[0].stringValue {
				if let idx = arguments[1].intValue {
					if s.characters.count >= idx {
						let index = advance(s.endIndex, -idx)
						return QBEValue(s.substringFromIndex(index))
					}
				}
			}
			return QBEValue.InvalidValue
			
		case .Mid:
			if let s = arguments[0].stringValue {
				if let start = arguments[1].intValue {
					if let length = arguments[2].intValue {
						let sourceLength = s.characters.count
						if sourceLength >= start {
							let index = advance(s.startIndex, start)
							let end = sourceLength >= (start+length) ? advance(index, length) : s.endIndex
							
							return QBEValue(s.substringWithRange(Range(start: index, end: end)))
						}
					}
				}
			}
			return QBEValue.InvalidValue
			
		case .Length:
			if let s = arguments[0].stringValue {
				return QBEValue(s.characters.count)
			}
			return QBEValue.InvalidValue
			
		case .Count:
			// Count only counts the number of numeric values
			var count = 0
			arguments.each({
				if let _ = $0.doubleValue {
					count++
				}
			})
			return QBEValue(count)
			
		case .CountAll:
			// Like COUNTARGS in Excel, this function returns the number of arguments
			return QBEValue(arguments.count)
		
		case .Substitute:
			if let source = arguments[0].stringValue {
				if let replace = arguments[1].stringValue {
					if let replaceWith = arguments[2].stringValue {
						// TODO: add case-insensitive and regex versions of this
						return QBEValue(source.stringByReplacingOccurrencesOfString(replace, withString: replaceWith))
					}
				}
			}
			return QBEValue.InvalidValue
		
		case .Trim:
			if let s = arguments[0].stringValue {
				return QBEValue(s.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()))
			}
			return QBEValue.InvalidValue
			
		case .Sum:
			var sum: QBEValue = QBEValue(0)
			arguments.each({
				let s = sum + $0
				
				// SUM just ignores anything that doesn't add up
				if s.isValid {
					sum = s
				}
			})
			return sum
		
		case .Average:
			let sum = QBEFunction.Sum.apply(arguments)
			return sum / QBEValue(arguments.count)
			
		case .Min:
			var least: QBEValue? = nil
			for argument in arguments {
				if least == nil || (argument.isValid && argument < least!) {
					least = argument
				}
			}
			return least ?? QBEValue.InvalidValue
			
		case .Max:
			var least: QBEValue? = nil
			for argument in arguments {
				if least == nil || (argument.isValid && argument > least!) {
					least = argument
				}
			}
			return least ?? QBEValue.InvalidValue
			
		case .RandomItem:
			if arguments.count == 0 {
				return QBEValue.EmptyValue
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
				return QBEValue.InvalidValue
			}
			
			if let d = arguments[0].doubleValue {
				if decimals == 0 {
					return QBEValue.IntValue(Int(round(d)))
				}
				else {
					let filler = pow(10.0, Double(decimals))
					return QBEValue(round(filler * d) / filler)
				}
			}
			
			return QBEValue.InvalidValue
			
		case .Choose:
			if arguments.count < 2 {
				return QBEValue.InvalidValue
			}
			
			if let index = arguments[0].intValue {
				if index < arguments.count && index > 0 {
					return arguments[index]
				}
			}
			return QBEValue.InvalidValue
			
		case .RandomBetween:
			if let bottom = arguments[0].intValue {
				if let top = arguments[1].intValue {
					if top <= bottom {
						return QBEValue.InvalidValue
					}
					
					return QBEValue(Int.random(bottom, upper: top+1))
				}
			}
			return QBEValue.InvalidValue
			
		case .Random:
			return QBEValue(Double.random())
			
		case .RegexSubstitute:
			// Note: by default, this is case-sensitive (like .Substitute)
			if	let source = arguments[0].stringValue,
				let pattern = arguments[1].stringValue,
				let replacement = arguments[2].stringValue,
				let result = source.replace(pattern, withTemplate: replacement, caseSensitive: true) {
					return QBEValue.StringValue(result)
			}
			return QBEValue.InvalidValue
			
		case .NormalInverse:
			if	let p = arguments[0].doubleValue,
				let mu = arguments[1].doubleValue,
				let sigma = arguments[2].doubleValue {
				if p < 0.0 || p > 1.0 {
					return QBEValue.InvalidValue
				}
					
				let deviations = QBENormalDistribution().inverse(p)
				return QBEValue.DoubleValue(mu + sigma * deviations)
			}
			return QBEValue.InvalidValue
			
		case .Sign:
			if let d = arguments[0].doubleValue {
				let sign = (d==0) ? 0 : (d>0 ? 1 : -1)
				return QBEValue.IntValue(sign)
			}
			return QBEValue.InvalidValue
			
			
		case .Split:
			if let s = arguments[0].stringValue {
				let separator = (arguments.count > 1 ? arguments[1].stringValue : nil) ?? " "
				let splitted = s.componentsSeparatedByString(separator)
				let pack = QBEPack(splitted)
				return QBEValue.StringValue(pack.stringValue)
			}
			return QBEValue.InvalidValue
			
			
		case .Nth:
			if let source = arguments[0].stringValue, let index = arguments[1].intValue {
				let pack = QBEPack(source)
				let adjustedIndex = index-1
				if adjustedIndex < pack.count && adjustedIndex >= 0 {
					return QBEValue.StringValue(pack[adjustedIndex])
				}
			}
			return QBEValue.InvalidValue
			
		case .Items:
			if let source = arguments[0].stringValue {
				return QBEValue.IntValue(QBEPack(source).count)
			}
			return QBEValue.InvalidValue
			
		case .Levenshtein:
			if let a = arguments[0].stringValue, let b = arguments[1].stringValue {
				return QBEValue.IntValue(a.levenshteinDistance(b))
			}
			return QBEValue.InvalidValue
			
		case .URLEncode:
			if let s = arguments[0].stringValue, let enc = s.stringByAddingPercentEscapesUsingEncoding(NSUTF8StringEncoding) {
				return QBEValue(enc)
			}
			return QBEValue.InvalidValue
			
		case .In:
			if arguments.count < 2 {
				return QBEValue.InvalidValue
			}
			else {
				let needle = arguments[0]
				for hay in 1..<arguments.count {
					if needle == arguments[hay] {
						return QBEValue(true)
					}
				}
				return QBEValue(false)
			}
			
		case .NotIn:
			if arguments.count < 2 {
				return QBEValue.InvalidValue
			}
			else {
				let needle = arguments[0]
				for hay in 1..<arguments.count {
					if needle == arguments[hay] {
						return QBEValue(false)
					}
				}
				return QBEValue(true)
			}
			
		case .Capitalize:
			if let s = arguments[0].stringValue {
				return QBEValue.StringValue(s.capitalizedString)
			}
			return QBEValue.InvalidValue
			
		case .Now:
			return QBEValue(NSDate())
			
		case .FromUnixTime:
			if let s = arguments[0].doubleValue {
				return QBEValue(NSDate(timeIntervalSince1970: s))
			}
			return QBEValue.InvalidValue
			
		case .ToUnixTime:
			if let d = arguments[0].dateValue {
				return QBEValue(d.timeIntervalSince1970)
			}
			return QBEValue.InvalidValue
			
		case .FromISO8601:
			if let s = arguments[0].stringValue, d = NSDate.fromISO8601FormattedDate(s) {
				return QBEValue(d)
			}
			return QBEValue.InvalidValue
			
		case .ToLocalISO8601:
			if let d = arguments[0].dateValue {
				return QBEValue(d.iso8601FormattedLocalDate)
			}
			return QBEValue.InvalidValue
			
		case .ToUTCISO8601:
			if let d = arguments[0].dateValue {
				return QBEValue(d.iso8601FormattedUTCDate)
			}
			return QBEValue.InvalidValue
			
		case .ToExcelDate:
			if let d = arguments[0].dateValue, let e = d.excelDate {
				return QBEValue(e)
			}
			return QBEValue.InvalidValue
			
		case .FromExcelDate:
			if let d = arguments[0].doubleValue, let x = NSDate.fromExcelDate(d) {
				return QBEValue(x)
			}
			return QBEValue.InvalidValue
			
		case .UTCDate:
			if let year = arguments[0].intValue, let month = arguments[1].intValue, let day = arguments[2].intValue {
				return QBEValue(NSDate.startOfGregorianDateInUTC(year, month: month, day: day))
			}
			return QBEValue.InvalidValue
			
		case .UTCDay:
			if let date = arguments[0].dateValue {
				return QBEValue(date.gregorianComponentsInUTC.day)
			}
			return QBEValue.InvalidValue

		case .UTCMonth:
			if let date = arguments[0].dateValue {
				return QBEValue(date.gregorianComponentsInUTC.month)
			}
			return QBEValue.InvalidValue

		case .UTCYear:
			if let date = arguments[0].dateValue {
				return QBEValue(date.gregorianComponentsInUTC.year)
			}
			return QBEValue.InvalidValue

		case .UTCHour:
			if let date = arguments[0].dateValue {
				return QBEValue(date.gregorianComponentsInUTC.hour)
			}
			return QBEValue.InvalidValue

		case .UTCMinute:
			if let date = arguments[0].dateValue {
				return QBEValue(date.gregorianComponentsInUTC.minute)
			}
			return QBEValue.InvalidValue

		case .UTCSecond:
			if let date = arguments[0].dateValue {
				return QBEValue(date.gregorianComponentsInUTC.second)
			}
			return QBEValue.InvalidValue
			
		case .Duration:
			if let start = arguments[0].dateValue, let end = arguments[1].dateValue {
				return QBEValue(end.timeIntervalSinceReferenceDate - start.timeIntervalSinceReferenceDate)
			}
			return QBEValue.InvalidValue
			
		case .After:
			if let start = arguments[0].dateValue, let duration = arguments[1].doubleValue {
				return QBEValue(NSDate(timeInterval: duration, sinceDate: start))
			}
			return QBEValue.InvalidValue
		}
	}
	
	static let allFunctions = [
		Uppercase, Lowercase, Negate, Absolute, And, Or, Acos, Asin, Atan, Cosh, Sinh, Tanh, Cos, Sin, Tan, Sqrt, Concat,
		If, Left, Right, Mid, Length, Substitute, Count, Sum, Trim, Average, Min, Max, RandomItem, CountAll, Pack, IfError,
		Exp, Log, Ln, Round, Choose, Random, RandomBetween, RegexSubstitute, NormalInverse, Sign, Split, Nth, Items,
		Levenshtein, URLEncode, In, NotIn, Not, Capitalize, Now, ToUnixTime, FromUnixTime, FromISO8601, ToLocalISO8601,
		ToUTCISO8601, ToExcelDate, FromExcelDate, UTCDate, UTCDay, UTCMonth, UTCYear, UTCHour, UTCMinute, UTCSecond,
		Duration, After, Xor
	]
}

enum QBEBinary: String {
	case Addition = "add"
	case Subtraction = "sub"
	case Multiplication = "mul"
	case Division = "div"
	case Modulus = "mod"
	case Concatenation = "cat"
	case Power = "pow"
	case Greater = "gt"
	case Lesser = "lt"
	case GreaterEqual = "gte"
	case LesserEqual = "lte"
	case Equal = "eq"
	case NotEqual = "neq"
	case ContainsString = "contains" // case-insensitive
	case ContainsStringStrict = "containsStrict" // case-sensitive
	case MatchesRegex = "matchesRegex" // not case-sensitive
	case MatchesRegexStrict = "matchesRegexStrict" // case-sensitive
	
	func explain(locale: QBELocale) -> String {
		switch self {
		case .Addition: return "+"
		case .Subtraction: return "-"
		case .Multiplication: return "*"
		case .Division: return "/"
		case .Modulus: return "%"
		case .Concatenation: return "&"
		case .Power: return "^"
		case .Greater: return ">"
		case .Lesser: return "<"
		case .GreaterEqual: return ">="
		case .LesserEqual: return "<="
		case .Equal: return "="
		case .NotEqual: return "<>"
		case .ContainsString: return "~="
		case .ContainsStringStrict: return "~~="
		case .MatchesRegex: return "±="
		case .MatchesRegexStrict: return "±±="
		}
	}
	
	func toFormula(locale: QBELocale) -> String {
		return self.explain(locale)
	}
	
	func apply(left: QBEValue, _ right: QBEValue) -> QBEValue {
		switch self {
		case .Addition:
			return left + right
			
		case .Subtraction:
			return left - right
			
		case .Multiplication:
			return left * right
			
		case .Modulus:
			return left % right
			
		case .Division:
			return left / right
			
		case .Concatenation:
			return left & right
			
		case .Power:
			return left ^ right
			
		case Greater:
			return left > right
			
		case Lesser:
			return left < right
			
		case GreaterEqual:
			return left >= right
			
		case LesserEqual:
			return left <= right
			
		case Equal:
			return left == right
			
		case NotEqual:
			return left != right
			
		case .ContainsString:
			return left ~= right
			
		case .ContainsStringStrict:
			return left ~~= right
			
		case .MatchesRegex:
			return left ±= right
			
		case .MatchesRegexStrict:
			return left ±±= right
		}
	}
}
