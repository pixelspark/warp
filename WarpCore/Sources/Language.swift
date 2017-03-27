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
	public var blobQualifier: Character = "`";
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

	public static let encodings: [String: String.Encoding] = [
		"UTF-8": .utf8,
		"UTF-16": .utf16,
		"UTF-32": .utf32,
		"ASCII": .ascii,
		"LATIN1": .isoLatin1,
		"LATIN2": .isoLatin2,
		"MAC-ROMAN": .macOSRoman,
		"CP1250": .windowsCP1250,
		"CP1251": .windowsCP1251,
		"CP1252": .windowsCP1252,
	]
	
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
			"UPPER": Function.uppercase,
			"LOWER": Function.lowercase,
			"ABS": Function.absolute,
			"AND": Function.and,
			"OR": Function.or,
			"SQRT": Function.sqrt,
			"SIN": Function.sin,
			"COS": Function.cos,
			"TAN": Function.tan,
			"ASIN": Function.asin,
			"ACOS": Function.acos,
			"ATAN": Function.atan,
			"SINH": Function.sinh,
			"COSH": Function.cosh,
			"TANH": Function.tanh,
			"IF": Function.`if`,
			"CONCAT": Function.concat,
			"LEFT": Function.left,
			"RIGHT": Function.right,
			"MID": Function.mid,
			"LENGTH": Function.length,
			"LOG": Function.log,
			"NOT": Function.not,
			"XOR": Function.xor,
			"REPLACE": Function.substitute,
			"REPLACE.PATTERN": Function.regexSubstitute,
			"TRIM": Function.trim,
			"SUM": Function.sum,
			"COUNT": Function.count,
			"AVERAGE": Function.average,
			"COUNTA": Function.countAll,
			"MIN": Function.min,
			"MAX": Function.max,
			"EXP": Function.exp,
			"LN": Function.ln,
			"ROUND": Function.round,
			"CHOOSE": Function.choose,
			"RANDBETWEEN": Function.randomBetween,
			"RAND": Function.random,
			"COALESCE": Function.coalesce,
			"IFERROR": Function.ifError,
			"PACK": Function.pack,
			"NORM.INV": Function.normalInverse,
			"SIGN": Function.sign,
			"SPLIT": Function.split,
			"ITEMS": Function.items,
			"SIMILARITY": Function.levenshtein,
			"ENCODEURL": Function.urlEncode,
			"IN": Function.`in`,
			"NOT.IN": Function.notIn,
			"SMALL": Function.min,
			"LARGE": Function.max,
			"PROPER": Function.capitalize,
			"NOW": Function.now,
			"TO.UNIX": Function.toUnixTime,
			"FROM.UNIX": Function.fromUnixTime,
			"TO.ISO8601.UTC": Function.toUTCISO8601,
			"TO.ISO8601": Function.toLocalISO8601,
			"FROM.ISO8601": Function.fromISO8601,
			"TO.EXCELDATE": Function.toExcelDate,
			"FROM.EXCELDATE": Function.fromExcelDate,
			"DATE.UTC": Function.utcDate,
			"YEAR.UTC": Function.utcYear,
			"MONTH.UTC": Function.utcMonth,
			"DAY.UTC": Function.utcDay,
			"HOUR.UTC": Function.utcHour,
			"MINUTE.UTC": Function.utcMinute,
			"SECOND.UTC": Function.utcSecond,
			"DURATION": Function.duration,
			"AFTER": Function.after,
			"NEGATE": Function.negate,
			"FLOOR": Function.floor,
			"CEILING": Function.ceiling,
			"RANDSTRING": Function.randomString,
			"WRITE.DATE": Function.toUnicodeDateString,
			"READ.DATE": Function.fromUnicodeDateString,
			"POWER": Function.power,
			"UUID": Function.uuid,
			"MEDIAN.LOW": Function.medianLow,
			"MEDIAN.HIGH": Function.medianHigh,
			"MEDIAN.PACK": Function.medianPack,
			"MEDIAN": Function.median,
			"STDEV.P": Function.standardDeviationPopulation,
			"STDEV.S": Function.standardDeviationSample,
			"VAR.P": Function.variancePopulation,
			"VAR.S": Function.varianceSample,
			"FROM.JSON": Function.jsonDecode,
			"READ.NUMBER": Function.parseNumber,
			"HILBERT.D": Function.hilbertXYToD,
			"HILBERT.X": Function.hilbertDToX,
			"HILBERT.Y": Function.hilbertDToY,
			"POWER.UP": Function.powerUp,
			"POWER.DOWN": Function.powerDown,
			"BASE64.ENCODE": Function.base64Encode,
			"BASE64.DECODE": Function.base64Decode,
			"HEX.ENCODE": Function.hexEncode,
			"HEX.DECODE": Function.hexDecode,
			"SIZE.OF": Function.numberOfBytes,
			"ENCODE": Function.encodeString,
			"DECODE": Function.decodeString,
		],
		
		"nl": [
			"ABS": Function.absolute,
			"BOOGCOS": Function.acos,
			"EN": Function.and,
			"BOOGSIN": Function.asin,
			"BOOGTAN": Function.atan,
			"GEMIDDELDE": Function.average,
			"KIEZEN": Function.choose,
			"TEKST.SAMENVOEGEN": Function.concat,
			"COS": Function.cos,
			"COSH": Function.cosh,
			"AANTAL": Function.count,
			"AANTALARG": Function.countAll,
			"EXP": Function.exp,
			"ALS": Function.`if`,
			"ALS.FOUT": Function.ifError,
			"LINKS": Function.left,
			"LENGTE": Function.length,
			"LN": Function.ln,
			"LOG": Function.log,
			"KLEINE.LETTERS": Function.lowercase,
			"MAX": Function.max,
			"DEEL": Function.mid,
			"MIN": Function.min,
			"NIET": Function.not,
			"OF": Function.or,
			"ASELECTTUSSEN": Function.randomBetween,
			"ASELECT": Function.random,
			"RECHTS": Function.right,
			"AFRONDEN": Function.round,
			"SIN": Function.sin,
			"SINH": Function.sinh,
			"WORTEL": Function.sqrt,
			"SUBSTITUEREN.PATROON": Function.regexSubstitute,
			"SUBSTITUEREN": Function.substitute,
			"SOM": Function.sum,
			"TAN": Function.tan,
			"TANH": Function.tanh,
			"SPATIES.WISSEN": Function.trim,
			"HOOFDLETTERS": Function.uppercase,
			"EX.OF": Function.xor,
			"EERSTE.GELDIG": Function.coalesce,
			"INPAKKEN": Function.pack,
			"NORM.INV.N": Function.normalInverse,
			"POS.NEG": Function.sign,
			"SPLITS": Function.split,
			"ITEMS": Function.items,
			"GELIJKENIS": Function.levenshtein,
			"URL.CODEREN": Function.urlEncode,
			"IN": Function.`in`,
			"NIET.IN": Function.notIn,
			"KLEINSTE": Function.min,
			"GROOTSTE": Function.max,
			"BEGINLETTERS": Function.capitalize,
			"NU": Function.now,
			"NAAR.UNIX": Function.toUnixTime,
			"VAN.UNIX": Function.fromUnixTime,
			"NAAR.ISO8601.UTC": Function.toUTCISO8601,
			"NAAR.ISO8601": Function.toLocalISO8601,
			"VAN.ISO8601": Function.fromISO8601,
			"NAAR.EXCELDATUM": Function.toExcelDate,
			"VAN.EXCELDATUM": Function.fromExcelDate,
			"DATUM.UTC": Function.utcDate,
			"JAAR.UTC": Function.utcYear,
			"MAAND.UTC": Function.utcMonth,
			"DAG.UTC": Function.utcDay,
			"UUR.UTC": Function.utcHour,
			"MINUUT.UTC": Function.utcMinute,
			"SECONDE.UTC": Function.utcSecond,
			"TIJDSDUUR": Function.duration,
			"NA": Function.after,
			"OMKEREN": Function.negate,
			"AFRONDEN.BOVEN": Function.ceiling,
			"AFRONDEN.BENEDEN": Function.floor,
			"ASELECTTEKST": Function.randomString,
			"SCHRIJF.DATUM": Function.toUnicodeDateString,
			"LEES.DATUM": Function.fromUnicodeDateString,
			"MACHT": Function.power,
			"UUID": Function.uuid,
			"AANTAL.UNIEK": Function.countDistinct,
			"MEDIAAN.LAAG": Function.medianLow,
			"MEDIAAN.HOOG": Function.medianHigh,
			"MEDIAAN.PAKKET": Function.medianPack,
			"MEDIAAN": Function.median,
			"STDEV.P": Function.standardDeviationPopulation,
			"STDEV.S": Function.standardDeviationSample,
			"VAR.P": Function.variancePopulation,
			"VAR.S": Function.varianceSample,
			"VAN.JSON": Function.jsonDecode,
			"LEES.GETAL": Function.parseNumber,
			"HILBERT.D": Function.hilbertXYToD,
			"HILBERT.X": Function.hilbertDToX,
			"HILBERT.Y": Function.hilbertDToY,
			"MACHT.OMHOOG": Function.powerUp,
			"MACHT.OMLAAG": Function.powerDown,
			"BASE64.ENCODEREN": Function.base64Encode,
			"BASE64.DECODEREN": Function.base64Decode,
			"HEX.ENCODEREN": Function.hexEncode,
			"HEX.DECODEREN": Function.hexDecode,
			"ENCODEREN": Function.encodeString,
			"DECODEREN": Function.decodeString,
			"GROOTTE.VAN": Function.numberOfBytes,
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

			case .blob(let b):
				let s = ByteCountFormatter.string(fromByteCount: Int64(b.count), countStyle: ByteCountFormatter.CountStyle.file)
				return "[\(s)]";
			
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

			case .blob(let b):
				return b.base64EncodedString()
			
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

			case .blob(let d):
				line += "\(csvStringQualifier)\(d.base64EncodedString(options: []))\(csvStringQualifier)"
			
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
