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

internal enum QBEValueRepresentation {
	case StringValue(String)
	case IntValue(Int)
	case BoolValue(Bool)
	case DoubleValue(Double)
	case EmptyValue
	
	var stringValue: String { get {
		switch self {
		case .StringValue(let s): return s
		case .IntValue(let i): return i.toString()
		case .BoolValue(let b): return b.toString()
		case .DoubleValue(let d): return d.toString()
		case .EmptyValue: return ""
		}
	} }
	
	var doubleValue: Double? { get {
		switch self {
			case .StringValue(let s): return s.toDouble()
			case .IntValue(let i): return i.toDouble()
			case .BoolValue(let b): return b.toDouble()
			case .DoubleValue(let d): return d
			case .EmptyValue: return nil
		}
	} }
	
	var intValue: Int? { get {
		switch self {
			case .StringValue(let s): return s.toInt()
			case .IntValue(let i): return i
			case .BoolValue(let b): return b.toInt()
			case .DoubleValue(let d): return Int(d)
			case .EmptyValue: return nil
		}
	} }
	
	init(coder: NSCoder) {
		let t = coder.decodeIntForKey("type")
		switch t {
			case 1: self = .StringValue(coder.decodeObjectForKey("value") as? String ?? "")
			case 2: self = .IntValue(coder.decodeIntegerForKey("value"))
			case 3: self = .BoolValue(coder.decodeBoolForKey("value"))
			case 4: self = .DoubleValue(coder.decodeDoubleForKey("value"))
			case 5: self = .EmptyValue
			default: self = .EmptyValue
		}
	}
	
	func encodeWithCoder(coder: NSCoder) {
		switch self {
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
		}
	}
}

class QBEValue: NSObject, UnicodeScalarLiteralConvertible, IntegerLiteralConvertible, NSCoding {
	let value: QBEValueRepresentation
	
	internal init(_ value: QBEValueRepresentation) {
		self.value = value
	}
	
	init(_ value: String = "") {
		self.value = .StringValue(value)
	}
	
	init(_ value: Double) {
		self.value = .DoubleValue(value)
	}
	
	init(_ value: Int) {
		self.value = .IntValue(value)
	}
	
	init(_ value: Bool) {
		self.value = .BoolValue(value)
	}
	
	required init(coder: NSCoder) {
		self.value = QBEValueRepresentation(coder: coder)
	}
	
	required init(integerLiteral: Int) {
		self.value = .IntValue(integerLiteral)
	}
	
	required init(unicodeScalarLiteral: String) {
		self.value = .StringValue(unicodeScalarLiteral)
	}
	
	func encodeWithCoder(coder: NSCoder) {
		value.encodeWithCoder(coder)
	}
	
	override var description: String {
		get {
			return self.value.stringValue
		}
	}
	
	var stringValue: String { get {
		return self.value.stringValue
	} }
	
	var intValue: Int? { get {
		return self.value.intValue
	} }
	
	var doubleValue: Double? { get {
			return self.value.doubleValue
	} }
}

func + (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs.value + rhs.value)
}

func - (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs.value - rhs.value)
}

prefix func - (lhs: QBEValue) -> QBEValue {
	return QBEValue(-lhs.value)
}

func * (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs.value * rhs.value)
}

func ^ (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs.value ^ rhs.value)
}

func > (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs.value > rhs.value)
}

func < (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs.value < rhs.value)
}

func >= (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs.value >= rhs.value)
}

func <= (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs.value <= rhs.value)
}

func == (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs.value == rhs.value)
}

func == (lhs: QBEValue, rhs: String) -> QBEValue {
	return QBEValue(rhs == lhs.value.stringValue)
}

func != (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(!(lhs.value == rhs.value))
}

func == (lhs: QBEValue, rhs: QBEValue) -> Bool {
	return (lhs.value == rhs.value)
}

func == (lhs: QBEValue, rhs: String) -> Bool {
	return (rhs == lhs.value.stringValue)
}

func != (lhs: QBEValue, rhs: QBEValue) -> Bool {
	return (!(lhs.value == rhs.value))
}

func / (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		if let rd = rhs.doubleValue {
			if rd == 0 {
				return QBEValue()
			}
			return QBEValue(ld / rd)
		}
	}
	return QBEValue()
}

func % (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		if let rd = rhs.doubleValue {
			return QBEValue(ld % rd)
		}
	}
	return QBEValue()
}

func & (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	return QBEValue(lhs.value & rhs.value)
}

func & (lhs: QBEValueRepresentation, rhs: QBEValueRepresentation) -> QBEValueRepresentation {
	return QBEValueRepresentation.StringValue(lhs.stringValue + rhs.stringValue)
}

func * (lhs: QBEValueRepresentation, rhs: QBEValueRepresentation) -> QBEValueRepresentation {
	switch (lhs, rhs) {
	case (.IntValue, .IntValue):
		return QBEValueRepresentation.IntValue(lhs.intValue! * rhs.intValue!)
		
	case (.DoubleValue, .DoubleValue):
		return QBEValueRepresentation.DoubleValue(lhs.doubleValue! * rhs.doubleValue!)
		
	case (.IntValue, .DoubleValue):
		return QBEValueRepresentation.DoubleValue(lhs.doubleValue! * rhs.doubleValue!)
		
	case (.DoubleValue, .IntValue):
		return QBEValueRepresentation.DoubleValue(lhs.doubleValue! * rhs.doubleValue!)
		
	default:
		return QBEValueRepresentation.EmptyValue
	}
}

func ^ (lhs: QBEValueRepresentation, rhs: QBEValueRepresentation) -> QBEValueRepresentation {
	if let lh = lhs.doubleValue {
		if let rh = rhs.doubleValue {
			return QBEValueRepresentation.DoubleValue(pow(lh, rh));
		}
	}
	return QBEValueRepresentation.EmptyValue
}

func + (lhs: QBEValueRepresentation, rhs: QBEValueRepresentation) -> QBEValueRepresentation {
	switch (lhs, rhs) {
	case (.IntValue, .IntValue):
		return QBEValueRepresentation.IntValue(lhs.intValue! + rhs.intValue!)
		
	case (.DoubleValue, .DoubleValue):
		return QBEValueRepresentation.DoubleValue(lhs.doubleValue! + rhs.doubleValue!)
		
	case (.IntValue, .DoubleValue):
		return QBEValueRepresentation.DoubleValue(lhs.doubleValue! + rhs.doubleValue!)
		
	case (.DoubleValue, .IntValue):
		return QBEValueRepresentation.DoubleValue(lhs.doubleValue! + rhs.doubleValue!)
		
	default:
		return QBEValueRepresentation.EmptyValue
	}
}

func - (lhs: QBEValueRepresentation, rhs: QBEValueRepresentation) -> QBEValueRepresentation {
	switch (lhs, rhs) {
	case (.IntValue, .IntValue):
		return QBEValueRepresentation.IntValue(lhs.intValue! - rhs.intValue!)
		
	case (.DoubleValue, .DoubleValue):
		return QBEValueRepresentation.DoubleValue(lhs.doubleValue! - rhs.doubleValue!)
		
	case (.IntValue, .DoubleValue):
		return QBEValueRepresentation.DoubleValue(lhs.doubleValue! - rhs.doubleValue!)
		
	case (.DoubleValue, .IntValue):
		return QBEValueRepresentation.DoubleValue(lhs.doubleValue! - rhs.doubleValue!)
		
	default:
		return QBEValueRepresentation.EmptyValue
	}
}

func == (lhs: QBEValueRepresentation, rhs: QBEValueRepresentation) -> Bool {
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

func > (lhs: QBEValueRepresentation, rhs: QBEValueRepresentation) -> Bool {
	switch(lhs, rhs) {
	case (.IntValue, .IntValue):
		return lhs.intValue > rhs.intValue
		
	default:
		return lhs.doubleValue > rhs.doubleValue
	}
}

func < (lhs: QBEValueRepresentation, rhs: QBEValueRepresentation) -> Bool {
	switch(lhs, rhs) {
	case (.IntValue, .IntValue):
		return lhs.intValue < rhs.intValue
		
	default:
		return lhs.doubleValue < rhs.doubleValue
	}
}

func >= (lhs: QBEValueRepresentation, rhs: QBEValueRepresentation) -> Bool {
	switch(lhs, rhs) {
	case (.IntValue, .IntValue):
		return lhs.intValue >= rhs.intValue
		
	default:
		return lhs.doubleValue >= rhs.doubleValue
	}
}

func <= (lhs: QBEValueRepresentation, rhs: QBEValueRepresentation) -> Bool {
	switch(lhs, rhs) {
	case (.IntValue, .IntValue):
		return lhs.intValue <= rhs.intValue
		
	default:
		return lhs.doubleValue <= rhs.doubleValue
	}
}

prefix func - (lhs: QBEValueRepresentation) -> QBEValueRepresentation {
	switch lhs {
	case .IntValue(let i):
		return QBEValueRepresentation.IntValue(-i)
		
	case .DoubleValue(let d):
		return QBEValueRepresentation.DoubleValue(-d)
		
	default:
		return QBEValueRepresentation.EmptyValue
	}
}