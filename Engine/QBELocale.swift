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
	
	/** Returns the function for the specified name, or nil if that function doesn't exist. **/
	func functionWithName(name: String) -> QBEFunction?
	
	func nameForFunction(function: QBEFunction) -> String?
	
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
	
	let constants: [QBEValue: String]
	
	private let functions: [String: QBEFunction]
	
	private let defaultConstants = [
		QBEValue(true): "TRUE",
		QBEValue(false): "FALSE",
		QBEValue(3.141592654): "PI"
	]
	
	private let defaultFunctions: [String: QBEFunction] = [
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
		"RANDBETWEEN": QBEFunction.RandomBetween,
		"RANDOM": QBEFunction.Random,
		
		// Non-Excel functions
		"COALESCE": QBEFunction.Coalesce,
		"IFERROR": QBEFunction.IfError,
		"PACK": QBEFunction.Pack
	]
	
	internal init(functions: [String: QBEFunction], constants: [QBEValue: String]) {
		self.functions = functions
		self.constants = constants
	}
	
	override init() {
		functions = defaultFunctions
		constants = defaultConstants
	}
	
	func functionWithName(name: String) -> QBEFunction? {
		if let qu = functions[name] {
			return qu
		}
		else {
			// Case insensitive function find (slower)
			for (name, function) in functions {
				if name.caseInsensitiveCompare(name) == NSComparisonResult.OrderedSame {
					return function
				}
			}
		}
		return nil
	}
	
	func nameForFunction(function: QBEFunction) -> String? {
		for (name, f) in functions {
			if function == f {
				return name
			}
		}
		return nil
	}
	
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