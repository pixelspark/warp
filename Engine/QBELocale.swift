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

/** The default dialect for formulas reflects the English version of Excel closely. **/
class QBELocale: NSObject {
	typealias QBELanguage = String
	
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
	
	static let languages: [QBELanguage: String] = [
		"nl": NSLocalizedString("Dutch", comment: ""),
		"en": NSLocalizedString("English", comment: "")
	]
	
	static let defaultLanguage: QBELanguage = "en"
	
	private static let allConstants: [QBELanguage: [QBEValue: String]] = [
		"en": [
			QBEValue(true): "TRUE",
			QBEValue(false): "FALSE",
			QBEValue(3.141592654): "PI",
			QBEValue.EmptyValue: "NULL",
			QBEValue.InvalidValue: "ERROR"
		],
		
		"nl": [
			QBEValue(true): "WAAR",
			QBEValue(false): "ONWAAR",
			QBEValue(3.141592654): "PI",
			QBEValue.EmptyValue: "LEEG",
			QBEValue.InvalidValue: "FOUT"
		]
	]
	
	private static let allFunctions: [QBELanguage: [String: QBEFunction]] = [
		"en": [
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
			"REPLACE.PATTERN": QBEFunction.RegexSubstitute,
			"TRIM": QBEFunction.Trim,
			"SUM": QBEFunction.Sum,
			"COUNT": QBEFunction.Count,
			"AVERAGE": QBEFunction.Average,
			"COUNTA": QBEFunction.CountAll,
			"MIN": QBEFunction.Min,
			"MAX": QBEFunction.Max,
			"EXP": QBEFunction.Exp,
			"LN": QBEFunction.Ln,
			"ROUND": QBEFunction.Round,
			"CHOOSE": QBEFunction.Choose,
			"RANDBETWEEN": QBEFunction.RandomBetween,
			"RAND": QBEFunction.Random,
			"COALESCE": QBEFunction.Coalesce,
			"IFERROR": QBEFunction.IfError,
			"PACK": QBEFunction.Pack,
			"NORM.INV": QBEFunction.NormalInverse
		],
		
		"nl": [
			"ABS": QBEFunction.Absolute,
			"BOOGCOS": QBEFunction.Acos,
			"EN": QBEFunction.And,
			"BOOGSIN": QBEFunction.Asin,
			"BOOGTAN": QBEFunction.Atan,
			"GEMIDDELDE": QBEFunction.Average,
			"KIEZEN": QBEFunction.Choose,
			"TEKST.SAMENVOEGEN": QBEFunction.Concat,
			"COS": QBEFunction.Cos,
			"COSH": QBEFunction.Cosh,
			"AANTAL": QBEFunction.Count,
			"AANTALARG": QBEFunction.CountAll,
			"EXP": QBEFunction.Exp,
			"ALS": QBEFunction.If,
			"ALS.FOUT": QBEFunction.IfError,
			"LINKS": QBEFunction.Left,
			"LENGTE": QBEFunction.Length,
			"LN": QBEFunction.Ln,
			"LOG": QBEFunction.Log,
			"KLEINE.LETTERS": QBEFunction.Lowercase,
			"MAX": QBEFunction.Max,
			"DEEL": QBEFunction.Mid,
			"MIN": QBEFunction.Min,
			"NIET": QBEFunction.Not,
			"OF": QBEFunction.Or,
			"ASELECTTUSSEN": QBEFunction.RandomBetween,
			"ASELECT": QBEFunction.Random,
			"RECHTS": QBEFunction.Right,
			"AFRONDEN": QBEFunction.Round,
			"SIN": QBEFunction.Sin,
			"SINH": QBEFunction.Sinh,
			"WORTEL": QBEFunction.Sqrt,
			"SUBSTITUEREN.PATROON": QBEFunction.RegexSubstitute,
			"SUBSTITUEREN": QBEFunction.Substitute,
			"SOM": QBEFunction.Sum,
			"TAN": QBEFunction.Tan,
			"TANH": QBEFunction.Tanh,
			"SPATIES.WISSEN": QBEFunction.Trim,
			"HOOFDLETTERS": QBEFunction.Uppercase,
			"EX.OF": QBEFunction.Xor,
			"EERSTE.GELDIG": QBEFunction.Coalesce,
			"INPAKKEN": QBEFunction.Pack,
			"NORM.INV.N": QBEFunction.NormalInverse
		]
	]
	
	var numberFormatter: NSNumberFormatter
	
	init(language: QBELanguage = QBELocale.defaultLanguage) {
		functions = QBELocale.allFunctions[language] ?? QBELocale.allFunctions[QBELocale.defaultLanguage]!
		constants = QBELocale.allConstants[language] ?? QBELocale.allConstants[QBELocale.defaultLanguage]!
		numberFormatter = NSNumberFormatter()
		numberFormatter.numberStyle = NSNumberFormatterStyle.DecimalStyle
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
	
	/** Return a string representation of the value in the user's locale. **/
	func localStringFor(value: QBEValue) -> String {
		switch value {
			case .StringValue(let s):
				return s
			
			case .BoolValue(let b):
				return constants[QBEValue(b)]!
			
			case .IntValue(let i):
				return numberFormatter.stringFromNumber(i)!
			
			case .DoubleValue(let d):
				return numberFormatter.stringFromNumber(d)!
			
			case .InvalidValue:
				return ""
			
			case .EmptyValue:
				return ""
		}
	}
	
	func valueForLocalString(value: String) -> QBEValue {
		if value.isEmpty {
			return QBEValue.EmptyValue
		}
		
		// Can this string be interpreted as a number?
		if let n = numberFormatter.numberFromString(value) {
			if n.isEqualToNumber(NSNumber(integer: n.integerValue)) {
				// This number is an integer
				return QBEValue.IntValue(n.integerValue)
			}
			else {
				return QBEValue.DoubleValue(n.doubleValue)
			}
		}
		
		return QBEValue.StringValue(value)
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