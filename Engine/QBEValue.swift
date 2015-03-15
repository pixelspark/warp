import Foundation

internal extension String {
	func toDouble() -> Double? {
		if self.isEmpty || self.hasPrefix(" ") {
			return nil
		}
		
		return self.withCString() { p -> Double? in
			var end: UnsafeMutablePointer<Int8> = nil
			let result = strtod(p, &end)
			return end.memory != 0 ? nil : result
		}
	}
	
	func histogram() -> [Character: Int] {
		var histogram = Dictionary<Character, Int>()
		
		for ch in self {
			let old: Int = histogram[ch] ?? 0
			histogram[ch] = old+1
		}
		
		return histogram
	}
}

internal extension ArraySlice {
	func each(call: (Element) -> ()) {
		for item in self {
			call(item)
		}
	}
}

internal extension Array {
	func implode<C: ExtensibleCollectionType>(separator: C) -> C? {
		if Element.self is C.Type {
			return Swift.join(separator, unsafeBitCast(self, [C].self))
		}
		
		return nil
	}
	
	func each(call: (Element) -> ()) {
		for item in self {
			call(item)
		}
	}
	
	mutating func remove <U: Equatable> (element: U) {
		let anotherSelf = self
		removeAll(keepCapacity: true)
		
		anotherSelf.each {
			(current: Element) in
			if (current as! U) != element {
				self.append(current)
			}
		}
	}
	
	mutating func removeObjectsAtIndexes(indexes: NSIndexSet, offset: Int) {
		for var i = indexes.lastIndex; i != NSNotFound; i = indexes.indexLessThanIndex(i) {
			self.removeAtIndex(i+offset)
		}
	}
	
	func objectsAtIndexes(indexes: NSIndexSet) -> [T] {
		var items: [T] = []
		
		indexes.enumerateIndexesUsingBlock {(idx, stop) -> () in
			items.append(self[idx])
		}
		
		return items
	}
	
	func contains<T: Equatable>(value: T) -> Bool {
		for i in self {
			if (i as? T) == value {
				return true
			}
		}
		return false
	}
}

internal extension Double {
	func toString() -> String {
		return String(format: "%.1f",self)
	}
}

internal extension Bool {
	func toString() -> String {
		return self ? "1" : "0"
	}
	
	func toDouble() -> Double {
		return self ? 1.0 : 0.0;
	}
	
	func toInt() -> Int {
		return self ? 1 : 0;
	}
}

internal extension Int {
	func toString() -> String {
		return String(self)
	}
	
	func toDouble() -> Double {
		return Double(self)
	}
	
	static func random(range: Range<Int>) -> Int {
		var offset = 0
		
		if range.startIndex < 0   // allow negative ranges
		{
			offset = abs(range.startIndex)
		}
		
		let mini = UInt32(range.startIndex + offset)
		let maxi = UInt32(range.endIndex   + offset)
		
		return Int(mini + arc4random_uniform(maxi - mini)) - offset
	}
}

internal func arc4random <T: IntegerLiteralConvertible> (type: T.Type) -> T {
	var r: T = 0
	arc4random_buf(&r, sizeof(T))
	return r
}

internal extension UInt64 {
	static func random(lower: UInt64 = min, upper: UInt64 = max) -> UInt64 {
		var m: UInt64
		let u = upper - lower
		var r = arc4random(UInt64)
		
		if u > UInt64(Int64.max) {
			m = 1 + ~u
		} else {
			m = ((max - (u * 2)) + 1) % u
		}
		
		while r < m {
			r = arc4random(UInt64)
		}
		
		return (r % u) + lower
	}
}

internal extension Int64 {
	static func random(lower: Int64 = min, upper: Int64 = max) -> Int64 {
		let (s, overflow) = Int64.subtractWithOverflow(upper, lower)
		let u = overflow ? UInt64.max - UInt64(~s) : UInt64(s)
		let r = UInt64.random(upper: u)
		
		if r > UInt64(Int64.max)  {
			return Int64(r - (UInt64(~lower) + 1))
		} else {
			return Int64(r) + lower
		}
	}
}

internal extension UInt32 {
	static func random(lower: UInt32 = min, upper: UInt32 = max) -> UInt32 {
		return arc4random_uniform(upper - lower) + lower
	}
}

internal extension Int32 {
	static func random(lower: Int32 = min, upper: Int32 = max) -> Int32 {
		let r = arc4random_uniform(UInt32(Int64(upper) - Int64(lower)))
		return Int32(Int64(r) + Int64(lower))
	}
}

internal extension UInt {
	static func random(lower: UInt = min, upper: UInt = max) -> UInt {
		switch (__WORDSIZE) {
			case 32: return UInt(UInt32.random(lower: UInt32(lower), upper: UInt32(upper)))
			case 64: return UInt(UInt64.random(lower: UInt64(lower), upper: UInt64(upper)))
			default: return lower
		}
	}
}

internal extension Int {
	static func random(lower: Int = min, upper: Int = max) -> Int {
		switch (__WORDSIZE) {
			case 32: return Int(Int32.random(lower: Int32(lower), upper: Int32(upper)))
			case 64: return Int(Int64.random(lower: Int64(lower), upper: Int64(upper)))
			default: return lower
		}
	}
}

internal extension Double {
	static func random() -> Double {
		return Double(Int64.random(lower: 0, upper: Int64.max)) / Double(Int64.max)
	}
}

/** QBEValue is used to represent all values in data sets. Although QBEValue can represent values of different types,
values of different types can usually easily be converted to another type. QBEValue closely models the way values are
handled in Excel and SQL (striving for a greatest common denominator where possible). QBEValue supports four data types
(string, integer, boolean and double) and two special types: 'empty' indicates a value that is intentionally empty (but
should not trigger an error and is for instance equal to an empty string and 0 in some calculations) and 'invalid' (which
represents the result of an invalid operation and should trigger subsequent operations on the value to also return 
'invalid'). 

Note that while QBEValue is an enum, it cannot be encoded using NSCoding. Wrap QBEValues inside QBEValueCoder before 
encoding or decoding using NSCoding. **/
internal enum QBEValue: Hashable, DebugPrintable {
	case StringValue(String)
	case IntValue(Int)
	case BoolValue(Bool)
	case DoubleValue(Double)
	case EmptyValue		// Any empty value that has no specific type. Equivalent to "" (empty string)
	case InvalidValue	// The result of any invalid operation (e.g. division by zero). Treat as NaN
	
	init(_ value: String) {
		self = .StringValue(value)
	}
	
	init(_ value: Double) {
		if isnan(value) || isinf(value) {
			self = .InvalidValue
		}
		else {
			self = .DoubleValue(value)
		}
	}
	
	init(_ value: Int) {
		self = .IntValue(value)
	}
	
	init(_ value: Bool) {
		self = .BoolValue(value)
	}
	
	var hashValue: Int { get  {
		return self.stringValue?.hashValue ?? 0
	}}
	
	var stringValue: String? { get {
		switch self {
		case .StringValue(let s): return s
		case .IntValue(let i): return i.toString()
		case .BoolValue(let b): return b.toString()
		case .DoubleValue(let d): return d.toString()
		case .EmptyValue: return nil
		case .InvalidValue: return nil
		}
	} }
	
	var doubleValue: Double? { get {
		switch self {
			case .StringValue(let s): return s.toDouble()
			case .IntValue(let i): return i.toDouble()
			case .BoolValue(let b): return b.toDouble()
			case .DoubleValue(let d): return d
			case .EmptyValue: return nil
			case .InvalidValue: return nil
		}
	} }
	
	var intValue: Int? { get {
		switch self {
			case .StringValue(let s): return s.toInt()
			case .IntValue(let i): return i
			case .BoolValue(let b): return b.toInt()
			case .DoubleValue(let d): return Int(d)
			case .EmptyValue: return nil
			case .InvalidValue: return nil
		}
	} }
	
	var boolValue: Bool? { get {
		switch self {
		case .StringValue(let s): return s.toInt() == 1
		case .IntValue(let i): return i == 1
		case .BoolValue(let b): return b
		case .DoubleValue(let d): return nil
		case .EmptyValue: return nil
		case .InvalidValue: return nil
		}
	} }
	
	var debugDescription: String { get {
		switch self {
		case .StringValue(let s): return "QBEValue.String('\(s)')"
		case .IntValue(let i): return "QBEValue.Int(\(i))"
		case .BoolValue(let b): return "QBEValue.Bool(\(b))"
		case .DoubleValue(let d): return "QBEValue.Double(\(d))"
		case .EmptyValue: return "QBEValue.Empty"
		case .InvalidValue: return "QBEValue.Invalid"
		}
	} }
	
	func absolute() -> QBEValue {
		return (self < QBEValue(0)) ? -self : self
	}
	
	var isValid: Bool { get {
		switch self {
			case .InvalidValue: return false
			default: return true
		}
	} }
	
	var isEmpty: Bool { get {
		switch self {
			case .EmptyValue:
				return true
				
			default:
				return false
		}
	} }
}

/** QBEValueCoder implements encoding for QBEValue (which cannot implement it as it is an enum). **/
class QBEValueCoder: NSObject, NSSecureCoding {
	let value: QBEValue
	
	override init() {
		self.value = .EmptyValue
	}
	
	init(_ value: QBEValue) {
		self.value = value
	}
	
	required init(coder aDecoder: NSCoder) {
		let t = aDecoder.decodeIntForKey("type")
		switch t {
			case 1: value = .StringValue((aDecoder.decodeObjectForKey("value") as? String) ?? "")
			case 2: value = .IntValue(aDecoder.decodeIntegerForKey("value"))
			case 3: value = .BoolValue(aDecoder.decodeBoolForKey("value"))
			case 4: value = .DoubleValue(aDecoder.decodeDoubleForKey("value"))
			case 5: value = .EmptyValue
			case 6: value = .InvalidValue
			default: value = .EmptyValue
		}
	}
	
	func encodeWithCoder(coder: NSCoder) {
		switch value {
		case .StringValue(let s):
			coder.encodeInt(1, forKey: "type")
			coder.encodeObject(s, forKey: "value")
			
		case .IntValue(let i):
			coder.encodeInt(2, forKey: "type")
			coder.encodeInteger(i, forKey: "value")
			
		case .BoolValue(let b):
			coder.encodeInt(3, forKey: "type")
			coder.encodeBool(b, forKey: "value")
			
		case .DoubleValue(let d):
			coder.encodeInt(4, forKey: "type")
			coder.encodeDouble(d, forKey: "value")
			
		case .EmptyValue:
			coder.encodeInt(5, forKey: "type")
			
		case .InvalidValue:
			coder.encodeInt(6, forKey: "type")
		}
	}
	
	class func supportsSecureCoding() -> Bool {
		return true
	}
}

func / (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		if let rd = rhs.doubleValue {
			// Division by zero will result in QBEValue.InvalidValue (handled in QBEValue initializer, which checks isnan/isinf)
			return QBEValue(ld / rd)
		}
	}
	return QBEValue.InvalidValue
}

func % (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		if let rd = rhs.doubleValue {
			return QBEValue(ld % rd)
		}
	}
	return QBEValue.InvalidValue
}

func & (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if !lhs.isValid || !rhs.isValid {
		return QBEValue.InvalidValue
	}
	
	return QBEValue.StringValue((lhs.stringValue ?? "") + (rhs.stringValue ?? ""))
}

func * (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		if let rd = rhs.doubleValue {
			return QBEValue.DoubleValue(ld * rd)
		}
	}
	return QBEValue.InvalidValue
}

func ^ (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let lh = lhs.doubleValue {
		if let rh = rhs.doubleValue {
			return QBEValue.DoubleValue(pow(lh, rh));
		}
	}
	return QBEValue.InvalidValue
}

func + (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		if let rd = rhs.doubleValue {
			return QBEValue.DoubleValue(ld + rd)
		}
	}
	return QBEValue.InvalidValue
}

func - (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		if let rd = rhs.doubleValue {
			return QBEValue.DoubleValue(ld - rd)
		}
	}
	return QBEValue.InvalidValue
}

func == (lhs: QBEValue, rhs: QBEValue) -> Bool {
	// The invalid value is never equal to anything, not even another invalid value
	if !lhs.isValid || !rhs.isValid {
		return false
	}
	
	switch (lhs, rhs) {
	case (.IntValue, .IntValue):
		return lhs.intValue == rhs.intValue
		
	case (.DoubleValue, .DoubleValue):
		return lhs.doubleValue == rhs.doubleValue
		
	case (.IntValue, .DoubleValue):
		return lhs.doubleValue == rhs.doubleValue
		
	case (.DoubleValue, .IntValue):
		return lhs.doubleValue == rhs.doubleValue
		
	case (.StringValue, .DoubleValue):
		return lhs.doubleValue == rhs.doubleValue
		
	case (.DoubleValue, .StringValue):
		return lhs.doubleValue == rhs.doubleValue
		
	case (.StringValue, .IntValue):
		return lhs.intValue == rhs.intValue
		
	case (.IntValue, .StringValue):
		return lhs.intValue == rhs.intValue
		
	default:
		return lhs.stringValue == rhs.stringValue
	}
}

func != (lhs: QBEValue, rhs: QBEValue) -> Bool {
	if !lhs.isValid || !rhs.isValid {
		return true
	}
	
	return !(lhs == rhs)
}

func > (lhs: QBEValue, rhs: QBEValue) -> Bool {
	if !lhs.isValid || !rhs.isValid {
		return false
	}
	
	switch(lhs, rhs) {
	case (.IntValue, .IntValue):
		return lhs.intValue > rhs.intValue
		
	default:
		return lhs.doubleValue > rhs.doubleValue
	}
}

func < (lhs: QBEValue, rhs: QBEValue) -> Bool {
	if !lhs.isValid || !rhs.isValid {
		return false
	}
	
	switch(lhs, rhs) {
	case (.IntValue, .IntValue):
		return lhs.intValue < rhs.intValue
		
	default:
		return lhs.doubleValue < rhs.doubleValue
	}
}

func >= (lhs: QBEValue, rhs: QBEValue) -> Bool {
	if !lhs.isValid || !rhs.isValid {
		return false
	}
	
	switch(lhs, rhs) {
	case (.IntValue, .IntValue):
		return lhs.intValue >= rhs.intValue
		
	default:
		return lhs.doubleValue >= rhs.doubleValue
	}
}

func <= (lhs: QBEValue, rhs: QBEValue) -> Bool {
	if !lhs.isValid || !rhs.isValid {
		return false
	}
	
	switch(lhs, rhs) {
	case (.IntValue, .IntValue):
		return lhs.intValue <= rhs.intValue
		
	default:
		return lhs.doubleValue <= rhs.doubleValue
	}
}

func <= (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs <= rhs)
}

func >= (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs >= rhs)
}

func == (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs == rhs)
}

func != (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs != rhs)
}

func < (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs < rhs)
}

func > (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs > rhs)
}

func ~= (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let l = lhs.stringValue, r = rhs.stringValue {
		return QBEValue.BoolValue(l.rangeOfString(r, options: NSStringCompareOptions.CaseInsensitiveSearch, range: nil, locale: nil) != nil)
	}
	return QBEValue.InvalidValue
}

infix operator ~~= {
	associativity left precedence 120
}

func ~~= (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let l = lhs.stringValue, r = rhs.stringValue {
		return QBEValue.BoolValue(l.rangeOfString(r, options: NSStringCompareOptions.allZeros, range: nil, locale: nil) != nil)
	}
	return QBEValue.InvalidValue
}

prefix func - (lhs: QBEValue) -> QBEValue {
	switch lhs {
	case .IntValue(let i):
		return QBEValue.IntValue(-i)
		
	case .DoubleValue(let d):
		return QBEValue.DoubleValue(-d)
		
	default:
		return QBEValue.InvalidValue
	}
}