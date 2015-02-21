import Foundation

/** The pack format is a framing format to store an array of values in a string, where the items of the array themselves
may contain the separator character. These occurrences are escaped in the pack format using the escape sequence 
QBEPackSeparatorEscape. Occurrences of the escape character are replaced with the QBEPackEscapeEscape sequence. The pack
format is inspired by the SLIP serial line framing format. The pack format allows values to be grouped together in a single
value cell (e.g. during aggregation) to later be unpacked again.

Using ',' as separator, '$0' as separator escape and '$1' as escape-escape, packing the array ["a","b,", "c$"] leads to 
the following pack string: "a,b$0,c$1". Unpacking the pack string "$0$0$0,$1$0,," leads to the array [",,,", "$,","",""].
**/
let QBEPackSeparator = ","
let QBEPackEscape = "$"
let QBEPackSeparatorEscape = "$0"
let QBEPackEscapeEscape = "$1"

/** QBELocale contains settings that determine how values are presented to the user. Results from QBELocale are *never* 
used in a calculation, as they change when the user selects a different locale. **/
protocol QBELocale: NSObjectProtocol {
	/** The decimal separator symbol **/
	var decimalSeparator: String { get }
	
	/** Start and end of string literal **/
	var stringQualifier: Character { get }
	
	var argumentSeparator: String { get }
	
	/** A list of common field separators (e.g. for parsing CSVs). Note that currently, only single-character separators
	are supported. **/
	var commonFieldSeparators: [String] { get }
	
	/** String to use when the string qualifier needs to appear in a string itself **/
	var stringQualifierEscape: String { get }
	
	var currentCellIdentifier: String { get }
	
	/** All constants that can be used in formulas (optionally the UI can choose to translate numbers back to constant 
	names, but this is not done often, only for boolean values) **/
	var constants: [QBEValue:String] { get }
	
	/** A list of all function names and the QBEFunction they refer to. **/
	var functions: [String: QBEFunction] { get }
	
	/** For CSV writing and reading **/
	func csvRow(row: [QBEValue]) -> String
}

/** The default dialect for formulas reflects the English version of Excel closely. **/
class QBEDefaultLocale: NSObject, QBELocale {
	let decimalSeparator = "."
	let stringQualifier: Character = "\""
	let stringQualifierEscape = "\"\""
	let argumentSeparator = ";"
	let currentCellIdentifier = "RC"
	
	let csvFieldSeparator = ";"
	let csvLineSeparator = "\r\n"
	let csvStringQualifier = "\""
	let csvStringEscaper = "\"\""
	
	let commonFieldSeparators = [";",",","|","\t"]
	
	let constants = [
		QBEValue(true): "TRUE",
		QBEValue(false): "FALSE",
		QBEValue(3.141592654): "PI"
	]
	
	let functions = [
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
		"CONCAT": QBEFunction.Concat,
		"LEFT": QBEFunction.Left,
		"RIGHT": QBEFunction.Right,
		"MID": QBEFunction.Mid,
		"LENGTH": QBEFunction.Length,
		"LOG": QBEFunction.Log,
		"NOT": QBEFunction.Not,
		"XOR": QBEFunction.Xor,
		"REPLACE": QBEFunction.Substitute,
		"TRIM": QBEFunction.Trim,
		"SUM": QBEFunction.Sum,
		"COUNT": QBEFunction.Count,
		"AVERAGE": QBEFunction.Average,
		"COUNTARGS": QBEFunction.CountAll,
		"MIN": QBEFunction.Min,
		"MAX": QBEFunction.Max,
		"EXP": QBEFunction.Exp,
		"LN": QBEFunction.Ln,
		"ROUND": QBEFunction.Round,
		"CHOOSE": QBEFunction.Choose,
		
		// Non-Excel functions
		"COALESCE": QBEFunction.Coalesce,
		"IFERROR": QBEFunction.IfError,
		"PACK": QBEFunction.Pack
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
				
			case .InvalidValue:
				break
				
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