import Foundation

internal func QBEText(text: String) -> String {
	let bundle = NSBundle(forClass: QBELocale.self)
	return NSLocalizedString(text, tableName: nil, bundle: bundle, value: text, comment: "")
}

/** The default dialect for formulas reflects the English version of Excel closely. */
public class QBELocale {
	public typealias QBELanguage = String
	
	public var decimalSeparator: String
	public var groupingSeparator: String
	public var stringQualifier: Character = "\""
	public var stringQualifierEscape = "\"\""
	public var argumentSeparator = ";"
	public var currentCellIdentifier = "RC"
	public var csvFieldSeparator = ";"
	public var csvLineSeparator = "\r\n"
	public var csvStringQualifier = "\""
	public var csvStringEscaper = "\"\""
	public var commonFieldSeparators = [";",",","|","\t"]
	public var numberFormatter: NSNumberFormatter
	public var dateFormatter: NSDateFormatter
	public var timeZone: NSTimeZone
	public var calendar: NSCalendar
	public var constants: [QBEValue: String]
	public let functions: [String: QBEFunction]
	public let postfixes: [String: QBEValue]
	
	public static let languages: [QBELanguage: String] = [
		"nl": QBEText("Dutch"),
		"en": QBEText("English")
	]
	
	public static let defaultLanguage: QBELanguage = "en"
	
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

	// Source: https://en.wikipedia.org/wiki/Metric_prefix
	private static let allPostfixes: [QBELanguage: [String: QBEValue]] = [
		"en": [
			"da": QBEValue(10.0),
			"h": QBEValue(100.0),
			"k": QBEValue(1000.0),
			"M": QBEValue(1000.0 * 1000.0),
			"G": QBEValue(1000.0 * 1000.0 * 1000.0),
			"T": QBEValue(1000.0 * 1000.0 * 1000.0 * 1000.0),
			"P": QBEValue(1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0),
			"E": QBEValue(1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0),
			"Z": QBEValue(1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0),
			"Y": QBEValue(1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0),

			"d": QBEValue(0.1),
			"c": QBEValue(0.1 * 0.1),
			"m": QBEValue(0.1 * 0.1 * 0.1),
			"µ": QBEValue(0.001 * 0.001),
			"n": QBEValue(0.001 * 0.001 * 0.001),
			"p": QBEValue(0.001 * 0.001 * 0.001 * 0.001),
			"f": QBEValue(0.001 * 0.001 * 0.001 * 0.001 * 0.001),
			"a": QBEValue(0.001 * 0.001 * 0.001 * 0.001 * 0.001 * 0.001),
			"z": QBEValue(0.001 * 0.001 * 0.001 * 0.001 * 0.001 * 0.001 * 0.001),
			"y": QBEValue(0.001 * 0.001 * 0.001 * 0.001 * 0.001 * 0.001 * 0.001 * 0.001),

			"Ki": QBEValue(1024.0),
			"Mi": QBEValue(1024.0 * 1024.0),
			"Gi": QBEValue(1024.0 * 1024.0 * 1024.0),
			"Ti": QBEValue(1024.0 * 1024.0 * 1024.0),
			"%": QBEValue(0.01),
			"‰": QBEValue(0.001),
			"‱": QBEValue(0.0001)
		]
	]
	
	private static let decimalSeparators: [QBELanguage: String] = [
		"en": ".",
		"nl": ","
	]
	
	private static let groupingSeparators: [QBELanguage: String] = [
		"en": ",",
		"nl": "."
	]
	
	private static let argumentSeparators: [QBELanguage: String] = [
		"en": ";",
		"nl": ";"
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
			"IN": QBEFunction.In,
			"NOT.IN": QBEFunction.NotIn,
			"SMALL": QBEFunction.Min,
			"LARGE": QBEFunction.Max,
			"PROPER": QBEFunction.Capitalize,
			"NOW": QBEFunction.Now,
			"TO.UNIX": QBEFunction.ToUnixTime,
			"FROM.UNIX": QBEFunction.FromUnixTime,
			"TO.ISO8601.UTC": QBEFunction.ToUTCISO8601,
			"TO.ISO8601": QBEFunction.ToLocalISO8601,
			"FROM.ISO8601": QBEFunction.FromISO8601,
			"TO.EXCELDATE": QBEFunction.ToExcelDate,
			"FROM.EXCELDATE": QBEFunction.FromExcelDate,
			"DATE.UTC": QBEFunction.UTCDate,
			"YEAR.UTC": QBEFunction.UTCYear,
			"MONTH.UTC": QBEFunction.UTCMonth,
			"DAY.UTC": QBEFunction.UTCDay,
			"HOUR.UTC": QBEFunction.UTCHour,
			"MINUTE.UTC": QBEFunction.UTCMinute,
			"SECOND.UTC": QBEFunction.UTCSecond,
			"DURATION": QBEFunction.Duration,
			"AFTER": QBEFunction.After,
			"NEGATE": QBEFunction.Negate,
			"FLOOR": QBEFunction.Floor,
			"CEILING": QBEFunction.Ceiling,
			"RANDSTRING": QBEFunction.RandomString,
			"WRITE.DATE": QBEFunction.ToUnicodeDateString,
			"READ.DATE": QBEFunction.FromUnicodeDateString,
			"POWER": QBEFunction.Power
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
			"IN": QBEFunction.In,
			"NIET.IN": QBEFunction.NotIn,
			"KLEINSTE": QBEFunction.Min,
			"GROOTSTE": QBEFunction.Max,
			"BEGINLETTERS": QBEFunction.Capitalize,
			"NU": QBEFunction.Now,
			"NAAR.UNIX": QBEFunction.ToUnixTime,
			"VAN.UNIX": QBEFunction.FromUnixTime,
			"NAAR.ISO8601.UTC": QBEFunction.ToUTCISO8601,
			"NAAR.ISO8601": QBEFunction.ToLocalISO8601,
			"VAN.ISO8601": QBEFunction.FromISO8601,
			"NAAR.EXCELDATUM": QBEFunction.ToExcelDate,
			"VAN.EXCELDATUM": QBEFunction.FromExcelDate,
			"DATUM.UTC": QBEFunction.UTCDate,
			"JAAR.UTC": QBEFunction.UTCYear,
			"MAAND.UTC": QBEFunction.UTCMonth,
			"DAG.UTC": QBEFunction.UTCDay,
			"UUR.UTC": QBEFunction.UTCHour,
			"MINUUT.UTC": QBEFunction.UTCMinute,
			"SECONDE.UTC": QBEFunction.UTCSecond,
			"TIJDSDUUR": QBEFunction.Duration,
			"NA": QBEFunction.After,
			"OMKEREN": QBEFunction.Negate,
			"AFRONDEN.BOVEN": QBEFunction.Ceiling,
			"AFRONDEN.BENEDEN": QBEFunction.Floor,
			"ASELECTTEKST": QBEFunction.RandomString,
			"SCHRIJF.DATUM": QBEFunction.ToUnicodeDateString,
			"LEES.DATUM": QBEFunction.FromUnicodeDateString,
			"MACHT": QBEFunction.Power
		]
	]
	
	public init(language: QBELanguage = QBELocale.defaultLanguage) {
		functions = QBELocale.allFunctions[language] ?? QBELocale.allFunctions[QBELocale.defaultLanguage]!
		constants = QBELocale.allConstants[language] ?? QBELocale.allConstants[QBELocale.defaultLanguage]!
		self.decimalSeparator = QBELocale.decimalSeparators[language]!
		self.groupingSeparator = QBELocale.groupingSeparators[language]!
		self.argumentSeparator = QBELocale.argumentSeparators[language]!
		self.postfixes = QBELocale.allPostfixes[language] ?? QBELocale.allPostfixes[QBELocale.defaultLanguage]!
		
		numberFormatter = NSNumberFormatter()
		numberFormatter.decimalSeparator = self.decimalSeparator
		numberFormatter.groupingSeparator = self.groupingSeparator
		numberFormatter.numberStyle = NSNumberFormatterStyle.DecimalStyle
		
		/* Currently, we always use the user's current calendar, regardless of the locale set. In the future, we might 
		also provide locales that set a particular time zone (e.g. a 'UTC locale'). */
		calendar = NSCalendar.autoupdatingCurrentCalendar()
		timeZone = calendar.timeZone
		
		dateFormatter = NSDateFormatter()
		dateFormatter.dateStyle = NSDateFormatterStyle.MediumStyle
		dateFormatter.timeStyle = NSDateFormatterStyle.MediumStyle
		dateFormatter.timeZone = timeZone
		dateFormatter.calendar = calendar
	}
	
	public func functionWithName(name: String) -> QBEFunction? {
		if let qu = functions[name] {
			return qu
		}
		else {
			// Case insensitive function find (slower)
			for (functionName, function) in functions {
				if name.caseInsensitiveCompare(functionName) == NSComparisonResult.OrderedSame {
					return function
				}
			}
		}
		return nil
	}
	
	public func nameForFunction(function: QBEFunction) -> String? {
		for (name, f) in functions {
			if function == f {
				return name
			}
		}
		return nil
	}
	
	/** Return a string representation of the value in the user's locale. */
	public func localStringFor(value: QBEValue) -> String {
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
			
			case .DateValue(let d):
				return dateFormatter.stringFromDate(NSDate(timeIntervalSinceReferenceDate: d))
			
			case .EmptyValue:
				return ""
		}
	}
	
	public static func stringForExchangedValue(value: QBEValue) -> String {
		switch value {
			case .DoubleValue(let d):
				return d.toString()
			
			case .IntValue(let i):
				return i.toString()
			
			default:
				return value.stringValue ?? ""
		}
	}
	
	/** Return the QBEValue for the given string in 'universal'  format (e.g. as used in exchangeable files). This uses
	 the C locale (decimal separator is '.'). */
	public static func valueForExchangedString(value: String) -> QBEValue {
		if value.isEmpty {
			return QBEValue.EmptyValue
		}
		
		// Can this string be interpreted as a number?
		if let n = value.toDouble() {
			if let i = value.toInt() where Double(i) == n {
				// This number is an integer
				return QBEValue.IntValue(i)
			}
			else {
				return QBEValue.DoubleValue(n)
			}
		}
		
		return QBEValue.StringValue(value)
	}
	
	/** Return the QBEValue for the given string in the user's locale (e.g. as presented and entered in the UI). This is
	a bit slower than the valueForExchangedString function (NSNumberFormatter.numberFromString is slower but accepts more
	formats than strtod_l, which is used in our String.toDouble implementation). */
	public func valueForLocalString(value: String) -> QBEValue {
		if value.isEmpty {
			return QBEValue.EmptyValue
		}
		
		if let n = numberFormatter.numberFromString(value) {
			if n.isEqualToNumber(NSNumber(integer: n.integerValue)) {
				return QBEValue.IntValue(n.integerValue)
			}
			else {
				return QBEValue.DoubleValue(n.doubleValue)
			}
		}
		return QBEValue.StringValue(value)
	}
	
	public func csvRow(row: [QBEValue]) -> String {
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
				
			case .DateValue(let d):
				line += NSDate(timeIntervalSinceReferenceDate: d).iso8601FormattedUTCDate
				
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