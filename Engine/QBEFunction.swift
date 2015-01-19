import Foundation

enum QBEArity: Equatable {
	case Fixed(Int)
	case Between(Int, Int)
	case Any
	
	func valid(count: Int) -> Bool {
		switch self {
		case .Fixed(let i):
			return count == i
		
		case .Between(let a, let b):
			return count >= a && count <= b
			
		case .Any:
			return true
		}
	}
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
	
	var description: String { get {
		switch self {
		case .Uppercase: return NSLocalizedString("uppercase", comment: "")
		case .Lowercase: return NSLocalizedString("lowercase", comment:"")
		case .Negate: return NSLocalizedString("-", comment:"")
		case .Absolute: return NSLocalizedString("absolute", comment:"")
		case .Identity: return NSLocalizedString("", comment:"")
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
		case .Count: return NSLocalizedString("count", comment: "")
		case .Sum: return NSLocalizedString("sum of", comment: "")
		case .Average: return NSLocalizedString("average of", comment: "")
		case .Min: return NSLocalizedString("lowest", comment: "")
		case .Max: return NSLocalizedString("highest", comment: "")
		case .RandomItem: return NSLocalizedString("random item", comment: "")
		case .CountAll: return NSLocalizedString("number of items", comment: "")
		case .Pack: return NSLocalizedString("pack", comment: "")
		}
	} }
	
	func toFormula(locale: QBELocale) -> String {
		for (name, function) in locale.functions {
			if function == self {
				return name
			}
		}
		return ""
	}
	
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
			return arguments[0].absolute()
			
		case .Identity:
			return arguments[0]
			
		case .And:
			for a in arguments {
				if a != QBEValue(true) {
					return QBEValue(false)
				}
			}
			return QBEValue(true)
			
		case .Coalesce:
			for a in arguments {
				if a != QBEValue.EmptyValue && a != QBEValue.InvalidValue {
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
			let res = arguments.map({
				$0.stringValue?.stringByReplacingOccurrencesOfString(QBEPackEscape, withString: QBEPackEscapeEscape).stringByReplacingOccurrencesOfString(QBEPackSeparator, withString: QBEPackSeparatorEscape) ?? ""
			})
			
			return QBEValue.StringValue(res.implode(QBEPackSeparator) ?? "")
			
		case .If:
			if let d = arguments[0].boolValue {
				return d ? arguments[1] : arguments[2]
			}
			return QBEValue.InvalidValue
			
		case .IfError:
			return (arguments[0] == QBEValue.InvalidValue) ? arguments[1] : arguments[0]
			
		case .Cos:
			if let d = arguments[0].doubleValue {
				return QBEValue(cos(d))
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
					if countElements(s) >= idx {
						let index = advance(s.startIndex, idx)
						return QBEValue(s.substringToIndex(index))
					}
				}
			}
			return QBEValue.InvalidValue
			
		case .Right:
			if let s = arguments[0].stringValue {
				if let idx = arguments[1].intValue {
					if countElements(s) >= idx {
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
						let sourceLength = countElements(s)
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
				return QBEValue(countElements(s))
			}
			return QBEValue.InvalidValue
			
		case .Count:
			// Count only counts the number of numeric values
			var count = 0
			arguments.each({
				if let d = $0.doubleValue {
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
			var sum = QBEFunction.Sum.apply(arguments)
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
		}
	}
	
	static let allFunctions = [
		Uppercase, Lowercase, Negate, Absolute, And, Or, Acos, Asin, Atan, Cosh, Sinh, Tanh, Cos, Sin, Tan, Sqrt, Concat,
		If, Left, Right, Mid, Length, Substitute, Count, Sum, Trim, Average, Min, Max, RandomItem, CountAll, Pack, IfError
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
	
	var description: String { get {
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
		}
	} }
	
	func toFormula(locale: QBELocale) -> String {
		return self.description
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
		}
	}
}
