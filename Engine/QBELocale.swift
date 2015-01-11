import Foundation

protocol QBELocale: NSObjectProtocol {
	/** The decimal separator symbol**/
	var decimalSeparator: String { get }
	
	/** Start and end of string literal **/
	var stringQualifier: Character { get }
	
	var argumentSeparator: String { get }
	
	/** String to use when the string qualifier needs to appear in a string itself **/
	var stringQualifierEscape: String { get }
	
	var constants: [QBEValue:String] { get }
	var unaryFunctions: [String: QBEFunction] { get }
	
	/** For CSV writing and reading **/
	func csvRow(row: [QBEValue]) -> String
}

/** The default dialect for formulas reflects the English version of Excel closely. **/
class QBEDefaultLocale: NSObject, QBELocale {
	let decimalSeparator = "."
	let stringQualifier: Character = "\""
	let stringQualifierEscape = "\"\""
	let argumentSeparator = ";"
	
	let csvFieldSeparator = ";"
	let csvLineSeparator = "\r\n"
	let csvStringQualifier = "\""
	let csvStringEscaper = "\"\""
	
	let constants = [
		QBEValue(true): "TRUE",
		QBEValue(false): "FALSE"
	]
	
	let unaryFunctions = [
		"UPPER": QBEFunction.Uppercase,
		"LOWER": QBEFunction.Lowercase,
		"ABS": QBEFunction.Absolute,
		"AND": QBEFunction.And,
		"OR": QBEFunction.Or,
		"SQRT": QBEFunction.Sqrt,
		"SIN": QBEFunction.Sin,
		"COS": QBEFunction.Cos,
		"TAN": QBEFunction.Tan,
		"ASIN": QBEFunction.Asin,
		"ACOS": QBEFunction.Acos,
		"ATAN": QBEFunction.Atan,
		"SINH": QBEFunction.Sinh,
		"COSH": QBEFunction.Cosh,
		"TANH": QBEFunction.Tanh,
		"IF": QBEFunction.If,
		"CONCAT": QBEFunction.Concat
	]
	
	func csvRow(row: [QBEValue]) -> String {
		var line = ""
		for columnIndex in 0...row.count-1 {
			let value = row[columnIndex]
			switch value {
			case .StringValue(let s):
				line += "\(csvStringQualifier)\(s.stringByReplacingOccurrencesOfString(csvStringQualifier, withString: csvStringEscaper))\(csvStringQualifier)"
			
			case .DoubleValue(let d):
				// FIXME: use decimalSeparator from locale
				line += "\(d)"
				
			case .IntValue(let i):
				line += "\(i)"
				
			case .BoolValue(let b):
				line += (b ? "1" : "0")
				
			case .EmptyValue:
				break
			}
			
			if(columnIndex < row.count-1) {
				line += csvFieldSeparator
			}
		}
		line += csvLineSeparator
		return line
	}
}

private func keyForValue(value: QBEValue, inDictionary: Dictionary<String, QBEValue>) -> String? {
	for (key, v) in inDictionary {
		if v == value {
			return key
		}
	}
	return nil
}