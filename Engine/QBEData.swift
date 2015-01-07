import Foundation

typealias QBEFuture = () -> QBERaster
typealias QBEFilter = (QBERaster) -> (QBERaster)

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
	func calculate(targetColumn: String, formula: QBEFunction) -> QBEData
	func limit(numberOfRows: Int) -> QBEData
	func replace(value: QBEValue, withValue: QBEValue, inColumn: String) -> QBEData
	
	var raster: QBEFuture { get }
	var columnNames: [String] { get }
}