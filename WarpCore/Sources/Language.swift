/* Copyright (c) 2014-2016 Pixelspark, Tommy van der Vorst

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
import Foundation

/** Localize a string using the localization bundle included with the framework (and not the main application bundle). */
internal func translationForString(_ text: String) -> String {
	let bundle = Bundle(for: Language.self)
	return NSLocalizedString(text, tableName: nil, bundle: bundle, value: text, comment: "")
}

/** Language provides localized names for functions and other aspects of the formula grammar facing end users. */
public class Language {
	public typealias LanguageIdentifier = String
	
	public var decimalSeparator: String
	public var groupingSeparator: String
	public var stringQualifier: Character = "\""
	public var stringQualifierEscape = "\"\""
	public var argumentSeparator = ";"
	public var currentCellIdentifier = "@"
	public var csvFieldSeparator = ";"
	public var csvLineSeparator = "\r\n"
	public var csvStringQualifier = "\""
	public var csvStringEscaper = "\"\""
	public var commonFieldSeparators = [";",",","|","\t"]
	public var numberFormatter: NumberFormatter
	public var dateFormatter: DateFormatter
	public var timeZone: TimeZone
	public var calendar: Calendar
	public var constants: [Value: String]
	public let functions: [String: Function]
	public let postfixes: [String: Value]
	
	public static let languages: [LanguageIdentifier: String] = [
		"nl": translationForString("Dutch"),
		"en": translationForString("English")
	]
	
	public static let defaultLanguage: LanguageIdentifier = "en"
	
	private static let allConstants: [LanguageIdentifier: [Value: String]] = [
		"en": [
			Value(true): "TRUE",
			Value(false): "FALSE",
			Value(3.141592654): "PI",
			Value.empty: "NULL",
			Value.invalid: "ERROR"
		],
		
		"nl": [
			Value(true): "WAAR",
			Value(false): "ONWAAR",
			Value(3.141592654): "PI",
			Value.empty: "LEEG",
			Value.invalid: "FOUT"
		]
	]

	// Source: https://en.wikipedia.org/wiki/Metric_prefix
	private static let allPostfixes: [LanguageIdentifier: [String: Value]] = [
		"en": [
			"da": Value(10.0),
			"h": Value(100.0),
			"k": Value(1000.0),
			"M": Value(1000.0 * 1000.0),
			"G": Value(1000.0 * 1000.0 * 1000.0),
			"T": Value(1000.0 * 1000.0 * 1000.0 * 1000.0),
			"P": Value(1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0),
			"E": Value(1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0),
			"Z": Value(1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0),
			"Y": Value(1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0 * 1000.0),

			"d": Value(0.1),
			"c": Value(0.1 * 0.1),
			"m": Value(0.1 * 0.1 * 0.1),
			"µ": Value(0.001 * 0.001),
			"n": Value(0.001 * 0.001 * 0.001),
			"p": Value(0.001 * 0.001 * 0.001 * 0.001),
			"f": Value(0.001 * 0.001 * 0.001 * 0.001 * 0.001),
			"a": Value(0.001 * 0.001 * 0.001 * 0.001 * 0.001 * 0.001),
			"z": Value(0.001 * 0.001 * 0.001 * 0.001 * 0.001 * 0.001 * 0.001),
			"y": Value(0.001 * 0.001 * 0.001 * 0.001 * 0.001 * 0.001 * 0.001 * 0.001),

			"Ki": Value(1024.0),
			"Mi": Value(1024.0 * 1024.0),
			"Gi": Value(1024.0 * 1024.0 * 1024.0),
			"Ti": Value(1024.0 * 1024.0 * 1024.0),
			"%": Value(0.01),
			"‰": Value(0.001),
			"‱": Value(0.0001)
		]
	]
	
	private static let decimalSeparators: [LanguageIdentifier: String] = [
		"en": ".",
		"nl": ","
	]
	
	private static let groupingSeparators: [LanguageIdentifier: String] = [
		"en": ",",
		"nl": "."
	]
	
	private static let argumentSeparators: [LanguageIdentifier: String] = [
		"en": ";",
		"nl": ";"
	]
	
	private static let allFunctions: [LanguageIdentifier: [String: Function]] = [
		"en": [
			"UPPER": Function.Uppercase,
			"LOWER": Function.Lowercase,
			"ABS": Function.Absolute,
			"AND": Function.And,
			"OR": Function.Or,
			"SQRT": Function.Sqrt,
			"SIN": Function.Sin,
			"COS": Function.Cos,
			"TAN": Function.Tan,
			"ASIN": Function.Asin,
			"ACOS": Function.Acos,
			"ATAN": Function.Atan,
			"SINH": Function.Sinh,
			"COSH": Function.Cosh,
			"TANH": Function.Tanh,
			"IF": Function.If,
			"CONCAT": Function.Concat,
			"LEFT": Function.Left,
			"RIGHT": Function.Right,
			"MID": Function.Mid,
			"LENGTH": Function.Length,
			"LOG": Function.Log,
			"NOT": Function.Not,
			"XOR": Function.Xor,
			"REPLACE": Function.Substitute,
			"REPLACE.PATTERN": Function.RegexSubstitute,
			"TRIM": Function.Trim,
			"SUM": Function.Sum,
			"COUNT": Function.Count,
			"AVERAGE": Function.Average,
			"COUNTA": Function.CountAll,
			"MIN": Function.Min,
			"MAX": Function.Max,
			"EXP": Function.Exp,
			"LN": Function.Ln,
			"ROUND": Function.Round,
			"CHOOSE": Function.Choose,
			"RANDBETWEEN": Function.RandomBetween,
			"RAND": Function.Random,
			"COALESCE": Function.Coalesce,
			"IFERROR": Function.IfError,
			"PACK": Function.Pack,
			"NORM.INV": Function.NormalInverse,
			"SIGN": Function.Sign,
			"SPLIT": Function.Split,
			"NTH": Function.Nth,
			"ITEMS": Function.Items,
			"SIMILARITY": Function.Levenshtein,
			"ENCODEURL": Function.URLEncode,
			"IN": Function.In,
			"NOT.IN": Function.NotIn,
			"SMALL": Function.Min,
			"LARGE": Function.Max,
			"PROPER": Function.Capitalize,
			"NOW": Function.Now,
			"TO.UNIX": Function.ToUnixTime,
			"FROM.UNIX": Function.FromUnixTime,
			"TO.ISO8601.UTC": Function.ToUTCISO8601,
			"TO.ISO8601": Function.ToLocalISO8601,
			"FROM.ISO8601": Function.FromISO8601,
			"TO.EXCELDATE": Function.ToExcelDate,
			"FROM.EXCELDATE": Function.FromExcelDate,
			"DATE.UTC": Function.UTCDate,
			"YEAR.UTC": Function.UTCYear,
			"MONTH.UTC": Function.UTCMonth,
			"DAY.UTC": Function.UTCDay,
			"HOUR.UTC": Function.UTCHour,
			"MINUTE.UTC": Function.UTCMinute,
			"SECOND.UTC": Function.UTCSecond,
			"DURATION": Function.Duration,
			"AFTER": Function.After,
			"NEGATE": Function.Negate,
			"FLOOR": Function.Floor,
			"CEILING": Function.Ceiling,
			"RANDSTRING": Function.RandomString,
			"WRITE.DATE": Function.ToUnicodeDateString,
			"READ.DATE": Function.FromUnicodeDateString,
			"POWER": Function.Power,
			"UUID": Function.UUID,
			"MEDIAN.LOW": Function.MedianLow,
			"MEDIAN.HIGH": Function.MedianHigh,
			"MEDIAN.PACK": Function.MedianPack,
			"MEDIAN": Function.Median,
			"STDEV.P": Function.StandardDeviationPopulation,
			"STDEV.S": Function.StandardDeviationSample,
			"VAR.P": Function.VariancePopulation,
			"VAR.S": Function.VarianceSample,
			"FROM.JSON": Function.JSONDecode,
			"READ.NUMBER": Function.ParseNumber
		],
		
		"nl": [
			"ABS": Function.Absolute,
			"BOOGCOS": Function.Acos,
			"EN": Function.And,
			"BOOGSIN": Function.Asin,
			"BOOGTAN": Function.Atan,
			"GEMIDDELDE": Function.Average,
			"KIEZEN": Function.Choose,
			"TEKST.SAMENVOEGEN": Function.Concat,
			"COS": Function.Cos,
			"COSH": Function.Cosh,
			"AANTAL": Function.Count,
			"AANTALARG": Function.CountAll,
			"EXP": Function.Exp,
			"ALS": Function.If,
			"ALS.FOUT": Function.IfError,
			"LINKS": Function.Left,
			"LENGTE": Function.Length,
			"LN": Function.Ln,
			"LOG": Function.Log,
			"KLEINE.LETTERS": Function.Lowercase,
			"MAX": Function.Max,
			"DEEL": Function.Mid,
			"MIN": Function.Min,
			"NIET": Function.Not,
			"OF": Function.Or,
			"ASELECTTUSSEN": Function.RandomBetween,
			"ASELECT": Function.Random,
			"RECHTS": Function.Right,
			"AFRONDEN": Function.Round,
			"SIN": Function.Sin,
			"SINH": Function.Sinh,
			"WORTEL": Function.Sqrt,
			"SUBSTITUEREN.PATROON": Function.RegexSubstitute,
			"SUBSTITUEREN": Function.Substitute,
			"SOM": Function.Sum,
			"TAN": Function.Tan,
			"TANH": Function.Tanh,
			"SPATIES.WISSEN": Function.Trim,
			"HOOFDLETTERS": Function.Uppercase,
			"EX.OF": Function.Xor,
			"EERSTE.GELDIG": Function.Coalesce,
			"INPAKKEN": Function.Pack,
			"NORM.INV.N": Function.NormalInverse,
			"POS.NEG": Function.Sign,
			"SPLITS": Function.Split,
			"NDE": Function.Nth,
			"ITEMS": Function.Items,
			"GELIJKENIS": Function.Levenshtein,
			"URL.CODEREN": Function.URLEncode,
			"IN": Function.In,
			"NIET.IN": Function.NotIn,
			"KLEINSTE": Function.Min,
			"GROOTSTE": Function.Max,
			"BEGINLETTERS": Function.Capitalize,
			"NU": Function.Now,
			"NAAR.UNIX": Function.ToUnixTime,
			"VAN.UNIX": Function.FromUnixTime,
			"NAAR.ISO8601.UTC": Function.ToUTCISO8601,
			"NAAR.ISO8601": Function.ToLocalISO8601,
			"VAN.ISO8601": Function.FromISO8601,
			"NAAR.EXCELDATUM": Function.ToExcelDate,
			"VAN.EXCELDATUM": Function.FromExcelDate,
			"DATUM.UTC": Function.UTCDate,
			"JAAR.UTC": Function.UTCYear,
			"MAAND.UTC": Function.UTCMonth,
			"DAG.UTC": Function.UTCDay,
			"UUR.UTC": Function.UTCHour,
			"MINUUT.UTC": Function.UTCMinute,
			"SECONDE.UTC": Function.UTCSecond,
			"TIJDSDUUR": Function.Duration,
			"NA": Function.After,
			"OMKEREN": Function.Negate,
			"AFRONDEN.BOVEN": Function.Ceiling,
			"AFRONDEN.BENEDEN": Function.Floor,
			"ASELECTTEKST": Function.RandomString,
			"SCHRIJF.DATUM": Function.ToUnicodeDateString,
			"LEES.DATUM": Function.FromUnicodeDateString,
			"MACHT": Function.Power,
			"UUID": Function.UUID,
			"AANTAL.UNIEK": Function.CountDistinct,
			"MEDIAAN.LAAG": Function.MedianLow,
			"MEDIAAN.HOOG": Function.MedianHigh,
			"MEDIAAN.PAKKET": Function.MedianPack,
			"MEDIAAN": Function.Median,
			"STDEV.P": Function.StandardDeviationPopulation,
			"STDEV.S": Function.StandardDeviationSample,
			"VAR.P": Function.VariancePopulation,
			"VAR.S": Function.VarianceSample,
			"VAN.JSON": Function.JSONDecode,
			"LEES.GETAL": Function.ParseNumber
		]
	]
	
	public init(language: LanguageIdentifier = Language.defaultLanguage) {
		functions = Language.allFunctions[language] ?? Language.allFunctions[Language.defaultLanguage]!
		constants = Language.allConstants[language] ?? Language.allConstants[Language.defaultLanguage]!
		self.decimalSeparator = Language.decimalSeparators[language]!
		self.groupingSeparator = Language.groupingSeparators[language]!
		self.argumentSeparator = Language.argumentSeparators[language]!
		self.postfixes = Language.allPostfixes[language] ?? Language.allPostfixes[Language.defaultLanguage]!
		
		numberFormatter = NumberFormatter()
		numberFormatter.decimalSeparator = self.decimalSeparator
		numberFormatter.groupingSeparator = self.groupingSeparator
		numberFormatter.numberStyle = NumberFormatter.Style.decimal
		
		/* Currently, we always use the user's current calendar, regardless of the locale set. In the future, we might 
		also provide locales that set a particular time zone (e.g. a 'UTC locale'). */
		calendar = Calendar.autoupdatingCurrent
		timeZone = calendar.timeZone
		
		dateFormatter = DateFormatter()
		dateFormatter.dateStyle = DateFormatter.Style.medium
		dateFormatter.timeStyle = DateFormatter.Style.medium
		dateFormatter.timeZone = timeZone
		dateFormatter.calendar = calendar
	}
	
	public func functionWithName(_ name: String) -> Function? {
		if let qu = functions[name] {
			return qu
		}
		else {
			// Case insensitive function find (slower)
			for (functionName, function) in functions {
				if name.caseInsensitiveCompare(functionName) == ComparisonResult.orderedSame {
					return function
				}
			}
		}
		return nil
	}
	
	public func nameForFunction(_ function: Function) -> String? {
		for (name, f) in functions {
			if function == f {
				return name
			}
		}
		return nil
	}
	
	/** Return a string representation of the value in the user's locale. */
	public func localStringFor(_ value: Value) -> String {
		switch value {
			case .string(let s):
				return s
			
			case .bool(let b):
				return constants[Value(b)]!
			
			case .int(let i):
				return numberFormatter.string(for: i)!
			
			case .double(let d):
				return numberFormatter.string(for: d)!
			
			case .invalid:
				return translationForString("n/a")
			
			case .date(let d):
				return dateFormatter.string(from: Date(timeIntervalSinceReferenceDate: d))
			
			case .empty:
				return ""
		}
	}
	
	public static func stringForExchangedValue(_ value: Value) -> String {
		switch value {
			case .double(let d):
				return d.toString()
			
			case .int(let i):
				return i.toString()
			
			default:
				return value.stringValue ?? ""
		}
	}
	
	/** Return the Value for the given string in 'universal'  format (e.g. as used in exchangeable files). This uses
	 the C locale (decimal separator is '.'). */
	public static func valueForExchangedString(_ value: String) -> Value {
		if value.isEmpty {
			return Value.empty
		}
		
		// Can this string be interpreted as a number?
		if let n = value.toDouble() {
			if let i = value.toInt(), Double(i) == n {
				// This number is an integer
				return Value.int(i)
			}
			else {
				return Value.double(n)
			}
		}
		
		return Value.string(value)
	}
	
	/** Return the Value for the given string in the user's locale (e.g. as presented and entered in the UI). This is
	a bit slower than the valueForExchangedString function (NSNumberFormatter.numberFromString is slower but accepts more
	formats than strtod_l, which is used in our String.toDouble implementation). */
	public func valueForLocalString(_ value: String) -> Value {
		if value.isEmpty {
			return Value.empty
		}
		
		if let n = numberFormatter.number(from: value) {
			if n.isEqual(to: NSNumber(value: n.intValue)) {
				return Value.int(n.intValue)
			}
			else {
				return Value.double(n.doubleValue)
			}
		}
		return Value.string(value)
	}
	
	public func csvRow(_ row: [Value]) -> String {
		var line = ""
		for columnIndex in 0...row.count-1 {
			let value = row[columnIndex]
			switch value {
			case .string(let s):
				line += "\(csvStringQualifier)\(s.replacingOccurrences(of: csvStringQualifier, with: csvStringEscaper))\(csvStringQualifier)"
			
			case .double(let d):
				// FIXME: use decimalSeparator from locale
				line += "\(d)"
				
			case .int(let i):
				line += "\(i)"
				
			case .bool(let b):
				line += (b ? "1" : "0")
				
			case .invalid:
				break
				
			case .date(let d):
				line += Date(timeIntervalSinceReferenceDate: d).iso8601FormattedUTCDate
				
			case .empty:
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
