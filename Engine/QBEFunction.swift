import Foundation

enum QBEArity {
	case Fixed(Int)
	case Any
	
	func valid(count: Int) -> Bool {
		switch self {
		case .Fixed(let i):
			return count == i
			
		case .Any:
			return true
		}
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
		}
	} }
	
	func toFormula(locale: QBELocale) -> String {
		for (name, function) in locale.unaryFunctions {
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
		}
	} }
	
	func apply(arguments: [QBEValue]) -> QBEValue {
		// Check arity
		if !arity.valid(arguments.count) {
			return QBEValue()
		}
		
		switch self {
		case .Negate:
			return -arguments[0]
			
		case .Uppercase:
			return QBEValue(arguments[0].stringValue.uppercaseString)
			
		case .Lowercase:
			return QBEValue(arguments[0].stringValue.lowercaseString)
			
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
		
		case .Or:
		for a in arguments {
			if a == QBEValue(true) {
				return QBEValue(true)
			}
		}
		return QBEValue(false)
			
		case .Concat:
			var s: String = ""
			for a in arguments {
				s += a.stringValue
			}
			return QBEValue(s)
	
		case .If:
			if let d = arguments[0].boolValue {
				return d ? arguments[1] : arguments[2]
			}
			return QBEValue()
			
		case .Cos:
			if let d = arguments[0].doubleValue {
				return QBEValue(cos(d))
			}
			return QBEValue()
			
		case .Sin:
			if let d = arguments[0].doubleValue {
				return QBEValue(sin(d))
			}
			return QBEValue()
			
		case .Tan:
			if let d = arguments[0].doubleValue {
				return QBEValue(tan(d))
			}
			return QBEValue()
			
		case .Cosh:
			if let d = arguments[0].doubleValue {
				return QBEValue(cosh(d))
			}
			return QBEValue()
			
		case .Sinh:
			if let d = arguments[0].doubleValue {
				return QBEValue(sinh(d))
			}
			return QBEValue()
			
		case .Tanh:
			if let d = arguments[0].doubleValue {
				return QBEValue(tanh(d))
			}
			return QBEValue()
			
		case .Acos:
			if let d = arguments[0].doubleValue {
				return QBEValue(acos(d))
			}
			return QBEValue()
			
		case .Asin:
			if let d = arguments[0].doubleValue {
				return QBEValue(asin(d))
			}
			return QBEValue()
			
		case .Atan:
			if let d = arguments[0].doubleValue {
				return QBEValue(atan(d))
			}
			return QBEValue()
			
		case .Sqrt:
			if let d = arguments[0].doubleValue {
				return QBEValue(sqrt(d))
			}
			return QBEValue()
		}
	}
	
	static let allFunctions = [Uppercase, Lowercase, Negate, Absolute, And, Or, Acos, Asin, Atan, Cosh, Sinh, Tanh, Cos, Sin, Tan, Sqrt, Concat, If]
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
