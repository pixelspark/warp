import Foundation

typealias QBEFuture = () -> QBERaster
typealias QBEFilter = (QBERaster) -> (QBERaster)

struct QBEColumn: StringLiteralConvertible {
	typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
	typealias UnicodeScalarLiteralType = StringLiteralType
	
	let name: String
	
	init(_ name: String) {
		self.name = name
	}
	
	init(stringLiteral value: StringLiteralType) {
		self.name = value
	}
	
	init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
		self.name = value
	}
	
	init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
		self.name = value
	}

}

/* Column names retain case, but they are compared case-insensitively */
func == (lhs: QBEColumn, rhs: QBEColumn) -> Bool {
	return lhs.name.caseInsensitiveCompare(rhs.name) == NSComparisonResult.OrderedSame
}

func != (lhs: QBEColumn, rhs: QBEColumn) -> Bool {
	return !(lhs == rhs)
}

func memoize<T>(result: () -> T) -> () -> T {
	var cached: T? = nil
	
	return {() in
		if let v = cached {
			return v
		}
		else {
			cached = result()
			return cached!
		}
	}
}

protocol QBEData: NSObjectProtocol {
	func transpose() -> QBEData
	func calculate(targetColumn: QBEColumn, formula: QBEExpression) -> QBEData
	func limit(numberOfRows: Int) -> QBEData
	func replace(value: QBEValue, withValue: QBEValue, inColumn: QBEColumn) -> QBEData
	func stream(receiver: ([[QBEValue]]) -> ())
	
	var raster: QBEFuture { get }
	var columnNames: [QBEColumn] { get }
}