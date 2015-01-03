import Foundation

class QBEValue: NSObject, UnicodeScalarLiteralConvertible, IntegerLiteralConvertible, NSCoding {
    let value: String
    
    init(_ value: String = "") {
        self.value = value
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