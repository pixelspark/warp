import Foundation

let QBEFunctions: [QBEFunction.Type] = [
	QBESiblingFunction.self,
	QBEMultiplicationFunction.self,
	QBESubstituteFunction.self,
	QBEAdditionFunction.self,
	QBEUppercaseFunction.self,
	QBELowercaseFunction.self,
	QBELiteralFunction.self,
	QBENegateFunction.self,
	QBEIdentityFunction.self
]

class QBEFunction: NSObject, NSCoding {
	var explanation: String { get {
		return "??"
		}}
	
	var complexity: Int { get {
		return 1
		}}
	
	override init() {
	}
	
	required init(coder aDecoder: NSCoder) {
	}
	
	func encodeWithCoder(aCoder: NSCoder) {
	}
	
	func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		fatalError("A QBEFunction was called that isn't implemented")
	}
	
	class func suggest(fromValue: QBEValue?, toValue: QBEValue, raster: QBERaster, row: Int) -> [QBEFunction] {
		return []
	}
}

class QBELiteralFunction: QBEFunction {
	let value: QBEValue
	
	init(_ value: QBEValue) {
		self.value = value
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		self.value = aDecoder.decodeObjectForKey("value") as? QBEValue ?? QBEValue()
		super.init(coder: aDecoder)
	}
	
	override var explanation: String { get {
		return value.stringValue
	} }
	
	override func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(self.value(), forKey: "value")
		super.encodeWithCoder(aCoder)
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		return value
	}
	
	override class func suggest(fromValue: QBEValue?, toValue: QBEValue, raster: QBERaster, row: Int) -> [QBEFunction] {
		if fromValue == nil {
			return [QBELiteralFunction(toValue)]
		}
		return []
	}
}

class QBEIdentityFunction: QBEFunction {
	override init() {
		super.init()
	}
	
	override var explanation: String { get {
		return NSLocalizedString("value", comment: "")
		}}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		return inputValue ?? QBEValue()
	}
}

class QBEAdditionFunction: QBEFunction {
	var addendum: Int
	
	init(addendum: Int) {
		self.addendum = addendum
		super.init()
	}
	
	override var explanation: String { get {
		return NSLocalizedString("add", comment: "") + " \(addendum) " + NSLocalizedString("to", comment: "") + " "
		}}
	
	required init(coder aDecoder: NSCoder) {
		addendum = aDecoder.decodeIntegerForKey("addendum")
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeInteger(addendum, forKey: "addendum")
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		if let i = inputValue?.intValue {
			return QBEValue(i + addendum)
		}
		return QBEValue()
	}
	
	override class func suggest(fromValue: QBEValue?, toValue: QBEValue, raster: QBERaster, row: Int) -> [QBEFunction] {
		if fromValue != nil {
			if let f = fromValue!.intValue {
				if let t = toValue.intValue {
					if f != t {
						return [QBEAdditionFunction(addendum: t-f)]
					}
				}
			}
		}
		return []
	}
}

class QBEMultiplicationFunction: QBEFunction {
	var multiplicant: Int
	
	init(multiplicant: Int) {
		self.multiplicant = multiplicant
		super.init()
	}
	
	override var explanation: String { get {
		return "\(multiplicant) " + NSLocalizedString("times", comment: "")
		}}
	
	required init(coder aDecoder: NSCoder) {
		multiplicant = aDecoder.decodeIntegerForKey("multiplicant")
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeInteger(multiplicant, forKey: "multiplicant")
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		if let i = inputValue?.intValue {
			return QBEValue(i * multiplicant)
		}
		return QBEValue()
	}
	
	override class func suggest(fromValue: QBEValue?, toValue: QBEValue, raster: QBERaster, row: Int) -> [QBEFunction] {
		if fromValue != nil {
			if let f = fromValue!.intValue {
				if let t = toValue.intValue {
					if f != t && f>0 {
						return [QBEMultiplicationFunction(multiplicant: t/f)]
					}
				}
			}
		}
		return []
	}
}

class QBEUppercaseFunction: QBEFunction {
	override init() {
		super.init()
	}
	
	override var explanation: String { get {
		return NSLocalizedString("uppercased", comment: "")
		}}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		return QBEValue(inputValue?.description.uppercaseString ?? "")
	}
	
	override class func suggest(fromValue: QBEValue?, toValue: QBEValue, raster: QBERaster, row: Int) -> [QBEFunction] {
		if fromValue?.description.uppercaseString == toValue.description.uppercaseString {
			return [QBEUppercaseFunction()]
		}
		return []
	}
}

class QBELowercaseFunction: QBEFunction {
	override var explanation: String { get {
		return NSLocalizedString("lowercased", comment: "")
		}}
	
	override init() {
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		return QBEValue(inputValue?.description.lowercaseString ?? "")
	}
	
	override class func suggest(fromValue: QBEValue?, toValue: QBEValue, raster: QBERaster, row: Int) -> [QBEFunction] {
		if fromValue?.description.lowercaseString == toValue.description.lowercaseString {
			return [QBELowercaseFunction()]
		}
		return []
	}
}

class QBENegateFunction: QBEFunction {
	override var explanation: String { get {
		return NSLocalizedString("-", comment: "")
		}}
	
	override init() {
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		return -(inputValue ?? QBEValue())
	}
	
	override class func suggest(fromValue: QBEValue?, toValue: QBEValue, raster: QBERaster, row: Int) -> [QBEFunction] {
		if let f = fromValue {
			if toValue == -f {
				return [QBENegateFunction()]
			}
		}
		return []
	}
}

extension String {
	func histogram() -> [Character: Int] {
		var histogram = Dictionary<Character, Int>()
		
		for ch in self {
			let old: Int = histogram[ch] ?? 0
			histogram[ch] = old+1
		}
		
		return histogram
	}
}

class QBESubstituteFunction: QBEFunction {
	var replaceValue: String
	var withValue: String
	
	override var explanation: String { get {
		return NSLocalizedString("substitute", comment: "")+" '\(replaceValue)' "+NSLocalizedString("with",comment:"")+" '\(withValue)'"
		}}
	
	init(replaceValue: String, withValue: String) {
		self.replaceValue = replaceValue
		self.withValue = withValue
		super.init()
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(replaceValue, forKey: "replaceValue")
		aCoder.encodeObject(withValue, forKey: "withValue")
	}
	
	required init(coder aDecoder: NSCoder) {
		replaceValue = aDecoder.decodeObjectForKey("replaceValue") as? String ?? ""
		withValue = aDecoder.decodeObjectForKey("withValue") as? String ?? ""
		super.init(coder: aDecoder)
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		return QBEValue(inputValue?.stringValue.stringByReplacingOccurrencesOfString(replaceValue, withString: withValue) ?? "")
	}
	
	override class func suggest(fromValue: QBEValue?, toValue: QBEValue, raster: QBERaster, row: Int) -> [QBEFunction] {
		let leftHistogram = fromValue?.stringValue.histogram()
		let rightHistogram = toValue.stringValue.histogram()
		
		if leftHistogram != nil {
			// Which characters are missing from the out value, but present in the in value?
			var missingInLeft: [Character] = []
			for lch in rightHistogram.keys {
				if leftHistogram![lch]==nil {
					missingInLeft.append(lch)
				}
			}
			
			// Suggest some replacements...
			var suggestions: [QBEFunction] = []
			
			// Don't spend too much time searching for weird replacements
			if missingInLeft.count > 1 {
				return []
			}
			
			// Which characters are missing from the in value, but present in the out value?
			for lch in leftHistogram!.keys {
				if rightHistogram[lch]==nil {
					for rch in missingInLeft {
						// Don't suggest a substitution for uppercase/lowercase conversions
						let leftCharacterString = String(lch)
						let rightCharacterString = String(rch)
						
						if leftCharacterString.uppercaseString != rightCharacterString.uppercaseString {
							suggestions.append(QBESubstituteFunction(replaceValue: String(lch), withValue: String(rch)))
						}
					}
				}
			}
			
			return suggestions
		}
		
		return []
	}
}

class QBECompoundFunction: QBEFunction {
	var first: QBEFunction
	var second: QBEFunction
	
	override var explanation: String { get {
		return second.explanation + " " + first.explanation
		}}
	
	override var complexity: Int { get {
		return first.complexity + second.complexity + 1
		}}
	
	init(first: QBEFunction, second: QBEFunction) {
		self.first = first
		self.second = second
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		self.first = aDecoder.decodeObjectForKey("first") as? QBEFunction ?? QBEIdentityFunction()
		self.second = aDecoder.decodeObjectForKey("second") as? QBEFunction ?? QBEIdentityFunction()
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(first, forKey: "first")
		aCoder.encodeObject(second, forKey: "second")
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		return second.apply(raster, rowNumber: rowNumber, inputValue: first.apply(raster, rowNumber: rowNumber, inputValue: inputValue))
	}
	
	override class func suggest(fromValue: QBEValue?, toValue: QBEValue, raster: QBERaster, row: Int) -> [QBEFunction] {
		return []
	}
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

class QBEBinaryFunction: QBEFunction {
	var first: QBEFunction
	var second: QBEFunction
	var type: QBEBinary
	
	override var explanation: String { get {
		return "(" + second.explanation + " " + type.description + " " + first.explanation + ")"
		}}
	
	override var complexity: Int { get {
		return first.complexity + second.complexity + 1
		}}
	
	init(first: QBEFunction, second: QBEFunction, type: QBEBinary) {
		self.first = first
		self.second = second
		self.type = type
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		self.first = aDecoder.decodeObjectForKey("first") as? QBEFunction ?? QBEIdentityFunction()
		self.second = aDecoder.decodeObjectForKey("second") as? QBEFunction ?? QBEIdentityFunction()
		let typeString = aDecoder.decodeObjectForKey("type") as? String ?? QBEBinary.Addition.rawValue
		self.type = QBEBinary(rawValue: typeString) ?? QBEBinary.Addition
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(first, forKey: "first")
		aCoder.encodeObject(second, forKey: "second")
		aCoder.encodeObject(type.rawValue, forKey: "type")
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		let left = second.apply(raster, rowNumber: rowNumber, inputValue: nil)
		let right = first.apply(raster, rowNumber: rowNumber, inputValue: nil)
		return self.type.apply(left, right)
	}
	
	override class func suggest(fromValue: QBEValue?, toValue: QBEValue, raster: QBERaster, row: Int) -> [QBEFunction] {
		return []
	}
}

class QBESiblingFunction: QBEFunction {
	var columnName: String
	
	init(columnName: String) {
		self.columnName = columnName
		super.init()
	}
	
	override var explanation: String { get {
		return NSLocalizedString("value in column", comment: "")+" "+columnName
		}}
	
	required init(coder aDecoder: NSCoder) {
		columnName = (aDecoder.decodeObjectForKey("columnName") as? String) ?? ""
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(columnName, forKey: "columnName")
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		if let idx = raster.indexOfColumnWithName(columnName) {
			return raster[rowNumber, idx]
		}
		return QBEValue()
	}
	
	override class func suggest(fromValue: QBEValue?, toValue: QBEValue, raster: QBERaster, row: Int) -> [QBEFunction] {
		var s: [QBEFunction] = []
		if fromValue == nil {
			for columnName in raster.columnNames {
				let sourceValue = raster[row, raster.indexOfColumnWithName(columnName)!]
				s.append(QBESiblingFunction(columnName: columnName))
			}
		}
		return s
	}
}
