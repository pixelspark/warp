import Foundation

let QBEFunctions: [QBEFunction.Type] = [
	QBESiblingFunction.self,
	QBEMultiplicationFunction.self,
	QBESubstituteFunction.self,
	QBEAdditionFunction.self,
	QBEUppercaseFunction.self,
	QBELowercaseFunction.self,
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
			
			// Which characters are missing from the in value, but present in the out value?
			var missingInRight: [Character] = []
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
		return raster[rowNumber, raster.indexOfColumnWithName(columnName)!]
	}
	
	override class func suggest(fromValue: QBEValue?, toValue: QBEValue, raster: QBERaster, row: Int) -> [QBEFunction] {
		var s: [QBEFunction] = []
		if fromValue != nil {
			return s
		}
		
		for columnName in raster.columnNames {
			let sourceValue = raster[row, raster.indexOfColumnWithName(columnName)!]
			s.append(QBESiblingFunction(columnName: columnName))
		}
		
		return s
	}
}
