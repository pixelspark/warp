import Foundation

let QBEExpressions: [QBEExpression.Type] = [
	QBESiblingExpression.self,
	QBELiteralExpression.self,
	QBEFunctionExpression.self,
	QBEIdentityExpression.self
]

class QBEExpression: NSObject, NSCoding {
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
	
	func toFormula(locale: QBELocale) -> String {
		return ""
	}
	
	func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		fatalError("A QBEExpression was called that isn't implemented")
	}
	
	class func suggest(fromValue: QBEExpression?, toValue: QBEValue, raster: QBERaster, row: Int, inputValue: QBEValue?) -> [QBEExpression] {
		return []
	}
}

class QBELiteralExpression: QBEExpression {
	let value: QBEValue
	
	init(_ value: QBEValue) {
		self.value = value
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		self.value = (aDecoder.decodeObjectForKey("value") as? QBEValueCoder ?? QBEValueCoder()).value
		super.init(coder: aDecoder)
	}
	
	override var explanation: String { get {
		return value.stringValue
	} }
	
	override func toFormula(locale: QBELocale) -> String {
		switch value {
		case .StringValue(let s):
			let escaped = value.stringValue.stringByReplacingOccurrencesOfString(String(locale.stringQualifier), withString: locale.stringQualifierEscape)
			return "\(locale.stringQualifier)\(escaped)\(locale.stringQualifier)"
			
		case .DoubleValue(let d):
			// FIXME: needs to use decimalSeparator from locale
			return "\(d)"
			
		case .BoolValue(let b):
			return locale.constants[QBEValue(b)] ?? ""
			
		case .IntValue(let i):
			return "\(i)"
			
		case .EmptyValue: return ""
		}
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(QBEValueCoder(self.value), forKey: "value")
		super.encodeWithCoder(aCoder)
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		return value
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, raster: QBERaster, row: Int, inputValue: QBEValue?) -> [QBEExpression] {
		if fromValue == nil {
			return [QBELiteralExpression(toValue)]
		}
		return []
	}
}

class QBEIdentityExpression: QBEExpression {
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

class QBEBinaryExpression: QBEExpression {
	var first: QBEExpression
	var second: QBEExpression
	var type: QBEBinary
	
	override var explanation: String { get {
		return "(" + second.explanation + " " + type.description + " " + first.explanation + ")"
		}}
	
	override func toFormula(locale: QBELocale) -> String {
		return "(\(second.toFormula(locale)) \(type.toFormula(locale)) \(first.toFormula(locale)))"
	}
	
	override var complexity: Int { get {
		return first.complexity + second.complexity + 1
		}}
	
	init(first: QBEExpression, second: QBEExpression, type: QBEBinary) {
		self.first = first
		self.second = second
		self.type = type
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		self.first = aDecoder.decodeObjectForKey("first") as? QBEExpression ?? QBEIdentityExpression()
		self.second = aDecoder.decodeObjectForKey("second") as? QBEExpression ?? QBEIdentityExpression()
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
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, raster: QBERaster, row: Int, inputValue: QBEValue?) -> [QBEExpression] {
		return []
	}
}

class QBEFunctionExpression: QBEExpression {
	var arguments: [QBEExpression]
	var type: QBEFunction
	
	override var explanation: String { get {
		let argumentsList = arguments.map({(a) -> String in return a.explanation}).implode(", ") ?? ""
		return "\(type.description)(\(argumentsList))"
	}}
	
	override func toFormula(locale: QBELocale) -> String {
		let args = arguments.map({(i) -> String in i.toFormula(locale)}).implode(locale.argumentSeparator) ?? ""
		return "\(type.toFormula(locale))(\(args))"
	}
	
	override var complexity: Int { get {
		var complexity = 1
		for a in arguments {
			complexity = max(complexity, a.complexity)
		}
		
		return complexity + 1
	}}
	
	init(arguments: [QBEExpression], type: QBEFunction) {
		self.arguments = arguments
		self.type = type
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		self.arguments = aDecoder.decodeObjectForKey("args") as? [QBEExpression] ?? []
		let typeString = aDecoder.decodeObjectForKey("type") as? String ?? QBEFunction.Identity.rawValue
		self.type = QBEFunction(rawValue: typeString) ?? QBEFunction.Identity
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(arguments, forKey: "args")
		aCoder.encodeObject(type.rawValue, forKey: "type")
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		let vals = arguments.map({(a) -> QBEValue in return a.apply(raster, rowNumber: rowNumber, inputValue: inputValue)})
		return self.type.apply(vals)
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, raster: QBERaster, row: Int, inputValue: QBEValue?) -> [QBEExpression] {
		if let from = fromValue {
			if let f = fromValue?.apply(raster, rowNumber: row, inputValue: inputValue) {
				var suggestions: [QBEExpression] = []
			
				for op in QBEFunction.allFunctions {
					if(op.arity.valid(1)) {
						if op.apply([f]) == toValue {
							suggestions.append(QBEFunctionExpression(arguments: [from], type: op))
						}
					}
				}
				return suggestions
			}
		}
		return []
	}
}

class QBESiblingExpression: QBEExpression {
	var columnName: QBEColumn
	
	init(columnName: QBEColumn) {
		self.columnName = columnName
		super.init()
	}
	
	override var explanation: String { get {
		return NSLocalizedString("value in column", comment: "")+" "+columnName.name
		}}
	
	required init(coder aDecoder: NSCoder) {
		columnName = QBEColumn((aDecoder.decodeObjectForKey("columnName") as? String) ?? "")
		super.init(coder: aDecoder)
	}
	
	override func toFormula(locale: QBELocale) -> String {
		return "[@\(columnName.name)]"
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(columnName.name, forKey: "columnName")
	}
	
	override func apply(raster: QBERaster, rowNumber: Int, inputValue: QBEValue?) -> QBEValue {
		if let idx = raster.indexOfColumnWithName(columnName) {
			return raster[rowNumber, idx]
		}
		return QBEValue()
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, raster: QBERaster, row: Int, inputValue: QBEValue?) -> [QBEExpression] {
		var s: [QBEExpression] = []
		if fromValue == nil {
			for columnName in raster.columnNames {
				let sourceValue = raster[row, raster.indexOfColumnWithName(columnName)!]
				s.append(QBESiblingExpression(columnName: columnName))
			}
		}
		return s
	}
}