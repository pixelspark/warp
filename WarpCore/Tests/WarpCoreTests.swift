import Cocoa
import XCTest
@testable import WarpCore

class WarpCoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    } 
	
	func testStatistics() {
		let moving = Moving(size: 10, items: [0,10,0,10,0,10,10,10,0,0,10,0,10,0,10,999999999999,0,5,5,5,5,5,5,5,5,5,5,5])
		XCTAssert(moving.sample.n == 10, "Moving should discard old samples properly")
		XCTAssert(moving.sample.mean == 5.0, "Average of test sample should be exactly 5")
		XCTAssert(moving.sample.stdev == 0.0, "Test sample has no deviations")

		let (lower, upper) = moving.sample.confidenceInterval(0.90)
		XCTAssert(lower <= upper, "Test sample confidence interval must not be flipped")
		XCTAssert(lower == 5.0 && upper == 5.0, "Test sample has confidence interval that is [5,5]")

		// Add a value to the moving average and try again
		moving.add(100)
		XCTAssert(moving.sample.n == 10, "Moving should discard old samples properly")
		XCTAssert(moving.sample.mean > 5.0, "Average of test sample should be > 5")
		XCTAssert(moving.sample.stdev > 0.0, "Test sample has a deviation now")
		let (lower2, upper2) = moving.sample.confidenceInterval(0.90)
		XCTAssert(lower2 <= upper2, "Test sample confidence interval must not be flipped")
		XCTAssert(lower2 < 5.0 && upper2 > 5.0, "Test sample has confidence interval that is wider")

		let (lower3, upper3) = moving.sample.confidenceInterval(0.95)
		XCTAssert(lower3 < lower2 && upper3 > upper2, "A more confident interval is wider")
	}

	func testArithmetic() {
		// Strings
		XCTAssert(Value("hello") == Value("hello"), "String equality")
		XCTAssert(Value("hello") != Value("HELLO"), "String equality is case sensitive")
		XCTAssert(Value(1337) == Value("1337"), "Numbers are strings")
		XCTAssert("Tommy".levenshteinDistance("tommy") == 1, "Levenshtein is case sensitive")
		XCTAssert("Tommy".levenshteinDistance("Tomy") == 1, "Levenshtein recognizes deletes")
		XCTAssert("Tommy".levenshteinDistance("ymmoT") == 4, "Levenshtein recognizes moves")
		XCTAssert("Tommy".levenshteinDistance("TommyV") == 1, "Levenshtein recognizes adds")

		// Booleans
		XCTAssert(true.toDouble()==1.0, "True is double 1.0")
		XCTAssert(false.toDouble()==0.0, "False is double 0.0")
		XCTAssert(true.toInt()==1, "True is integer 1")
		XCTAssert(false.toInt()==0, "False is integer 0")

		// Invalid value
		XCTAssert(Value.invalid != Value.invalid, "Invalid value does not equal itself")
		XCTAssert(Value.invalid != Value.empty, "Invalid value does not equal empty value")
		XCTAssert(Value.invalid != Value.bool(false), "Invalid value does not equal false value")

		// Empty value
		XCTAssert(Value.empty == Value.empty, "Empty equals empty")
		XCTAssert(Value.empty != Value.string(""), "Empty does not equal empty string")
		XCTAssert(Value.empty != Value.int(0), "Empty does not equal zero integer")
		XCTAssert(Value.empty != Value.bool(false), "Empty does not equal false")

		// Numeric operations
		XCTAssert(Value(12) * Value(13) == Value(156), "Integer multiplication")
		XCTAssert(Value(12.2) * Value(13.3) == Value(162.26), "Double multiplication")
		XCTAssert(Value(12) * Value(13) == Value(156), "Integer multiplication to double")
		XCTAssert(Value(12) / Value(2) == Value(6), "Integer division to double")
		XCTAssert(!(Value(10.0) / Value(0)).isValid, "Division by zero")
		XCTAssert(Value(Double(Int.max)+1.0).intValue == nil, "Doubles that are too large to be converted to Int should not be representible as integer value")
		XCTAssert(Value(Double(Int.min)-1.0).intValue == nil, "Doubles that are too large negatively to be converted to Int should not be representible as integer value")

		// String operations
		XCTAssert(Value("1337") & Value("h4x0r") == Value("1337h4x0r"), "String string concatenation")

		// Implicit conversions
		XCTAssert((Value(13) + Value("37")) == Value.int(50), "Integer plus string results in integer")
		XCTAssert(Value("13") + Value(37) == Value.int(50), "String plus integer results in integer")
		XCTAssert(Value("13") + Value("37") == Value.int(50), "String plus integer results in integer")
		XCTAssert(Value(true) + Value(true) == Value.int(2), "True + true == 2")
		XCTAssert(!(Value(1) + Value.empty).isValid, "1 + Empty is not valid")
		XCTAssert(!(Value.empty + Value.empty).isValid, "Empty + Empty is not valud")
		XCTAssert(!(Value(12) + Value.invalid).isValid, "Int + Invalid is not valid")

		XCTAssert((Value(13) - Value("37")) == Value.int(-24), "Integer minus string results in integer")
		XCTAssert(Value("13") - Value(37) == Value.int(-24), "String minus integer results in integer")
		XCTAssert(Value("13") - Value("37") == Value.int(-24), "String minus integer results in integer")
		XCTAssert(Value(true) - Value(true) == Value.int(0), "True + true == 2")
		XCTAssert(!(Value(1) - Value.empty).isValid, "1 - Empty is not valid")
		XCTAssert(!(Value.empty - Value.empty).isValid, "Empty - Empty is  ot valud")
		XCTAssert(!(Value(12) - Value.invalid).isValid, "Int - Invalid is not valid")

		// Numeric comparisons
		XCTAssert((Value(12) < Value(25)) == Value(true), "Less than")
		XCTAssert((Value(12) > Value(25)) == Value(false), "Greater than")
		XCTAssert((Value(12) <= Value(25)) == Value(true), "Less than or equal")
		XCTAssert((Value(12) >= Value(25)) == Value(false), "Greater than or equal")
		XCTAssert((Value(12) <= Value(12)) == Value(true), "Less than or equal")
		XCTAssert((Value(12) >= Value(12)) == Value(true), "Greater than or equal")

		// Equality
		XCTAssert((Value(12.0) == Value(12)) == Value(true), "Double == int")
		XCTAssert((Value(12) == Value(12.0)) == Value(true), "Int == double")
		XCTAssert((Value(12.0) != Value(12)) == Value(false), "Double != int")
		XCTAssert((Value(12) != Value(12.0)) == Value(false), "Int != double")
		XCTAssert(Value("12") == Value(12), "String number is treated as number")
		XCTAssert((Value("12") + Value("13")) == Value(25), "String number is treated as number")
		XCTAssert(Value.empty == Value.empty, "Empty equals empty")
		XCTAssert(!(Value.invalid == Value.invalid), "Invalid value equals nothing")

		// Inequality
		XCTAssert(Value.empty != Value(0), "Empty is not equal to zero")
		XCTAssert(Value.empty != Value(Double.nan), "Empty is not equal to double NaN")
		XCTAssert(Value.empty != Value(""), "Empty is not equal to empty string")
		XCTAssert(Value.invalid != Value.invalid, "Invalid value inequals other invalid value")

		// Packs
		XCTAssert(Pack("a,b,c,d").count == 4, "Pack format parser works")
		XCTAssert(Pack("a,b,c,d,").count == 5, "Pack format parser works")
		XCTAssert(Pack("a,b$0,c$1$0,d$0$1").count == 4, "Pack format parser works")
		XCTAssert(Pack(",").count == 2, "Pack format parser works")
		XCTAssert(Pack("").count == 0, "Pack format parser works")
		XCTAssert(Pack(["Tommy", "van$,der,Vorst"]).stringValue == "Tommy,van$1$0der$0Vorst", "Pack writer properly escapes")
	}

	func testFunctions() {
		for fun in Function.allFunctions {
			switch fun {

			case .Xor:
				XCTAssert(Function.Xor.apply([Value(true), Value(true)]) == Value(false), "XOR(true, true)")
				XCTAssert(Function.Xor.apply([Value(true), Value(false)]) == Value(true), "XOR(true, false)")
				XCTAssert(Function.Xor.apply([Value(false), Value(false)]) == Value(false), "XOR(false, false)")

			case .Identity:
				XCTAssert(Function.Identity.apply([Value(1.337)]) == Value(1.337),"Identity")

			case .Not:
				XCTAssert(Function.Not.apply([Value(false)]) == Value(true), "Not")

			case .And:
				XCTAssert(Function.And.apply([Value(true), Value(true)]) == Value(true), "AND(true, true)")
				XCTAssert(!Function.And.apply([Value(true), Value.invalid]).isValid, "AND(true, invalid)")
				XCTAssert(Function.And.apply([Value(true), Value(false)]) == Value(false), "AND(true, false)")
				XCTAssert(Function.And.apply([Value(false), Value(false)]) == Value(false), "AND(false, false)")

			case .Lowercase:
				XCTAssert(Function.Lowercase.apply([Value("Tommy")]) == Value("tommy"), "Lowercase")

			case .Uppercase:
				XCTAssert(Function.Uppercase.apply([Value("Tommy")]) == Value("TOMMY"), "Uppercase")

			case .Absolute:
				XCTAssert(Function.Absolute.apply([Value(-1)]) == Value(1), "Absolute")

			case .StandardDeviationSample:
				XCTAssert(Function.StandardDeviationSample.apply([1.0, 2.0, 3.0].map { return Value($0) }) == Value(1.0), "Standard deviation of sample works")
				XCTAssert(!Function.StandardDeviationSample.apply([1.0].map { return Value($0) }).isValid, "Standard deviation of sample works")
				XCTAssert(!Function.StandardDeviationSample.apply([]).isValid, "Standard deviation of sample works")

			case .StandardDeviationPopulation:
				XCTAssert(Function.StandardDeviationPopulation.apply([1.0, 2.0, 3.0].map { return Value($0) }) == Value(sqrt(2.0 / 3.0)), "Standard deviation of sample works")
				XCTAssert(Function.StandardDeviationPopulation.apply([1.0].map { return Value($0) }) == Value(0.0), "Standard deviation of sample works")
				XCTAssert(!Function.StandardDeviationPopulation.apply([]).isValid, "Standard deviation of sample works")

			case .VarianceSample:
				XCTAssert(Function.VarianceSample.apply([1.0, 2.0, 3.0].map { return Value($0) }) == Value(1.0), "Variance of sample works")
				XCTAssert(!Function.VarianceSample.apply([1.0].map { return Value($0) }).isValid, "Variance of sample works")
				XCTAssert(!Function.VarianceSample.apply([]).isValid, "Variance of sample works")

			case .VariancePopulation:
				XCTAssert(Function.VariancePopulation.apply([1.0, 2.0, 3.0].map { return Value($0) }) == Value(2.0 / 3.0), "Variance of sample works")
				XCTAssert(Function.VariancePopulation.apply([1.0].map { return Value($0) }) == Value(0.0), "Variance of sample works")
				XCTAssert(!Function.VariancePopulation.apply([]).isValid, "Variance of sample works")

			case .Count:
				XCTAssert(Function.Count.apply([]) == Value(0), "Empty count returns zero")
				XCTAssert(Function.Count.apply([Value(1), Value(1), Value.invalid, Value.empty]) == Value(2), "Count does not include invalid values and empty values")

			case .Median:
				XCTAssert(Function.Median.apply([Value(1), Value(1), Value(2), Value.invalid, Value.empty]) == Value(1), "Median ignores invalid values and takes averages")

			case .MedianLow:
				XCTAssert(Function.MedianLow.apply([Value(1), Value(1), Value(2), Value(2), Value.invalid, Value.empty]) == Value(1), "Median low ignores invalid values and takes lower value")

			case .MedianHigh:
				XCTAssert(Function.MedianHigh.apply([Value(1), Value(1), Value(2), Value(2), Value.invalid, Value.empty]) == Value(2), "Median high ignores invalid values and takes higher value")

			case .MedianPack:
				XCTAssert(Function.MedianPack.apply([Value(1), Value(1), Value(2), Value(2), Value.invalid, Value.empty]) == Value(Pack([Value(1), Value(2)]).stringValue), "Median pack ignores invalid values and returns pack value")

			case .CountDistinct:
				XCTAssert(Function.Count.apply([]) == Value(0), "Empty count distinct returns zero")
				XCTAssert(Function.Count.apply([Value(1), Value(1), Value.invalid, Value.empty]) == Value(2), "Count distinct does not include invalid values")

			case .Items:
				XCTAssert(Function.Items.apply([Value("")]) == Value(0), "Empty count returns zero")
				XCTAssert(Function.Items.apply([Value("Foo,bar,baz")]) == Value(3), "Count does not include invalid values and empty values")

			case .CountAll:
				XCTAssert(Function.CountAll.apply([Value(1), Value(1), Value.invalid, Value.empty]) == Value(4), "CountAll includes invalid values and empty values")

			case .Negate:
				XCTAssert(Function.Negate.apply([Value(1337)]) == Value(-1337), "Negate")

			case .Or:
				XCTAssert(Function.Or.apply([Value(true), Value(true)]) == Value(true), "OR(true, true)")
				XCTAssert(Function.Or.apply([Value(true), Value(false)]) == Value(true), "OR(true, false)")
				XCTAssert(Function.Or.apply([Value(false), Value(false)]) == Value(false), "OR(false, false)")
				XCTAssert(!Function.Or.apply([Value(true), Value.invalid]).isValid, "OR(true, invalid)")

			case .Acos:
				XCTAssert(Function.Acos.apply([Value(0.337)]) == Value(acos(0.337)), "Acos")
				XCTAssert(!Function.Acos.apply([Value(1.337)]).isValid, "Acos")

			case .Asin:
				XCTAssert(Function.Asin.apply([Value(0.337)]) == Value(asin(0.337)), "Asin")
				XCTAssert(!Function.Asin.apply([Value(1.337)]).isValid, "Asin")

			case .NormalInverse:
				let ni = Function.NormalInverse.apply([Value(0.25), Value(42), Value(4)])
				XCTAssert(ni > Value(39) && ni < Value(40), "NormalInverse")

			case .Atan:
				XCTAssert(Function.Atan.apply([Value(1.337)]) == Value(atan(1.337)), "Atan")

			case .Cosh:
				XCTAssert(Function.Cosh.apply([Value(1.337)]) == Value(cosh(1.337)), "Cosh")

			case .Sinh:
				XCTAssert(Function.Sinh.apply([Value(1.337)]) == Value(sinh(1.337)), "Sinh")

			case .Tanh:
				XCTAssert(Function.Tanh.apply([Value(1.337)]) == Value(tanh(1.337)), "Tanh")

			case .Cos:
				XCTAssert(Function.Cos.apply([Value(1.337)]) == Value(cos(1.337)), "Cos")

			case .Sin:
				XCTAssert(Function.Sin.apply([Value(1.337)]) == Value(sin(1.337)), "Sin")

			case .Tan:
				XCTAssert(Function.Tan.apply([Value(1.337)]) == Value(tan(1.337)), "Tan")

			case .Sqrt:
				XCTAssert(Function.Sqrt.apply([Value(1.337)]) == Value(sqrt(1.337)), "Sqrt")
				XCTAssert(!Function.Sqrt.apply([Value(-1)]).isValid, "Sqrt")

			case .Round:
				XCTAssert(Function.Round.apply([Value(1.337)]) == Value(1), "Round")
				XCTAssert(Function.Round.apply([Value(1.337), Value(2)]) == Value(1.34), "Round")
				XCTAssert(Function.Round.apply([Value(0.5)]) == Value(1), "Round")

			case .Log:
				XCTAssert(Function.Log.apply([Value(1.337)]) == Value(log10(1.337)), "Log")
				XCTAssert(!Function.Log.apply([Value(0)]).isValid, "Log")

			case .Exp:
				XCTAssert(Function.Exp.apply([Value(1.337)]) == Value(exp(1.337)), "Exp")
				XCTAssert(Function.Exp.apply([Value(0)]) == Value(1), "Exp")

			case .Ln:
				XCTAssert(Function.Ln.apply([Value(1.337)]) == Value(log10(1.337) / log10(exp(1.0))), "Ln")
				XCTAssert(!Function.Ln.apply([Value(0)]).isValid, "Ln")

			case .Concat:
				XCTAssert(Function.Concat.apply([Value(1), Value("33"), Value(false)]) == Value("1330"), "Concat")

			case .If:
				XCTAssert(Function.If.apply([Value(true), Value(13), Value(37)]) == Value(13), "If")
				XCTAssert(Function.If.apply([Value(false), Value(13), Value(37)]) == Value(37), "If")
				XCTAssert(!Function.If.apply([Value.invalid, Value(13), Value(37)]).isValid, "If")

			case .Left:
				XCTAssert(Function.Left.apply([Value(1337), Value(3)]) == Value(133), "Left")
				XCTAssert(!Function.Left.apply([Value(1337), Value(5)]).isValid, "Left")

			case .Right:
				XCTAssert(Function.Right.apply([Value(1337), Value(3)]) == Value(337), "Right")
				XCTAssert(!Function.Right.apply([Value(1337), Value(5)]).isValid, "Right")

			case .Mid:
				XCTAssert(Function.Mid.apply([Value(1337), Value(3), Value(1)]) == Value(7), "Mid")
				XCTAssert(Function.Mid.apply([Value(1337), Value(3), Value(10)]) == Value(7), "Mid")

			case .Substitute:
				XCTAssert(Function.Substitute.apply([Value("foobar"), Value("foo"), Value("bar")]) == Value("barbar"), "Substitute")

			case .Length:
				XCTAssert(Function.Length.apply([Value("test")]) == Value(4), "Length")

			case .Sum:
				XCTAssert(Function.Sum.apply([1,3,3,7].map({return Value($0)})) == Value(1+3+3+7), "Sum")
				XCTAssert(Function.Sum.apply([]) == Value(0), "Sum")

			case .Min:
				XCTAssert(Function.Min.apply([1,3,3,7].map({return Value($0)})) == Value(1), "Min")
				XCTAssert(!Function.Min.apply([]).isValid, "Min")

			case .Max:
				XCTAssert(Function.Max.apply([1,3,3,7].map({return Value($0)})) == Value(7), "Max")
				XCTAssert(!Function.Max.apply([]).isValid, "Max")

			case .Average:
				XCTAssert(Function.Average.apply([1,3,3,7].map({return Value($0)})) == Value((1.0+3.0+3.0+7.0)/4.0), "Average")
				XCTAssert(!Function.Average.apply([]).isValid, "Average")

			case .Trim:
				XCTAssert(Function.Trim.apply([Value("   trim  ")]) == Value("trim"), "Trim")
				XCTAssert(Function.Trim.apply([Value("  ")]) == Value(""), "Trim")

			case .Choose:
				XCTAssert(Function.Choose.apply([3,3,3,7].map({return Value($0)})) == Value(7), "Choose")
				XCTAssert(!Function.Choose.apply([Value(3)]).isValid, "Choose")

			case .Random:
				let rv = Function.Random.apply([])
				XCTAssert(rv >= Value(0.0) && rv <= Value(1.0), "Random")

			case .RandomBetween:
				let rv = Function.RandomBetween.apply([Value(-10), Value(9)])
				XCTAssert(rv >= Value(-10.0) && rv <= Value(9.0), "RandomBetween")

			case .RandomItem:
				let items = [1,3,3,7].map({return Value($0)})
				XCTAssert(items.contains(Function.RandomItem.apply(items)), "RandomItem")

			case .Pack:
				XCTAssert(Function.Pack.apply([Value("He,llo"),Value("World")]) == Value(Pack(["He,llo", "World"]).stringValue), "Pack")

			case .Split:
				XCTAssert(Function.Split.apply([Value("Hello#World"), Value("#")]) == Value("Hello,World"), "Split")

			case .Nth:
				XCTAssert(Function.Nth.apply([Value("Foo,bar,baz"), Value(3)]) == Value("baz"), "Nth")
				XCTAssert(!Function.Nth.apply([Value("Foo,bar,baz"), Value(4)]).isValid, "Nth")
				XCTAssert(Function.Nth.apply([Value("foo,bar,baz,boo"), Value("foo")]) == Value("bar"), "Nth with dictionary")
				XCTAssert(!Function.Nth.apply([Value("foo,bar,baz,boo"), Value("xxx")]).isValid, "Nth with dictionary")

			case .Sign:
				XCTAssert(Function.Sign.apply([Value(-1337)]) == Value(-1), "Sign")
				XCTAssert(Function.Sign.apply([Value(0)]) == Value(0), "Sign")
				XCTAssert(Function.Sign.apply([Value(1337)]) == Value(1), "Sign")

			case .IfError:
				XCTAssert(Function.IfError.apply([Value.invalid, Value(1337)]) == Value(1337), "IfError")
				XCTAssert(Function.IfError.apply([Value(1336), Value(1337)]) == Value(1336), "IfError")

			case .Levenshtein:
				XCTAssert(Function.Levenshtein.apply([Value("tommy"), Value("tom")]) == Value(2), "Levenshtein")

			case .RegexSubstitute:
				XCTAssert(Function.RegexSubstitute.apply([Value("Tommy"), Value("m+"), Value("@")]) == Value("To@y"), "RegexSubstitute")

			case .Coalesce:
				XCTAssert(Function.Coalesce.apply([Value.invalid, Value.invalid, Value(1337)]) == Value(1337), "Coalesce")

			case .Capitalize:
				XCTAssert(Function.Capitalize.apply([Value("tommy van DER vorst")]) == Value("Tommy Van Der Vorst"), "Capitalize")

			case .URLEncode:
				// FIXME: URLEncode should probably also encode slashes, right?
				XCTAssert(Function.URLEncode.apply([Value("tommy%/van DER vorst")]) == Value("tommy%25/van%20DER%20vorst"), "URLEncode")

			case .In:
				XCTAssert(Function.In.apply([Value(1), Value(1), Value(2)]) == Value.bool(true), "In")
				XCTAssert(Function.In.apply([Value(1), Value(3), Value(2)]) == Value.bool(false), "In")

			case .NotIn:
				XCTAssert(Function.NotIn.apply([Value(1), Value(2), Value(2)]) == Value.bool(true), "NotIn")
				XCTAssert(Function.NotIn.apply([Value(1), Value(1), Value(2)]) == Value.bool(false), "NotIn")

			case .ToUnixTime:
				let d = Date()
				XCTAssert(Function.ToUnixTime.apply([Value(d)]) == Value(d.timeIntervalSince1970), "ToUnixTime")
				let epoch = Date(timeIntervalSince1970: 0)
				XCTAssert(Function.ToUnixTime.apply([Value(epoch)]) == Value(0), "ToUnixTime")

			case .FromUnixTime:
				XCTAssert(Function.FromUnixTime.apply([Value(0)]) == Value(Date(timeIntervalSince1970: 0)), "FromUnixTime")

			case .Now:
				break

			case .FromISO8601:
				XCTAssert(Function.FromISO8601.apply([Value("1970-01-01T00:00:00Z")]) == Value(Date(timeIntervalSince1970: 0)), "FromISO8601")

			case .ToLocalISO8601:
				break

			case .ToUTCISO8601:
				XCTAssert(Function.ToUTCISO8601.apply([Value(Date(timeIntervalSince1970: 0))]) == Value("1970-01-01T00:00:00Z"), "ToUTCISO8601")

			case .FromExcelDate:
				XCTAssert(Function.FromExcelDate.apply([Value(25569.0)]) == Value(Date(timeIntervalSince1970: 0.0)), "FromExcelDate")
				XCTAssert(Function.FromExcelDate.apply([Value(42210.8330092593)]) == Value(Date(timeIntervalSinceReferenceDate: 459547172.0)), "FromExcelDate")

			case .ToExcelDate:
				XCTAssert(Function.ToExcelDate.apply([Value(Date(timeIntervalSince1970: 0.0))]) == Value(25569.0), "ToExcelDate")
				XCTAssert(Function.ToExcelDate.apply([Value(Date(timeIntervalSinceReferenceDate: 459547172))]).doubleValue!.approximates(42210.8330092593, epsilon: 0.01), "ToExcelDate")

			case .UTCDate:
				XCTAssert(Function.UTCDate.apply([Value(2001), Value(1), Value(1)]) == Value.date(0.0), "UTCDate")

			case .UTCYear:
				XCTAssert(Function.UTCYear.apply([Value.date(0)]) == Value(2001), "UTCYear")

			case .UTCMonth:
				XCTAssert(Function.UTCMonth.apply([Value.date(0)]) == Value(1), "UTCMonth")

			case .UTCDay:
				XCTAssert(Function.UTCDay.apply([Value.date(0)]) == Value(1), "UTCDay")

			case .UTCHour:
				XCTAssert(Function.UTCHour.apply([Value.date(0)]) == Value(0), "UTCHour")

			case .UTCMinute:
				XCTAssert(Function.UTCMinute.apply([Value.date(0)]) == Value(0), "UTCMinute")

			case .UTCSecond:
				XCTAssert(Function.UTCSecond.apply([Value.date(0)]) == Value(0), "UTCSecond")

			case .Duration:
				let start = Value(Date(timeIntervalSinceReferenceDate: 1337.0))
				let end = Value(Date(timeIntervalSinceReferenceDate: 1346.0))
				XCTAssert(Function.Duration.apply([start, end]) == Value(9.0), "Duration")
				XCTAssert(Function.Duration.apply([end, start]) == Value(-9.0), "Duration")

			case .After:
				let start = Value(Date(timeIntervalSinceReferenceDate: 1337.0))
				let end = Value(Date(timeIntervalSinceReferenceDate: 1346.0))
				XCTAssert(Function.After.apply([start, Value(9.0)]) == end, "After")
				XCTAssert(Function.After.apply([end, Value(-9.0)]) == start, "After")

			case .Ceiling:
				XCTAssert(Function.Ceiling.apply([Value(1.337)]) == Value(2), "Ceiling")

			case .Floor:
				XCTAssert(Function.Floor.apply([Value(1.337)]) == Value(1), "Floor")

			case .RandomString:
				XCTAssert(Function.RandomString.apply([Value("[0-9]")]).stringValue!.characters.count == 1, "RandomString")

			case .ToUnicodeDateString:
				XCTAssert(Function.ToUnicodeDateString.apply([Value.date(460226561.0), Value("yyy-MM-dd")]) == Value("2015-08-02"), "ToUnicodeDateString")

			case .FromUnicodeDateString:
				XCTAssert(Function.FromUnicodeDateString.apply([Value("1988-08-11"), Value("yyyy-MM-dd")]) == Value(Date.fromISO8601FormattedDate("1988-08-11T00:00:00Z")!), "FromUnicodeDateString")

			case .Power:
				XCTAssert(Function.Power.apply([Value(2), Value(0)]) == Value(1), "Power")

			case .UUID:
				XCTAssert(Function.UUID.apply([]).stringValue!.lengthOfBytes(using: String.Encoding.utf8) == 36, "UUID must be 36 characters long")

			case .IsEmpty:
				XCTAssert(Function.IsEmpty.apply([Value.empty]) == Value.bool(true), "empty value is empty")
				XCTAssert(Function.IsEmpty.apply([Value.int(1)]) == Value.bool(false), "value is not empty")
				XCTAssert(Function.IsEmpty.apply([Value.invalid]) == Value.bool(false), "invalid value is not empty")

			case .IsInvalid:
				XCTAssert(Function.IsInvalid.apply([Value.invalid]) == Value.bool(true), "invalid value is invalid")
				XCTAssert(Function.IsInvalid.apply([Value.empty]) == Value.bool(false), "empty value is not invalid")

			case .JSONDecode:
				XCTAssert(Function.JSONDecode.apply([Value.string("[1,2,3]")]) == Pack(["1","2","3"]).value, "JSON decode array")
			}
		}

		// Binaries
		XCTAssert(Binary.ContainsString.apply(Value("Tommy"), Value("om"))==Value(true), "Contains string operator should be case-insensitive")
		XCTAssert(Binary.ContainsString.apply(Value("Tommy"), Value("x"))==Value(false), "Contains string operator should work")
		XCTAssert(Binary.ContainsStringStrict.apply(Value("Tommy"), Value("Tom"))==Value(true), "Strict contains string operator should work")
		XCTAssert(Binary.ContainsStringStrict.apply(Value("Tommy"), Value("tom"))==Value(false), "Strict contains string operator should be case-sensitive")
		XCTAssert(Binary.ContainsStringStrict.apply(Value("Tommy"), Value("x"))==Value(false), "Strict contains string operator should work")

		// Split / nth
		XCTAssert(Function.Split.apply([Value("van der Vorst, Tommy"), Value(" ")]).stringValue == "van,der,Vorst$0,Tommy", "Split works")
		XCTAssert(Function.Nth.apply([Value("van,der,Vorst$0,Tommy"), Value(3)]).stringValue == "Vorst,", "Nth works")
		XCTAssert(Function.Items.apply([Value("van,der,Vorst$0,Tommy")]).intValue == 4, "Items works")
		
		// Stats
		let z = Function.NormalInverse.apply([Value(0.9), Value(10), Value(5)]).doubleValue
		XCTAssert(z != nil, "NormalInverse should return a value under normal conditions")
		XCTAssert(z! > 16.406 && z! < 16.408, "NormalInverse should results that are equal to those of NORM.INV.N in Excel")

		// Equality of expressions
		XCTAssert(Sibling(Column("x")) == Sibling(Column("x")), "Equality of expressions")
		XCTAssert(Sibling(Column("x")) != Sibling(Column("y")), "Equality of expressions")
		XCTAssert(Call(arguments: [], type: Function.Random) == Call(arguments: [], type: Function.Random), "Non-deterministic expression can be equal")
		XCTAssert(!Call(arguments: [], type: Function.Random).isEquivalentTo(Call(arguments: [], type: Function.Random)), "Non-deterministic expression cannot be equivalent")
	}
	
	func testEmptyRaster() {
		let emptyRaster = Raster()
		XCTAssert(emptyRaster.rowCount == 0, "Empty raster is empty")
		XCTAssert(emptyRaster.columns.count == 0, "Empty raster is empty")
		XCTAssert(emptyRaster.columns.count == emptyRaster.columns.count, "Column count matches")
	}
	
	func testColumn() {
		XCTAssert(Column("Hello") == Column("hello"), "Case-insensitive column names")
		XCTAssert(Column("xxx") != Column("hello"), "Case-insensitive column names")
		
		XCTAssert(Column.defaultNameForIndex(1337) == Column("BZL"), "Generation of column names")
		XCTAssert(Column.defaultNameForNewColumn([]) == Column("A"), "Generation of column names")
		XCTAssert(Column.defaultNameForNewColumn(["xxx"]) == Column("B"), "Generation of column names")
		XCTAssert(Column.defaultNameForNewColumn(["B"]) != Column("B"), "Generation of column names")
	}
	
	func testSequencer() {
		func checkSequence(_ formula: String, _ expected: [String]) {
			let expectedValues = Set(expected.map { return Value($0) })
			let sequencer = Sequencer(formula)!
			let result = Set(Array(sequencer.root!))
			XCTAssert(result.count == sequencer.cardinality, "Expected number of items matches with the actual number of items for sequence \(formula)")
			XCTAssert(result.isSuperset(of: expectedValues) && expectedValues.isSuperset(of: result), "Sequence \(formula) returns \(expectedValues), got \(result)")
		}

		checkSequence("[AB]{2}", ["AA","AB","BA","BB"])
		checkSequence("[A\\t]{2}", ["AA","A\t","\tA","\t\t"])
		checkSequence("[A\\ ]{2}", ["AA","A "," A","  "])
		checkSequence("test", ["test"])
		checkSequence("(foo)bar", ["foobar"])
		checkSequence("foo?bar", ["bar", "foobar"])
		checkSequence("[abc][\\[]", ["a[", "b[", "c["])
		checkSequence("[1-4]", ["1", "2", "3", "4"])
		checkSequence("[abc]", ["a", "b", "c"])
		checkSequence("[abc][def]", ["ad", "ae", "af", "bd", "be", "bf", "cd", "ce", "cf"])
		checkSequence("[abc]|[def]", ["a","b","c","d","e","f"])
		checkSequence("[A-E]{2}", ["AA","AB","AC","AD","AE","BA","BB","BC","BD","BE","CA","CB","CC","CD","CE","DA","DB","DC","DD","DE","EA","EB","EC","ED","EE"])

		checkSequence("[0-9]{2}[E-A]{2}", []) // Right side is empty, do not crash and produce empty sequence
		checkSequence("[a-Z]", ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z",
								"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"])

		checkSequence("[A-z]", ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z",
			"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"])

		checkSequence("[a-zA-Z]", ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z",
			"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"])

		XCTAssert(Sequencer("'") == nil, "Do not parse everything")
		XCTAssert(Array(Sequencer("[A-C]{2}")!.root!).count == 3*3, "Sequence [A-C]{2} delivers 3*3 items")
		XCTAssert(Array(Sequencer("[A-Z]{2}")!.root!).count == 26*26, "Sequence [A-Z]{2} delivers 26*26 items")
		XCTAssert(Array(Sequencer("[A-Z][a-z]")!.root!).count == 26*26, "Sequence <A-Z><a-z> should generate 26*26 items")
		XCTAssert(Array(Sequencer("[abc]|[def]")!.root!).count == 6, "Sequence [abc]|[def] should generate 6 items")
		XCTAssert(Array(Sequencer("([abc]|[def])")!.root!).count == 6, "Sequence ([abc]|[def]) should generate 6 items")
		XCTAssert(Array(Sequencer("([abc]|[def])[xyz]")!.root!).count == 6 * 3, "Sequence ([abc]|[def])[xyz] should generate 6*3 items")
		
		XCTAssert(Sequencer("([0-9]{2}\\-[A-Z]{3}\\-[0-9])|([A-Z]{2}\\-[A-Z]{2}\\-[0-9]{2})")!.cardinality == 63273600,"Cardinality of a complicated sequencer expression is correct")

		// [a-z]{40} generates 4^40 items, which is much larger than Int.max, so cardinality cannot be reported.
		XCTAssert(Sequencer("[a-z]{40}")!.cardinality == nil, "Very large sequences should not have cardinality defined")
	}
	
	func testFormulaParser() {
		let locale = Language(language: Language.defaultLanguage)
		
		// Test whether parsing goes right
		XCTAssert(Formula(formula: "1.337", locale: locale)!.root.apply(Row(), foreign: nil, inputValue: nil) == Value(1.337), "Parse decimal numbers")
		XCTAssert(Formula(formula: "1,337,338", locale: locale)!.root.apply(Row(), foreign: nil, inputValue: nil) == Value(1337338), "Parse numbers with thousand separators")
		XCTAssert(Formula(formula: "1337,338", locale: locale)!.root.apply(Row(), foreign: nil, inputValue: nil) == Value(1337338), "Parse numbers with thousand separators in the wrong place")
		XCTAssert(Formula(formula: "1.337.338", locale: locale)==nil, "Parse numbers with double decimal separators should fail")
		XCTAssert(Formula(formula: "13%", locale: locale)!.root.apply(Row(), foreign: nil, inputValue: nil) == Value(0.13), "Parse percentages")
		XCTAssert(Formula(formula: "10Ki", locale: locale)!.root.apply(Row(), foreign: nil, inputValue: nil) == Value(10 * 1024), "Parse SI postfixes")

		XCTAssert(Formula(formula: "6~2", locale: locale) != nil, "Parse modulus operator")
		XCTAssert(Formula(formula: "\"1,2,3\"[2]", locale: locale) != nil, "Parse index accessors")

		XCTAssert(Formula(formula: "6/ 2", locale: locale) != nil, "Parse whitespace around binary operator: right side")
		XCTAssert(Formula(formula: "6 / 2", locale: locale) != nil, "Parse whitespace around binary operator: both sides")
		XCTAssert(Formula(formula: "6 /2", locale: locale) != nil, "Parse whitespace around binary operator: left side")
		XCTAssert(Formula(formula: "(6>=2)>3", locale: locale) != nil, "Parse greater than or equals, while at the same time parsing greater than")
		
		XCTAssert(Formula(formula: "6/(1-3/4)", locale: locale) != nil, "Formula in default dialect")
		XCTAssert(Formula(formula: "6/(1-3/4)±", locale: locale) == nil, "Formula needs to ignore any garbage near the end of a formula")
		XCTAssert(Formula(formula: "6/(1-3/4)+[@colRef]", locale: locale) != nil, "Formula in default dialect with column ref")
		XCTAssert(Formula(formula: "6/(1-3/4)+[#colRef]", locale: locale) != nil, "Formula in default dialect with foreign ref")
		XCTAssert(Formula(formula: "6/(1-3/4)+[@colRef]&\"stringLit\"", locale: locale) != nil, "Formula in default dialect with string literal")
		
		for ws in [" ","\t", " \t", "\r", "\n", "\r\n"] {
			XCTAssert(Formula(formula: "6\(ws)/\(ws)(\(ws)1-3/\(ws)4)", locale: locale) != nil, "Formula with whitespace '\(ws)' in between")
			XCTAssert(Formula(formula: "\(ws)6\(ws)/\(ws)(\(ws)1-3/\(ws)4)", locale: locale) != nil, "Formula with whitespace '\(ws)' at beginning")
			XCTAssert(Formula(formula: "6\(ws)/\(ws)(\(ws)1-3/\(ws)4)\(ws)", locale: locale) != nil, "Formula with whitespace '\(ws)' at end")
		}
		
		// Test results
		XCTAssert(Formula(formula: "6/(1-3/4)", locale: locale)!.root.apply(Row(), foreign: nil, inputValue: nil) == Value(24), "Formula in default dialect")
		XCTAssert(Formula(formula: "7~2", locale: locale)!.root.apply(Row(), foreign: nil, inputValue: nil) == Value(1), "Modulus operator")
		XCTAssert(Formula(formula: "\"1,2,3\"[1]", locale: locale)!.root.apply(Row(), foreign: nil, inputValue: nil) == Value("1"), "Index access")
		XCTAssert(Formula(formula: "\"foo,bar,baz,faa\"[\"baz\"]", locale: locale)!.root.apply(Row(), foreign: nil, inputValue: nil) == Value("faa"), "Index access using string")
		
		// Test whether parsing goes wrong when it should
		XCTAssert(Formula(formula: "", locale: locale) == nil, "Empty formula")
		XCTAssert(Formula(formula: "1+22@D@D@", locale: locale) == nil, "Garbage formula")
		

		XCTAssert(Formula(formula: "fALse", locale: locale) != nil, "Constant names should be case-insensitive")
		XCTAssert(Formula(formula: "siN(1)", locale: locale) != nil, "Function names should be case-insensitive")
		XCTAssert(Formula(formula: "SIN(1)", locale: locale)!.root.apply(Row(), foreign: nil, inputValue: nil) == Value(sin(1.0)), "SIN(1)=sin(1)")
		XCTAssert(Formula(formula: "siN(1)", locale: locale)!.root.apply(Row(), foreign: nil, inputValue: nil) == Value(sin(1.0)), "siN(1)=sin(1)")
		XCTAssert(Formula(formula: "POWER(1;)", locale: locale) == nil, "Empty arguments are invalid")
		XCTAssert(Formula(formula: "POWER(2;4)", locale: locale)!.root.apply(Row(), foreign: nil, inputValue: nil) == Value(pow(2,4)), "POWER(2;4)==2^4")
	}
	
	func testExpressions() {
		let x = Call(arguments: [Sibling(Column("test")), Literal(Value(3))], type: .Left)
		let y = Call(arguments: [Sibling(Column("test")), Literal(Value(3))], type: .Left)
		XCTAssert(x == y, "Two identical expressions must be equal")
		XCTAssert(x.hashValue == y.hashValue, "Two identical expressions must be equal")

		XCTAssert(Literal(Value(13.46)).isConstant, "Literal expression should be constant")
		XCTAssert(!Call(arguments: [], type: Function.RandomItem).isConstant, "Non-deterministic function expression should not be constant")
		
		XCTAssert(!Comparison(first: Literal(Value(13.45)), second: Call(arguments: [], type: Function.RandomItem), type: Binary.Equal).isConstant, "Binary operator applied to at least one non-constant expression should not be constant itself")
		
		
		let locale = Language(language: Language.defaultLanguage)
		
		let a = Formula(formula: "([@x]+1)>([@x]+1)", locale: locale)!.root.prepare()
		XCTAssert(a is Literal && a.apply(Row(), foreign: nil, inputValue: nil) == Value.bool(false), "Equivalence is optimized away for '>' operator in x+1 > x+1")
		
		let b = Formula(formula: "(1+[@x])>([@x]+1)", locale: locale)!.root.prepare()
		XCTAssert(b is Literal && b.apply(Row(), foreign: nil, inputValue: nil) == Value.bool(false), "Equivalence is optimized away for '>' operator in x+1 > 1+x")
		
		let c = Formula(formula: "(1+[@x])>=([@x]+1)", locale: locale)!.root.prepare()
		XCTAssert(c is Literal && c.apply(Row(), foreign: nil, inputValue: nil) == Value.bool(true), "Equivalence is optimized away for '>=' operator in x+1 > 1+x")
		
		let d = Formula(formula: "(1+[@x])<>([@x]+1)", locale: locale)!.root.prepare()
		XCTAssert(d is Literal && d.apply(Row(), foreign: nil, inputValue: nil) == Value.bool(false), "Equivalence is optimized away for '<>' operator in x+1 > x+2")
		
		let f = Formula(formula: "(1+[@x])<>([@x]+2)", locale: locale)!.root.prepare()
		XCTAssert(f is Comparison, "Equivalence is NOT optimized away for '<>' operator in x+1 > x+2")
		
		// Optimizer is not smart enough to do the following
		//let e = Formula(formula: "(1+2+[@x])>(2+[@x]+1)", locale: locale)!.root.prepare()
		//XCTAssert(e is Literal && e.apply(Row(), foreign: nil, inputValue: nil) == Value.bool(false), "Equivalence is optimized away for '>' operator in 1+2+x > 2+x+1")
	}
	
	func compareDataset(_ job: Job, _ a: WarpCore.Dataset, _ b: WarpCore.Dataset, callback: (Bool) -> ()) {
		a.raster(job, callback: { (aRasterFallible) -> () in
			switch aRasterFallible {
				case .success(let aRaster):
					b.raster(job, callback: { (bRasterFallible) -> () in
						switch bRasterFallible {
							case .success(let bRaster):
								let equal = aRaster.compare(bRaster)
								if !equal {
									job.log("A: \(aRaster.debugDescription)")
									job.log("B: \(bRaster.debugDescription)")
								}
								callback(equal)
							
							case .failure(let error):
								XCTFail(error)
						}
					})
				
				case .failure(let error):
					XCTFail(error)
			}
		})
	}
	
	func testCoalescer() {
		let raster = Raster(data: [
			[Value.int(1), Value.int(2), Value.int(3)],
			[Value.int(4), Value.int(5), Value.int(6)],
			[Value.int(7), Value.int(8), Value.int(9)]
		], columns: [Column("a"), Column("b"), Column("c")], readOnly: true)
		
		let inDataset = RasterDataset(raster: raster)
		let inOptDataset = inDataset.coalesced
		let job = Job(.userInitiated)

		inDataset.filter(Literal(Value(false))).raster(job) { rf in
			switch rf {
			case .success(let r):
				XCTAssert(r.columns.count > 0, "Dataset set that is filtered to be empty should still contains column names")

			case .failure(let e):
				XCTFail(e)
			}

		}
		
		compareDataset(job, inDataset.limit(2).limit(1), inOptDataset.limit(2).limit(1)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for limit(2).limit(1) should equal normal result")
		}
		
		compareDataset(job, inDataset.offset(2).offset(1), inOptDataset.offset(2).offset(1)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for offset(2).offset(1) should equal normal result")
		}
		
		compareDataset(job, inDataset.offset(3), inOptDataset.offset(2).offset(1)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for offset(2).offset(1) should equal offset(3)")
		}
		
		// Verify coalesced sort operations
		let aSorts = [
			Order(expression: Sibling("a"), ascending: true, numeric: true),
			Order(expression: Sibling("b"), ascending: false, numeric: true)
		]
		
		let bSorts = [
			Order(expression: Sibling("c"), ascending: true, numeric: true)
		]
		
		compareDataset(job, inDataset.sort(aSorts).sort(bSorts), inDataset.sort(bSorts + aSorts)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for sort().sort() should equal normal result")
		}
		
		compareDataset(job, inDataset.sort(aSorts).sort(bSorts), inOptDataset.sort(aSorts).sort(bSorts)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for sort().sort() should equal normal result")
		}
		
		// Verify coalesced transpose
		compareDataset(job, inDataset.transpose().transpose(), inOptDataset.transpose().transpose()) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for transpose().transpose() should equal normal result")
		}
		
		compareDataset(job, inDataset.transpose().transpose().transpose(), inOptDataset.transpose().transpose().transpose()) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for transpose().transpose().transpose() should equal normal result")
		}
		
		compareDataset(job, inDataset, inOptDataset.transpose().transpose()) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for transpose().transpose() should equal original result")
		}

		let seqDataset = StreamDataset(source: Sequencer("[a-z]{4}")!.stream("Value"))
		seqDataset.random(1).random(1).raster(job) { rf in
			switch rf {
			case .success(let r):
				XCTAssert(r.rowCount == 1, "Random.Random returns the wrong row count")

			case .failure(let e): XCTFail(e)
			}
		}
	}
	
	func testInferer() {
		let locale = Language(language: Language.defaultLanguage)
		let cols = ["A","B","C","D"].map({Column($0)})
		let row = [1,3,4,6].map({Value($0)})
		let suggestions = Expression.infer(nil, toValue: Value(24), level: 4, row: Row(row, columns: cols), column: 0, maxComplexity: Int.max, previousValues: [])
		suggestions.forEach { print("Solution: \($0.explain(locale))") }
		XCTAssert(suggestions.count>0, "Can solve the 1-3-4-6 24 game.")
	}
	
	func testDatasetImplementations() {
		let job = Job(.userInitiated)
		
		var d: [[Value]] = []
		for i in 0..<1000 {
			d.append([Value(i), Value(i+1), Value(i+2)])
		}
		
		func assertRaster(_ raster: Fallible<Raster>, message: String, condition: (Raster) -> Bool) {
			switch raster {
				case .success(let r):
					XCTAssertTrue(condition(r), message)
				
				case .failure(let error):
					XCTFail("\(message) failed: \(error)")
			}
		}
		
		let data = RasterDataset(data: d, columns: [Column("X"), Column("Y"), Column("Z")])
		
		// Limit
		data.limit(5).raster(job) { assertRaster($0, message: "Limit actually works") { $0.rowCount == 5 } }
		
		// Offset
		data.offset(5).raster(job) { assertRaster($0, message: "Offset actually works", condition: { $0.rowCount == 1000 - 5 }) }
		
		// Distinct
		data.distinct().raster(job) {
			assertRaster($0, message: "Distinct removes no columns", condition: { $0.columns.count == 3 })
			assertRaster($0, message: "Distinct removes no rows when they are all unique", condition: { $0.rowCount == 1000 })
		}
		
		// Union
		let secondDataset = RasterDataset(data: d, columns: [Column("X"), Column("B"), Column("C")])
		data.union(secondDataset).raster(job) {
			assertRaster($0, message: "Union creates the proper number of columns", condition: { $0.columns.count == 5 })
			assertRaster($0, message: "Union creates the proper number of rows", condition: { $0.rowCount == 2000 })
		}
		data.union(data).raster(job) {
			assertRaster($0, message: "Union creates the proper number of columns in self-union scenario", condition: { $0.columns.count == 3 })
			assertRaster($0, message: "Union creates the proper number of rows in self-union scenario", condition: { $0.rowCount == 2000 })
		}
		
		// Join
		data.join(Join(type: .LeftJoin, foreignDataset: secondDataset, expression: Comparison(first: Sibling("X"), second: Foreign("X"), type: .Equal))).raster(job) {
			assertRaster($0, message: "Join returns the appropriate number of rows in a one-to-one scenario", condition: { (x) in
				x.rowCount == 1000
			})
			assertRaster($0, message: "Join returns the appropriate number of columns", condition: { $0.columns.count == 5 })
		}
		data.join(Join(type: .LeftJoin, foreignDataset: data, expression: Comparison(first: Sibling("X"), second: Foreign("X"), type: .Equal))).raster(job) {
			assertRaster($0, message: "Join returns the appropriate number of rows in a self-join one-to-one scenario", condition: { $0.rowCount == 1000 })
			assertRaster($0, message: "Join returns the appropriate number of columns in a self-join", condition: { $0.columns.count == 3 })
		}
		
		// Select columns
		data.selectColumns(["THIS_DOESNT_EXIST"]).columns(job) { (r) -> () in
			switch r {
				case .success(let cns):
					XCTAssert(cns.isEmpty, "Selecting an invalid column returns a set without columns")
				
				case .failure(let error):
					XCTFail(error)
			}
		}
		
		// Transpose (repeatedly transpose and see if we end up with the initial value)
		data.raster(job) { (r) -> () in
			switch r {
				case .success(let raster):
					let rowsBefore = raster.rowCount
					let columnsBefore = raster.columns.count
					
					self.measure {
						var td: WarpCore.Dataset = data
						for _ in 1...11 {
							td = td.transpose()
						}
						
						td.raster(job) { assertRaster($0, message: "Row count matches") { $0.rowCount == columnsBefore - 1 } }
						td.raster(job) { assertRaster($0, message: "Column count matches") { $0.columns.count == rowsBefore + 1 } }
					}
			
				case .failure(let error):
					XCTFail(error)
			}
			
		}
		
		// Empty raster behavior
		let emptyRasterDataset = RasterDataset(data: [], columns: [])
		emptyRasterDataset.limit(5).raster(job) { assertRaster($0, message: "Limit works when number of rows > available rows") { $0.rowCount == 0 } }
		emptyRasterDataset.selectColumns([Column("THIS_DOESNT_EXIST")]).raster(job) { assertRaster($0, message: "Selecting an invalid column works properly in empty raster") { $0.columns.isEmpty } }
	}
	
    func testRaster() {
		let job = Job(.userInitiated)
		
		var d: [[Value]] = []
		for i in 0...1000 {
			d.append([Value(i), Value(i+1), Value(i+2)])
		}
		
		let rasterDataset = RasterDataset(data: d, columns: [Column("X"), Column("Y"), Column("Z")])
		rasterDataset.raster(job) { (raster) -> () in
			switch raster {
				case .success(let r):
					XCTAssert(r.indexOfColumnWithName("X")==0, "First column has index 0")
					XCTAssert(r.indexOfColumnWithName("x")==0, "Column names should be case-insensitive")
					XCTAssert(r.rowCount == 1001, "Row count matches")
					XCTAssert(r.columns.count == 3, "Column count matches")
				
				case .failure(let error):
					XCTFail(error)
			}
		}

		// Raster modifications
		let cols = [Column("X"), Column("Y"), Column("Z")]
		let testRaster = Raster(data: d, columns: cols)
		XCTAssert(testRaster.rowCount == d.count, "Row count matches")
		testRaster.addRows([[Value.empty, Value.empty, Value.empty]])
		XCTAssert(testRaster.rowCount == d.count+1, "Row count matches after insert")

		testRaster.addColumns([Column("W")])
		XCTAssert(testRaster.columns.count == 3+1, "Column count matches after insert")

		// Raster modifications through RasterMutableDataset
		let mutableRaster = RasterMutableDataset(raster: testRaster)
		mutableRaster.performMutation(.alter(DatasetDefinition(columns: cols)), job: job) { result in
			switch result {
			case .success:
				XCTAssert(testRaster.columns.count == 3, "Column count matches again after mutation")

				mutableRaster.performMutation(.truncate, job: job) { result in
					switch result {
					case .success:
						XCTAssert(testRaster.columns.count == 3, "Column count matches again after mutation")
						XCTAssert(testRaster.rowCount == 0, "Row count matches again after mutation")

					case .failure(let e): XCTFail(e)
					}
				}

			case .failure(let e): XCTFail(e)
			}
		}
    }

	func testNormalDistribution() {
		XCTAssert(NormalDistribution().inverse(0.0).isInfinite)
		XCTAssert(NormalDistribution().inverse(1.0).isInfinite)
		XCTAssertEqualWithAccuracy(NormalDistribution().inverse(0.5), 0.0, accuracy: 0.001)
		XCTAssertEqualWithAccuracy(NormalDistribution().inverse(0.25), -0.674490, accuracy: 0.001)
		XCTAssertEqualWithAccuracy(NormalDistribution().inverse(0.75), 0.674490, accuracy: 0.001)
	}
	
	func testThreading() {
		let data = Array<Int>(0...500000)
		let expectFinish = self.expectation(description: "Parallel map finishes in time")
		
		let future = data.parallel(
			{ (slice: Array<Int>) -> [Int] in
				return Array(slice.map({return $0 * 2}))
			},
			reduce: {(s, r: Int?) -> (Int) in
				var r = r
				for number in s {
					r = (r == nil || number > r) ? number : r
				}
				return r ?? 0
			}
		)

		let job = Job(.userInitiated)
		future.get(job) { result in
			XCTAssert(result != nil && result! == 1000000, "Parallel M/R delivers the correct result")
			expectFinish.fulfill()
		}
		
		self.waitForExpectations(timeout: 15.0, handler: { (err) -> Void in
			if let e = err {
				print("Error=\(e)")
			}
		})
	}

	func testAggregation() {
		let n = 10000
		let rows = (0..<n).map { i in
			return [i, 0, 1].map { Value.int($0) }
		}

		let raster = Raster(data: rows, columns: ["a", "b", "c"])
		let rasterDataset = RasterDataset(raster: raster)
		let job = Job(.userInitiated)

		asyncTest { callback in
			rasterDataset.aggregate([:], values: ["x": Aggregator(map: Sibling(Column("c")), reduce: .Sum)]).raster(job) { result in
				result.require { outRaster in
					XCTAssert(WarpCoreTests.rasterEquals(outRaster, grid: [
						[Value.int(n)]
					]), "Simple aggregation works")

					callback()
				}
			}
		}
	}

	private func asyncTest(_ block: (callback: () -> ()) -> ()) {
		let expectFinish = self.expectation(description: "CSV tests")

		block {
			expectFinish.fulfill()
		}

		self.waitForExpectations(timeout: 5.0) { (err) -> Void in
			if let e = err {
				// Note: referencing self here deliberately to prevent test from being destroyed prematurely
				print("Error=\(e) \(self)")
			}
		}
	}

	private static func rasterEquals(_ raster: Raster, grid: [[Value]]) -> Bool {
		for row in 0..<raster.rowCount {
			if raster[row].values != grid[row] {
				return false
			}
		}
		return true
	}
}
