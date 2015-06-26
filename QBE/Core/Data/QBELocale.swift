import Foundation

/** The default dialect for formulas reflects the English version of Excel closely. */
struct QBELocale {
	typealias QBELanguage = String
	
	var decimalSeparator = "."
	var stringQualifier: Character = "\""
	var stringQualifierEscape = "\"\""
	var argumentSeparator = ";"
	var currentCellIdentifier = "RC"
	var csvFieldSeparator = ";"
	var csvLineSeparator = "\r\n"
	var csvStringQualifier = "\""
	var csvStringEscaper = "\"\""
	var commonFieldSeparators = [";",",","|","\t"]
	var numberFormatter: NSNumberFormatter
	var constants: [QBEValue: String]
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
			"NORM.INV": QBEFunction.NormalInverse,
			"SIGN": QBEFunction.Sign,
			"SPLIT": QBEFunction.Split,
			"NTH": QBEFunction.Nth,
			"ITEMS": QBEFunction.Items,
			"SIMILARITY": QBEFunction.Levenshtein,
			"ENCODEURL": QBEFunction.URLEncode,
			"IN": QBEFunction.In
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
			"NORM.INV.N": QBEFunction.NormalInverse,
			"POS.NEG": QBEFunction.Sign,
			"SPLITS": QBEFunction.Split,
			"NDE": QBEFunction.Nth,
			"ITEMS": QBEFunction.Items,
			"GELIJKENIS": QBEFunction.Levenshtein,
			"URL.CODEREN": QBEFunction.URLEncode,
			"IN": QBEFunction.In
		]
	]
	
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
	
	/** Return a string representation of the value in the user's locale. */
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