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
}

internal extension Array {
	func implode <C: ExtensibleCollectionType> (separator: C) -> C? {
		if Element.self is C.Type {
			return Swift.join(separator, unsafeBitCast(self, [C].self))
		}
		
		return nil
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
}

internal enum QBEValue: Hashable {
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
		if isnan(value) {
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
	
	func absolute() -> QBEValue {
		return (self < QBEValue(0)) ? -self : self
	}
	
	var description: String { get {
		// FIXME: return something sensible for empty/invalid values
		return self.stringValue ?? ""
	} }
	
	var isValid: Bool { get {
		switch self {
		case .InvalidValue: return false
		default: return true
		}
	} }
}

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
			case 1: value = .StringValue(aDecoder.decodeObjectForKey("value") as? String ?? "")
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
			if rd == 0 {
				return QBEValue.InvalidValue
			}
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
	switch (lhs, rhs) {
	case (.IntValue, .IntValue):
		return QBEValue.IntValue(lhs.intValue! * rhs.intValue!)
		
	case (.DoubleValue, .DoubleValue):
		return QBEValue.DoubleValue(lhs.doubleValue! * rhs.doubleValue!)
		
	case (.IntValue, .DoubleValue):
		return QBEValue.DoubleValue(lhs.doubleValue! * rhs.doubleValue!)
		
	case (.DoubleValue, .IntValue):
		return QBEValue.DoubleValue(lhs.doubleValue! * rhs.doubleValue!)
		
	default:
		return QBEValue.InvalidValue
	}
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
	switch (lhs, rhs) {
	case (.IntValue, .IntValue):
		return QBEValue.IntValue(lhs.intValue! + rhs.intValue!)
		
	case (.DoubleValue, .DoubleValue):
		return QBEValue.DoubleValue(lhs.doubleValue! + rhs.doubleValue!)
		
	case (.IntValue, .DoubleValue):
		return QBEValue.DoubleValue(lhs.doubleValue! + rhs.doubleValue!)
		
	case (.DoubleValue, .IntValue):
		return QBEValue.DoubleValue(lhs.doubleValue! + rhs.doubleValue!)
		
	default:
		return QBEValue.InvalidValue
	}
}

func - (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	switch (lhs, rhs) {
	case (.IntValue, .IntValue):
		return QBEValue.IntValue(lhs.intValue! - rhs.intValue!)
		
	case (.DoubleValue, .DoubleValue):
		return QBEValue.DoubleValue(lhs.doubleValue! - rhs.doubleValue!)
		
	case (.IntValue, .DoubleValue):
		return QBEValue.DoubleValue(lhs.doubleValue! - rhs.doubleValue!)
		
	case (.DoubleValue, .IntValue):
		return QBEValue.DoubleValue(lhs.doubleValue! - rhs.doubleValue!)
		
	default:
		return QBEValue.InvalidValue
	}
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
		
	default:
		return lhs.stringValue == rhs.stringValue
	}
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