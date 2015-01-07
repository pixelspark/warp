import Foundation

extension String {
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

extension Double {
	func toString() -> String {
		return String(format: "%.1f",self)
	}
}

class QBEValue: NSObject, UnicodeScalarLiteralConvertible, IntegerLiteralConvertible, NSCoding {
	let value: String
	
	init(_ value: String = "") {
		self.value = value
	}
	
	init(_ value: Double) {
		self.value = value.toString()
	}
	
	init(_ value: Int) {
		self.value = String(value)
	}
	
	required init(coder: NSCoder) {
		if let x = coder.decodeObjectForKey("value") as? String {
			value = x
		}
		else {
			value = ""
		}
	}
	
	required init(integerLiteral: Int) {
		self.value = String(integerLiteral)
	}
	
	required init(unicodeScalarLiteral: String) {
		self.value = unicodeScalarLiteral as String
	}
	
	func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(value, forKey: "value")
	}
	
	override var description: String {
		get {
			return self.value
		}
	}
	
	var stringValue: String { get {
		return self.value
	} }
	
	var intValue: Int? { get {
		return self.value.toInt()
	} }
	
	var doubleValue: Double? { get {
			return self.value.toDouble()
	} }
}

func + (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		if let rd = rhs.doubleValue {
			return QBEValue(ld + rd)
		}
	}
	return QBEValue()
}

func - (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		if let rd = rhs.doubleValue {
			return QBEValue(ld - rd)
		}
	}
	return QBEValue()
}

prefix func - (lhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		return QBEValue(-ld)
	}
	return QBEValue()
}

func * (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		if let rd = rhs.doubleValue {
			return QBEValue(ld * rd)
		}
	}
	return QBEValue()
}

func ^ (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		if let rd = rhs.doubleValue {
			return QBEValue(pow(ld, rd))
		}
	}
	return QBEValue()
}

func / (lhs: QBEValue, rhs: QBEValue) -> QBEValue {
	if let ld = lhs.doubleValue {
		if let rd = rhs.doubleValue {
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
	let ld = lhs.stringValue
	let rd = rhs.stringValue
	return QBEValue(ld + rd)
}

func == (lhs: QBEValue, rhs: QBEValue) -> Bool {
	return rhs.value == lhs.value
}

func == (lhs: QBEValue, rhs: String) -> Bool {
	return rhs == lhs.value
}

func != (lhs: QBEValue, rhs: QBEValue) -> Bool {
	return lhs.value != rhs.value
}