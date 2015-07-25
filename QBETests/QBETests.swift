import Cocoa
import XCTest

class QBETests: XCTestCase {
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    } 
	
	func testStatistics() {
		let moving = QBEMoving(size: 10, items: [0,10,0,10,0,10,10,10,0,0,10,0,10,0,10,999999999999,0,5,5,5,5,5,5,5,5,5,5,5])
		XCTAssert(moving.sample.n == 10, "QBEMoving should discard old samples properly")
		XCTAssert(moving.sample.mean == 5.0, "Average of test sample should be exactly 5")
		XCTAssert(moving.sample.stdev == 0.0, "Test sample has no deviations")
		
		let (lower, upper) = moving.sample.confidenceInterval(0.90)
		XCTAssert(lower <= upper, "Test sample confidence interval must not be flipped")
		XCTAssert(lower == 5.0 && upper == 5.0, "Test sample has confidence interval that is [5,5]")
		
		// Add a value to the moving average and try again
		moving.add(100)
		XCTAssert(moving.sample.n == 10, "QBEMoving should discard old samples properly")
		XCTAssert(moving.sample.mean > 5.0, "Average of test sample should be > 5")
		XCTAssert(moving.sample.stdev > 0.0, "Test sample has a deviation now")
		let (lower2, upper2) = moving.sample.confidenceInterval(0.90)
		XCTAssert(lower2 <= upper2, "Test sample confidence interval must not be flipped")
		XCTAssert(lower2 < 5.0 && upper2 > 5.0, "Test sample has confidence interval that is wider")
		
		let (lower3, upper3) = moving.sample.confidenceInterval(0.95)
		XCTAssert(lower3 < lower2 && upper3 > upper2, "A more confident interval is wider")
	}
	
	func testEmptyQBERaster() {
		let emptyRaster = QBERaster()
		XCTAssert(emptyRaster.rowCount == 0, "Empty raster is empty")
		XCTAssert(emptyRaster.columnCount == 0, "Empty raster is empty")
		XCTAssert(emptyRaster.columnNames.count == emptyRaster.columnCount, "Column count matches")
	}
	
	func testColumn() {
		XCTAssert(QBEColumn("Hello") == QBEColumn("hello"), "Case-insensitive column names")
		XCTAssert(QBEColumn("xxx") != QBEColumn("hello"), "Case-insensitive column names")
		
		XCTAssert(QBEColumn.defaultColumnForIndex(1337)==QBEColumn("BZL"), "Generation of column names")
		XCTAssert(QBEColumn.defaultColumnForIndex(0)==QBEColumn("A"), "Generation of column names")
		XCTAssert(QBEColumn.defaultColumnForIndex(1)==QBEColumn("B"), "Generation of column names")
	}
	
	func testArithmetic() {
		// Strings
		XCTAssert(QBEValue("hello") == QBEValue("hello"), "String equality")
		XCTAssert(QBEValue("hello") != QBEValue("HELLO"), "String equality is case sensitive")
		XCTAssert(QBEValue(1337) == QBEValue("1337"), "Numbers are strings")
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
		XCTAssert(QBEValue.InvalidValue != QBEValue.InvalidValue, "Invalid value does not equal itself")
		XCTAssert(QBEValue.InvalidValue != QBEValue.EmptyValue, "Invalid value does not equal empty value")
		XCTAssert(QBEValue.InvalidValue != QBEValue.BoolValue(false), "Invalid value does not equal false value")
		
		// Empty value
		XCTAssert(QBEValue.EmptyValue == QBEValue.EmptyValue, "Empty equals empty")
		XCTAssert(QBEValue.EmptyValue != QBEValue.StringValue(""), "Empty does not equal empty string")
		XCTAssert(QBEValue.EmptyValue != QBEValue.IntValue(0), "Empty does not equal zero integer")
		XCTAssert(QBEValue.EmptyValue != QBEValue.BoolValue(false), "Empty does not equal false")

		// Numeric operations
		XCTAssert(QBEValue(12) * QBEValue(13) == QBEValue(156), "Integer multiplication")
		XCTAssert(QBEValue(12.2) * QBEValue(13.3) == QBEValue(162.26), "Double multiplication")
		XCTAssert(QBEValue(12) * QBEValue(13) == QBEValue(156), "Integer multiplication to double")
		XCTAssert(QBEValue(12) / QBEValue(2) == QBEValue(6), "Integer division to double")
		XCTAssert(!(QBEValue(10.0) / QBEValue(0)).isValid, "Division by zero")
		
		// String operations
		XCTAssert(QBEValue("1337") & QBEValue("h4x0r") == QBEValue("1337h4x0r"), "String string concatenation")
		
		// Implicit conversions
		XCTAssert((QBEValue(13) + QBEValue("37")) == QBEValue.IntValue(50), "Integer plus string results in integer")
		XCTAssert(QBEValue("13") + QBEValue(37) == QBEValue.IntValue(50), "String plus integer results in integer")
		XCTAssert(QBEValue("13") + QBEValue("37") == QBEValue.IntValue(50), "String plus integer results in integer")
		XCTAssert(QBEValue(true) + QBEValue(true) == QBEValue.IntValue(2), "True + true == 2")
		XCTAssert(!(QBEValue(1) + QBEValue.EmptyValue).isValid, "1 + Empty is not valid")
		XCTAssert(!(QBEValue.EmptyValue + QBEValue.EmptyValue).isValid, "Empty + Empty is not valud")
		XCTAssert(!(QBEValue(12) + QBEValue.InvalidValue).isValid, "Int + Invalid is not valid")
		
		XCTAssert((QBEValue(13) - QBEValue("37")) == QBEValue.IntValue(-24), "Integer minus string results in integer")
		XCTAssert(QBEValue("13") - QBEValue(37) == QBEValue.IntValue(-24), "String minus integer results in integer")
		XCTAssert(QBEValue("13") - QBEValue("37") == QBEValue.IntValue(-24), "String minus integer results in integer")
		XCTAssert(QBEValue(true) - QBEValue(true) == QBEValue.IntValue(0), "True + true == 2")
		XCTAssert(!(QBEValue(1) - QBEValue.EmptyValue).isValid, "1 - Empty is not valid")
		XCTAssert(!(QBEValue.EmptyValue - QBEValue.EmptyValue).isValid, "Empty - Empty is  ot valud")
		XCTAssert(!(QBEValue(12) - QBEValue.InvalidValue).isValid, "Int - Invalid is not valid")
		
		// Numeric comparisons
		XCTAssert((QBEValue(12) < QBEValue(25)) == QBEValue(true), "Less than")
		XCTAssert((QBEValue(12) > QBEValue(25)) == QBEValue(false), "Greater than")
		XCTAssert((QBEValue(12) <= QBEValue(25)) == QBEValue(true), "Less than or equal")
		XCTAssert((QBEValue(12) >= QBEValue(25)) == QBEValue(false), "Greater than or equal")
		XCTAssert((QBEValue(12) <= QBEValue(12)) == QBEValue(true), "Less than or equal")
		XCTAssert((QBEValue(12) >= QBEValue(12)) == QBEValue(true), "Greater than or equal")
		
		// Equality
		XCTAssert((QBEValue(12.0) == QBEValue(12)) == QBEValue(true), "Double == int")
		XCTAssert((QBEValue(12) == QBEValue(12.0)) == QBEValue(true), "Int == double")
		XCTAssert((QBEValue(12.0) != QBEValue(12)) == QBEValue(false), "Double != int")
		XCTAssert((QBEValue(12) != QBEValue(12.0)) == QBEValue(false), "Int != double")
		XCTAssert(QBEValue("12") == QBEValue(12), "String number is treated as number")
		XCTAssert((QBEValue("12") + QBEValue("13")) == QBEValue(25), "String number is treated as number")
		XCTAssert(QBEValue.EmptyValue == QBEValue.EmptyValue, "Empty equals empty")
		XCTAssert(!(QBEValue.InvalidValue == QBEValue.InvalidValue), "Invalid value equals nothing")
		
		// Inequality
		XCTAssert(QBEValue.EmptyValue != QBEValue(0), "Empty is not equal to zero")
		XCTAssert(QBEValue.EmptyValue != QBEValue(Double.NaN), "Empty is not equal to double NaN")
		XCTAssert(QBEValue.EmptyValue != QBEValue(""), "Empty is not equal to empty string")
		XCTAssert(QBEValue.InvalidValue != QBEValue.InvalidValue, "Invalid value inequals other invalid value")
		
		// Packs
		XCTAssert(QBEPack("a,b,c,d").count == 4, "Pack format parser works")
		XCTAssert(QBEPack("a,b,c,d,").count == 5, "Pack format parser works")
		XCTAssert(QBEPack("a,b$0,c$1$0,d$0$1").count == 4, "Pack format parser works")
		XCTAssert(QBEPack(",").count == 2, "Pack format parser works")
		XCTAssert(QBEPack("").count == 0, "Pack format parser works")
		XCTAssert(QBEPack(["Tommy", "van$,der,Vorst"]).stringValue == "Tommy,van$1$0der$0Vorst", "Pack writer properly escapes")
	}
	
	func testFormulaParser() {
		let locale = QBELocale(language: QBELocale.defaultLanguage)
		
		// Test whether parsing goes right
		XCTAssert(QBEFormula(formula: "6/ 2", locale: locale) != nil, "Parse whitespace around binary operator: right side")
		XCTAssert(QBEFormula(formula: "6 / 2", locale: locale) != nil, "Parse whitespace around binary operator: both sides")
		XCTAssert(QBEFormula(formula: "6 /2", locale: locale) != nil, "Parse whitespace around binary operator: left side")
		
		XCTAssert(QBEFormula(formula: "6/(1-3/4)", locale: locale) != nil, "Formula in default dialect")
		XCTAssert(QBEFormula(formula: "6/(1-3/4)±", locale: locale) == nil, "Formula needs to ignore any garbage near the end of a formula")
		XCTAssert(QBEFormula(formula: "6/(1-3/4)+[@colRef]", locale: locale) != nil, "Formula in default dialect with column ref")
		XCTAssert(QBEFormula(formula: "6/(1-3/4)+[#colRef]", locale: locale) != nil, "Formula in default dialect with foreign ref")
		XCTAssert(QBEFormula(formula: "6/(1-3/4)+[@colRef]&\"stringLit\"", locale: locale) != nil, "Formula in default dialect with string literal")
		
		for ws in [" ","\t", " \t", "\r", "\n", "\r\n"] {
			XCTAssert(QBEFormula(formula: "6\(ws)/\(ws)(\(ws)1-3/\(ws)4)", locale: locale) != nil, "Formula with whitespace '\(ws)' in between")
			XCTAssert(QBEFormula(formula: "\(ws)6\(ws)/\(ws)(\(ws)1-3/\(ws)4)", locale: locale) != nil, "Formula with whitespace '\(ws)' at beginning")
			XCTAssert(QBEFormula(formula: "6\(ws)/\(ws)(\(ws)1-3/\(ws)4)\(ws)", locale: locale) != nil, "Formula with whitespace '\(ws)' at end")
		}
		
		// Test results
		XCTAssert(QBEFormula(formula: "6/(1-3/4)", locale: locale)!.root.apply(QBERow(), foreign: nil, inputValue: nil) == QBEValue(24), "Formula in default dialect")
		
		// Test whether parsing goes wrong when it should
		XCTAssert(QBEFormula(formula: "", locale: locale) == nil, "Empty formula")
		XCTAssert(QBEFormula(formula: "1+22@D@D@", locale: locale) == nil, "Garbage formula")
		

		XCTAssert(QBEFormula(formula: "fALse", locale: locale) != nil, "Constant names should be case-insensitive")
		XCTAssert(QBEFormula(formula: "siN(1)", locale: locale) != nil, "Function names should be case-insensitive")
	}
	
	func testExpressions() {
		XCTAssert(QBELiteralExpression(QBEValue(13.46)).isConstant, "Literal expression should be constant")
		XCTAssert(!QBEFunctionExpression(arguments: [], type: QBEFunction.RandomItem).isConstant, "Non-deterministic function expression should not be constant")
		
		XCTAssert(!QBEBinaryExpression(first: QBELiteralExpression(QBEValue(13.45)), second: QBEFunctionExpression(arguments: [], type: QBEFunction.RandomItem), type: QBEBinary.Equal).isConstant, "Binary operator applied to at least one non-constant expression should not be constant itself")
	}
	
	func testFunctions() {
		for fun in QBEFunction.allFunctions {
			switch fun {
				
			case .Xor:
				XCTAssert(QBEFunction.Xor.apply([QBEValue(true), QBEValue(true)]) == QBEValue(false), "XOR(true, true)")
				XCTAssert(QBEFunction.Xor.apply([QBEValue(true), QBEValue(false)]) == QBEValue(true), "XOR(true, false)")
				XCTAssert(QBEFunction.Xor.apply([QBEValue(false), QBEValue(false)]) == QBEValue(false), "XOR(false, false)")
				
			case .Identity:
				XCTAssert(QBEFunction.Identity.apply([QBEValue(1.337)]) == QBEValue(1.337),"Identity")
				
			case .Not:
				XCTAssert(QBEFunction.Not.apply([QBEValue(false)]) == QBEValue(true), "Not")
				
			case .And:
				XCTAssert(QBEFunction.And.apply([QBEValue(true), QBEValue(true)]) == QBEValue(true), "AND(true, true)")
				XCTAssert(!QBEFunction.And.apply([QBEValue(true), QBEValue.InvalidValue]).isValid, "AND(true, invalid)")
				XCTAssert(QBEFunction.And.apply([QBEValue(true), QBEValue(false)]) == QBEValue(false), "AND(true, false)")
				XCTAssert(QBEFunction.And.apply([QBEValue(false), QBEValue(false)]) == QBEValue(false), "AND(false, false)")
			
			case .Lowercase:
				XCTAssert(QBEFunction.Lowercase.apply([QBEValue("Tommy")]) == QBEValue("tommy"), "Lowercase")
			
			case .Uppercase:
				XCTAssert(QBEFunction.Uppercase.apply([QBEValue("Tommy")]) == QBEValue("TOMMY"), "Uppercase")
			
			case .Absolute:
				XCTAssert(QBEFunction.Absolute.apply([QBEValue(-1)]) == QBEValue(1), "Absolute")
				
			case .Count:
				XCTAssert(QBEFunction.Count.apply([]) == QBEValue(0), "Empty count returns zero")
				XCTAssert(QBEFunction.Count.apply([QBEValue(1), QBEValue(1), QBEValue.InvalidValue, QBEValue.EmptyValue]) == QBEValue(2), "Count does not include invalid values and empty values")
				
			case .Items:
				XCTAssert(QBEFunction.Items.apply([QBEValue("")]) == QBEValue(0), "Empty count returns zero")
				XCTAssert(QBEFunction.Items.apply([QBEValue("Foo,bar,baz")]) == QBEValue(3), "Count does not include invalid values and empty values")
				
			case .CountAll:
				XCTAssert(QBEFunction.CountAll.apply([QBEValue(1), QBEValue(1), QBEValue.InvalidValue, QBEValue.EmptyValue]) == QBEValue(4), "CountAll includes invalid values and empty values")
				
			case .Negate:
				XCTAssert(QBEFunction.Negate.apply([QBEValue(1337)]) == QBEValue(-1337), "Negate")
				
			case .Or:
				XCTAssert(QBEFunction.Or.apply([QBEValue(true), QBEValue(true)]) == QBEValue(true), "OR(true, true)")
				XCTAssert(QBEFunction.Or.apply([QBEValue(true), QBEValue(false)]) == QBEValue(true), "OR(true, false)")
				XCTAssert(QBEFunction.Or.apply([QBEValue(false), QBEValue(false)]) == QBEValue(false), "OR(false, false)")
				XCTAssert(!QBEFunction.Or.apply([QBEValue(true), QBEValue.InvalidValue]).isValid, "OR(true, invalid)")
				
			case .Acos:
				XCTAssert(QBEFunction.Acos.apply([QBEValue(0.337)]) == QBEValue(acos(0.337)), "Acos")
				XCTAssert(!QBEFunction.Acos.apply([QBEValue(1.337)]).isValid, "Acos")
				
			case .Asin:
				XCTAssert(QBEFunction.Asin.apply([QBEValue(0.337)]) == QBEValue(asin(0.337)), "Asin")
				XCTAssert(!QBEFunction.Asin.apply([QBEValue(1.337)]).isValid, "Asin")
				
			case .NormalInverse:
				let ni = QBEFunction.NormalInverse.apply([QBEValue(0.25), QBEValue(42), QBEValue(4)])
				XCTAssert(ni > QBEValue(39) && ni < QBEValue(40), "NormalInverse")
				
			case .Atan:
				XCTAssert(QBEFunction.Atan.apply([QBEValue(1.337)]) == QBEValue(atan(1.337)), "Atan")
				
			case .Cosh:
				XCTAssert(QBEFunction.Cosh.apply([QBEValue(1.337)]) == QBEValue(cosh(1.337)), "Cosh")
				
			case .Sinh:
				XCTAssert(QBEFunction.Sinh.apply([QBEValue(1.337)]) == QBEValue(sinh(1.337)), "Sinh")
				
			case .Tanh:
				XCTAssert(QBEFunction.Tanh.apply([QBEValue(1.337)]) == QBEValue(tanh(1.337)), "Tanh")
				
			case .Cos:
				XCTAssert(QBEFunction.Cos.apply([QBEValue(1.337)]) == QBEValue(cos(1.337)), "Cos")
				
			case .Sin:
				XCTAssert(QBEFunction.Sin.apply([QBEValue(1.337)]) == QBEValue(sin(1.337)), "Sin")
				
			case .Tan:
				XCTAssert(QBEFunction.Tan.apply([QBEValue(1.337)]) == QBEValue(tan(1.337)), "Tan")
				
			case .Sqrt:
				XCTAssert(QBEFunction.Sqrt.apply([QBEValue(1.337)]) == QBEValue(sqrt(1.337)), "Sqrt")
				XCTAssert(!QBEFunction.Sqrt.apply([QBEValue(-1)]).isValid, "Sqrt")
				
			case .Round:
				XCTAssert(QBEFunction.Round.apply([QBEValue(1.337)]) == QBEValue(1), "Round")
				XCTAssert(QBEFunction.Round.apply([QBEValue(1.337), QBEValue(2)]) == QBEValue(1.34), "Round")
				XCTAssert(QBEFunction.Round.apply([QBEValue(0.5)]) == QBEValue(1), "Round")
				
			case .Log:
				XCTAssert(QBEFunction.Log.apply([QBEValue(1.337)]) == QBEValue(log10(1.337)), "Log")
				XCTAssert(!QBEFunction.Log.apply([QBEValue(0)]).isValid, "Log")
				
			case .Exp:
				XCTAssert(QBEFunction.Exp.apply([QBEValue(1.337)]) == QBEValue(exp(1.337)), "Exp")
				XCTAssert(QBEFunction.Exp.apply([QBEValue(0)]) == QBEValue(1), "Exp")
				
			case .Ln:
				XCTAssert(QBEFunction.Ln.apply([QBEValue(1.337)]) == QBEValue(log10(1.337) / log10(exp(1.0))), "Ln")
				XCTAssert(!QBEFunction.Ln.apply([QBEValue(0)]).isValid, "Ln")
				
			case .Concat:
				XCTAssert(QBEFunction.Concat.apply([QBEValue(1), QBEValue("33"), QBEValue(false)]) == QBEValue("1330"), "Concat")
				
			case .If:
				XCTAssert(QBEFunction.If.apply([QBEValue(true), QBEValue(13), QBEValue(37)]) == QBEValue(13), "If")
				XCTAssert(QBEFunction.If.apply([QBEValue(false), QBEValue(13), QBEValue(37)]) == QBEValue(37), "If")
				XCTAssert(!QBEFunction.If.apply([QBEValue.InvalidValue, QBEValue(13), QBEValue(37)]).isValid, "If")
				
			case .Left:
				XCTAssert(QBEFunction.Left.apply([QBEValue(1337), QBEValue(3)]) == QBEValue(133), "Left")
				XCTAssert(!QBEFunction.Left.apply([QBEValue(1337), QBEValue(5)]).isValid, "Left")
				
			case .Right:
				XCTAssert(QBEFunction.Right.apply([QBEValue(1337), QBEValue(3)]) == QBEValue(337), "Right")
				XCTAssert(!QBEFunction.Right.apply([QBEValue(1337), QBEValue(5)]).isValid, "Right")
				
			case .Mid:
				XCTAssert(QBEFunction.Mid.apply([QBEValue(1337), QBEValue(3), QBEValue(1)]) == QBEValue(7), "Mid")
				XCTAssert(QBEFunction.Mid.apply([QBEValue(1337), QBEValue(3), QBEValue(10)]) == QBEValue(7), "Mid")
				
			case .Substitute:
				XCTAssert(QBEFunction.Substitute.apply([QBEValue("foobar"), QBEValue("foo"), QBEValue("bar")]) == QBEValue("barbar"), "Substitute")
				
			case .Length:
				XCTAssert(QBEFunction.Length.apply([QBEValue("test")]) == QBEValue(4), "Length")
				
			case .Sum:
				XCTAssert(QBEFunction.Sum.apply([1,3,3,7].map({return QBEValue($0)})) == QBEValue(1+3+3+7), "Sum")
				XCTAssert(QBEFunction.Sum.apply([]) == QBEValue(0), "Sum")
				
			case .Min:
				XCTAssert(QBEFunction.Min.apply([1,3,3,7].map({return QBEValue($0)})) == QBEValue(1), "Min")
				XCTAssert(!QBEFunction.Min.apply([]).isValid, "Min")
				
			case .Max:
				XCTAssert(QBEFunction.Max.apply([1,3,3,7].map({return QBEValue($0)})) == QBEValue(7), "Max")
				XCTAssert(!QBEFunction.Max.apply([]).isValid, "Max")
				
			case .Average:
				XCTAssert(QBEFunction.Average.apply([1,3,3,7].map({return QBEValue($0)})) == QBEValue((1.0+3.0+3.0+7.0)/4.0), "Average")
				XCTAssert(!QBEFunction.Average.apply([]).isValid, "Average")
				
			case .Trim:
				XCTAssert(QBEFunction.Trim.apply([QBEValue("   trim  ")]) == QBEValue("trim"), "Trim")
				XCTAssert(QBEFunction.Trim.apply([QBEValue("  ")]) == QBEValue(""), "Trim")
			
			case .Choose:
				XCTAssert(QBEFunction.Choose.apply([3,3,3,7].map({return QBEValue($0)})) == QBEValue(7), "Choose")
				XCTAssert(!QBEFunction.Choose.apply([QBEValue(3)]).isValid, "Choose")
				
			case .Random:
				let rv = QBEFunction.Random.apply([])
				XCTAssert(rv >= QBEValue(0.0) && rv <= QBEValue(1.0), "Random")
				
			case .RandomBetween:
				let rv = QBEFunction.RandomBetween.apply([QBEValue(-10), QBEValue(9)])
				XCTAssert(rv >= QBEValue(-10.0) && rv <= QBEValue(9.0), "RandomBetween")
				
			case .RandomItem:
				let items = [1,3,3,7].map({return QBEValue($0)})
				XCTAssert(items.contains(QBEFunction.RandomItem.apply(items)), "RandomItem")
				
			case .Pack:
				XCTAssert(QBEFunction.Pack.apply([QBEValue("He,llo"),QBEValue("World")]) == QBEValue(QBEPack(["He,llo", "World"]).stringValue), "Pack")
				
			case .Split:
				XCTAssert(QBEFunction.Split.apply([QBEValue("Hello#World"), QBEValue("#")]) == QBEValue("Hello,World"), "Split")
				
			case .Nth:
				XCTAssert(QBEFunction.Nth.apply([QBEValue("Foo,bar,baz"), QBEValue(3)]) == QBEValue("baz"), "Nth")
			
			case .Sign:
				XCTAssert(QBEFunction.Sign.apply([QBEValue(-1337)]) == QBEValue(-1), "Sign")
				XCTAssert(QBEFunction.Sign.apply([QBEValue(0)]) == QBEValue(0), "Sign")
				XCTAssert(QBEFunction.Sign.apply([QBEValue(1337)]) == QBEValue(1), "Sign")
				
			case .IfError:
				XCTAssert(QBEFunction.IfError.apply([QBEValue.InvalidValue, QBEValue(1337)]) == QBEValue(1337), "IfError")
				XCTAssert(QBEFunction.IfError.apply([QBEValue(1336), QBEValue(1337)]) == QBEValue(1336), "IfError")
				
			case .Levenshtein:
				XCTAssert(QBEFunction.Levenshtein.apply([QBEValue("tommy"), QBEValue("tom")]) == QBEValue(2), "Levenshtein")
				
			case .RegexSubstitute:
				XCTAssert(QBEFunction.RegexSubstitute.apply([QBEValue("Tommy"), QBEValue("m+"), QBEValue("@")]) == QBEValue("To@y"), "RegexSubstitute")
				
			case .Coalesce:
				XCTAssert(QBEFunction.Coalesce.apply([QBEValue.InvalidValue, QBEValue.InvalidValue, QBEValue(1337)]) == QBEValue(1337), "Coalesce")
				
			case .Capitalize:
				XCTAssert(QBEFunction.Capitalize.apply([QBEValue("tommy van DER vorst")]) == QBEValue("Tommy Van Der Vorst"), "Capitalize")
				
			case .URLEncode:
				// FIXME: URLEncode should probably also encode slashes, right?
				XCTAssert(QBEFunction.URLEncode.apply([QBEValue("tommy%/van DER vorst")]) == QBEValue("tommy%25/van%20DER%20vorst"), "URLEncode")
				
			case .In:
				XCTAssert(QBEFunction.In.apply([QBEValue(1), QBEValue(1), QBEValue(2)]) == QBEValue.BoolValue(true), "In")
				XCTAssert(QBEFunction.In.apply([QBEValue(1), QBEValue(3), QBEValue(2)]) == QBEValue.BoolValue(false), "In")
				
			case .NotIn:
				XCTAssert(QBEFunction.NotIn.apply([QBEValue(1), QBEValue(2), QBEValue(2)]) == QBEValue.BoolValue(true), "NotIn")
				XCTAssert(QBEFunction.NotIn.apply([QBEValue(1), QBEValue(1), QBEValue(2)]) == QBEValue.BoolValue(false), "NotIn")
			
			case .ToUnixTime:
				let d = NSDate()
				XCTAssert(QBEFunction.ToUnixTime.apply([QBEValue(d)]) == QBEValue(d.timeIntervalSince1970), "ToUnixTime")
				let epoch = NSDate(timeIntervalSince1970: 0)
				XCTAssert(QBEFunction.ToUnixTime.apply([QBEValue(epoch)]) == QBEValue(0), "ToUnixTime")
				
			case .FromUnixTime:
				XCTAssert(QBEFunction.FromUnixTime.apply([QBEValue(0)]) == QBEValue(NSDate(timeIntervalSince1970: 0)), "FromUnixTime")
				
			case .Now:
				break
				
			case .FromISO8601:
				XCTAssert(QBEFunction.FromISO8601.apply([QBEValue("1970-01-01T00:00:00Z")]) == QBEValue(NSDate(timeIntervalSince1970: 0)), "FromISO8601")
				
			case .ToLocalISO8601:
				break
				
			case .ToUTCISO8601:
				XCTAssert(QBEFunction.ToUTCISO8601.apply([QBEValue(NSDate(timeIntervalSince1970: 0))]) == QBEValue("1970-01-01T00:00:00Z"), "ToUTCISO8601")
				
			case .FromExcelDate:
				XCTAssert(QBEFunction.FromExcelDate.apply([QBEValue(25569.0)]) == QBEValue(NSDate(timeIntervalSince1970: 0.0)), "FromExcelDate")
				XCTAssert(QBEFunction.FromExcelDate.apply([QBEValue(42210.8330092593)]) == QBEValue(NSDate(timeIntervalSinceReferenceDate: 459547172.0)), "FromExcelDate")
				
			case .ToExcelDate:
				XCTAssert(QBEFunction.ToExcelDate.apply([QBEValue(NSDate(timeIntervalSince1970: 0.0))]) == QBEValue(25569.0), "ToExcelDate")
				XCTAssert(QBEFunction.ToExcelDate.apply([QBEValue(NSDate(timeIntervalSinceReferenceDate: 459547172))]).doubleValue!.approximates(42210.8330092593, epsilon: 0.01), "ToExcelDate")
				
			case .UTCDate:
				XCTAssert(QBEFunction.UTCDate.apply([QBEValue(2001), QBEValue(1), QBEValue(1)]) == QBEValue.DateValue(0.0), "UTCDate")
				
			case .UTCYear:
				XCTAssert(QBEFunction.UTCYear.apply([QBEValue.DateValue(0)]) == QBEValue(2001), "UTCYear")
				
			case .UTCMonth:
				XCTAssert(QBEFunction.UTCMonth.apply([QBEValue.DateValue(0)]) == QBEValue(1), "UTCMonth")
				
			case .UTCDay:
				XCTAssert(QBEFunction.UTCDay.apply([QBEValue.DateValue(0)]) == QBEValue(1), "UTCDay")
				
			case .UTCHour:
				XCTAssert(QBEFunction.UTCHour.apply([QBEValue.DateValue(0)]) == QBEValue(0), "UTCHour")
				
			case .UTCMinute:
				XCTAssert(QBEFunction.UTCMinute.apply([QBEValue.DateValue(0)]) == QBEValue(0), "UTCMinute")
				
			case .UTCSecond:
				XCTAssert(QBEFunction.UTCSecond.apply([QBEValue.DateValue(0)]) == QBEValue(0), "UTCSecond")
			}
		}
		
		// Binaries
		XCTAssert(QBEBinary.ContainsString.apply(QBEValue("Tommy"), QBEValue("om"))==QBEValue(true), "Contains string operator should be case-insensitive")
		XCTAssert(QBEBinary.ContainsString.apply(QBEValue("Tommy"), QBEValue("x"))==QBEValue(false), "Contains string operator should work")
		XCTAssert(QBEBinary.ContainsStringStrict.apply(QBEValue("Tommy"), QBEValue("Tom"))==QBEValue(true), "Strict contains string operator should work")
		XCTAssert(QBEBinary.ContainsStringStrict.apply(QBEValue("Tommy"), QBEValue("tom"))==QBEValue(false), "Strict contains string operator should be case-sensitive")
		XCTAssert(QBEBinary.ContainsStringStrict.apply(QBEValue("Tommy"), QBEValue("x"))==QBEValue(false), "Strict contains string operator should work")
		
		// Split / nth
		XCTAssert(QBEFunction.Split.apply([QBEValue("van der Vorst, Tommy"), QBEValue(" ")]).stringValue == "van,der,Vorst$0,Tommy", "Split works")
		XCTAssert(QBEFunction.Nth.apply([QBEValue("van,der,Vorst$0,Tommy"), QBEValue(3)]).stringValue == "Vorst,", "Nth works")
		XCTAssert(QBEFunction.Items.apply([QBEValue("van,der,Vorst$0,Tommy")]).intValue == 4, "Items works")
		
		// Stats
		let z = QBEFunction.NormalInverse.apply([QBEValue(0.9), QBEValue(10), QBEValue(5)]).doubleValue
		XCTAssert(z != nil, "NormalInverse should return a value under normal conditions")
		XCTAssert(z! > 16.406 && z! < 16.408, "NormalInverse should results that are equal to those of NORM.INV.N in Excel")
	}
	
	func compareData(job: QBEJob, _ a: QBEData, _ b: QBEData, callback: (Bool) -> ()) {
		a.raster(job, callback: { (aRasterFallible) -> () in
			switch aRasterFallible {
				case .Success(let aRaster):
					b.raster(job, callback: { (bRasterFallible) -> () in
						switch bRasterFallible {
							case .Success(let bRaster):
								let equal = aRaster.compare(bRaster)
								if !equal {
									job.log("A: \(aRaster.debugDescription)")
									job.log("B: \(bRaster.debugDescription)")
								}
								callback(equal)
							
							case .Failure(let error):
								XCTFail(error)
						}
					})
				
				case .Failure(let error):
					XCTFail(error)
			}
		})
	}
	
	func testCoalescer() {
		let raster = QBERaster(data: [
			[QBEValue.IntValue(1), QBEValue.IntValue(2), QBEValue.IntValue(3)],
			[QBEValue.IntValue(4), QBEValue.IntValue(5), QBEValue.IntValue(6)],
			[QBEValue.IntValue(7), QBEValue.IntValue(8), QBEValue.IntValue(9)]
		], columnNames: [QBEColumn("a"), QBEColumn("b"), QBEColumn("c")], readOnly: true)
		
		let inData = QBERasterData(raster: raster)
		let inOptData = QBECoalescedData(inData)
		let job = QBEJob(.UserInitiated)
		
		compareData(job, inData.limit(2).limit(1), inOptData.limit(2).limit(1)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for limit(2).limit(1) should equal normal result")
		}
		
		compareData(job, inData.offset(2).offset(1), inOptData.offset(2).offset(1)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for offset(2).offset(1) should equal normal result")
		}
		
		compareData(job, inData.offset(3), inOptData.offset(2).offset(1)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for offset(2).offset(1) should equal offset(3)")
		}
		
		// Verify coalesced sort operations
		let aSorts = [
			QBEOrder(expression: QBESiblingExpression(columnName: "a"), ascending: true, numeric: true),
			QBEOrder(expression: QBESiblingExpression(columnName: "b"), ascending: false, numeric: true)
		]
		
		let bSorts = [
			QBEOrder(expression: QBESiblingExpression(columnName: "c"), ascending: true, numeric: true)
		]
		
		compareData(job, inData.sort(aSorts).sort(bSorts), inData.sort(bSorts + aSorts)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for sort().sort() should equal normal result")
		}
		
		compareData(job, inData.sort(aSorts).sort(bSorts), inOptData.sort(aSorts).sort(bSorts)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for sort().sort() should equal normal result")
		}
		
		// Verify coalesced transpose
		compareData(job, inData.transpose().transpose(), inOptData.transpose().transpose()) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for transpose().transpose() should equal normal result")
		}
		
		compareData(job, inData.transpose().transpose().transpose(), inOptData.transpose().transpose().transpose()) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for transpose().transpose().transpose() should equal normal result")
		}
		
		compareData(job, inData, inOptData.transpose().transpose()) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for transpose().transpose() should equal original result")
		}
	}
	
	func testInferer() {
		let locale = QBELocale(language: QBELocale.defaultLanguage)
		var suggestions: [QBEExpression] = []
		let cols = ["A","B","C","D"].map({QBEColumn($0)})
		let row = [1,3,4,6].map({QBEValue($0)})
		QBEExpression.infer(nil, toValue: QBEValue(24), suggestions: &suggestions, level: 10, row: QBERow(row, columnNames: cols), column: 0, maxComplexity: Int.max, previousValues: [])
		suggestions.each({QBELog($0.explain(locale))})
		XCTAssert(suggestions.count>0, "Can solve the 1-3-4-6 24 game.")
	}
	
	func testQBEDataImplementations() {
		let job = QBEJob(.UserInitiated)
		
		var d: [[QBEValue]] = []
		for i in 0..<1000 {
			d.append([QBEValue(i), QBEValue(i+1), QBEValue(i+2)])
		}
		
		func assertRaster(raster: QBEFallible<QBERaster>, message: String, condition: (QBERaster) -> Bool) {
			switch raster {
				case .Success(let r):
					XCTAssertTrue(condition(r), message)
				
				case .Failure(let error):
					XCTFail("\(message) failed: \(error)")
			}
		}
		
		let data = QBERasterData(data: d, columnNames: [QBEColumn("X"), QBEColumn("Y"), QBEColumn("Z")])
		
		// Limit
		data.limit(5).raster(job) { assertRaster($0, message: "Limit actually works") { $0.rowCount == 5 } }
		
		// Offset
		data.offset(5).raster(job) { assertRaster($0, message: "Offset actually works", condition: { $0.rowCount == 1000 - 5 }) }
		
		// Distinct
		data.distinct().raster(job) {
			assertRaster($0, message: "Distinct removes no columns", condition: { $0.columnCount == 3 })
			assertRaster($0, message: "Distinct removes no rows when they are all unique", condition: { $0.rowCount == 1000 })
		}
		
		// Union
		let secondData = QBERasterData(data: d, columnNames: [QBEColumn("X"), QBEColumn("B"), QBEColumn("C")])
		data.union(secondData).raster(job) {
			assertRaster($0, message: "Union creates the proper number of columns", condition: { $0.columnCount == 5 })
			assertRaster($0, message: "Union creates the proper number of rows", condition: { $0.rowCount == 2000 })
		}
		data.union(data).raster(job) {
			assertRaster($0, message: "Union creates the proper number of columns in self-union scenario", condition: { $0.columnCount == 3 })
			assertRaster($0, message: "Union creates the proper number of rows in self-union scenario", condition: { $0.rowCount == 2000 })
		}
		
		// Join
		data.join(QBEJoin(type: .LeftJoin, foreignData: secondData, expression: QBEBinaryExpression(first: QBESiblingExpression(columnName: "X"), second: QBEForeignExpression(columnName: "X"), type: .Equal))).raster(job) {
			assertRaster($0, message: "Join returns the appropriate number of rows in a one-to-one scenario", condition: { $0.rowCount == 1000 })
			assertRaster($0, message: "Join returns the appropriate number of columns", condition: { $0.columnCount == 5 })
		}
		data.join(QBEJoin(type: .LeftJoin, foreignData: data, expression: QBEBinaryExpression(first: QBESiblingExpression(columnName: "X"), second: QBEForeignExpression(columnName: "X"), type: .Equal))).raster(job) {
			assertRaster($0, message: "Join returns the appropriate number of rows in a self-join one-to-one scenario", condition: { $0.rowCount == 1000 })
			assertRaster($0, message: "Join returns the appropriate number of columns in a self-join", condition: { $0.columnCount == 3 })
		}
		
		// Select columns
		data.selectColumns(["THIS_DOESNT_EXIST"]).columnNames(job) { (r) -> () in
			switch r {
				case .Success(let cns):
					XCTAssert(cns.count == 0, "Selecting an invalid column returns a set without columns")
				
				case .Failure(let error):
					XCTFail(error)
			}
		}
		
		// Transpose (repeatedly transpose and see if we end up with the initial value)
		data.raster(job) { (r) -> () in
			switch r {
				case .Success(let raster):
					let rowsBefore = raster.rowCount
					let columnsBefore = raster.columnCount
					
					self.measureBlock {
						var td: QBEData = data
						for _ in 1...11 {
							td = td.transpose()
						}
						
						td.raster(job) { assertRaster($0, message: "Row count matches") { $0.rowCount == columnsBefore - 1 } }
						td.raster(job) { assertRaster($0, message: "Column count matches") { $0.columnCount == rowsBefore + 1 } }
					}
			
				case .Failure(let error):
					XCTFail(error)
			}
			
		}
		
		// Empty raster behavior
		let emptyRasterData = QBERasterData(data: [], columnNames: [])
		emptyRasterData.limit(5).raster(job) { assertRaster($0, message: "Limit works when number of rows > available rows") { $0.rowCount == 0 } }
		emptyRasterData.selectColumns([QBEColumn("THIS_DOESNT_EXIST")]).raster(job) { assertRaster($0, message: "Selecting an invalid column works properly in empty raster") { $0.columnNames.count == 0 } }
	}
	
    func testQBERaster() {
		let job = QBEJob(.UserInitiated)
		
		var d: [[QBEValue]] = []
		for i in 0...1000 {
			d.append([QBEValue(i), QBEValue(i+1), QBEValue(i+2)])
		}
		
		let rasterData = QBERasterData(data: d, columnNames: [QBEColumn("X"), QBEColumn("Y"), QBEColumn("Z")])
		rasterData.raster(job) { (raster) -> () in
			switch raster {
				case .Success(let r):
					XCTAssert(r.indexOfColumnWithName("X")==0, "First column has index 0")
					XCTAssert(r.indexOfColumnWithName("x")==0, "Column names should be case-insensitive")
					XCTAssert(r.rowCount == 1001, "Row count matches")
					XCTAssert(r.columnCount == 3, "Column count matches")
				
				case .Failure(let error):
					XCTFail(error)
			}
		}
    }
	
	func testThreading() {
		let data = Array<Int>(0...5000000)
		let expectFinish = self.expectationWithDescription("Parallel map finishes in time")
		
		let future = data.parallel(
			map: { (slice: ArraySlice<Int>) -> [Int] in
				//println("Worker \(slice)")
				return Array(slice.map({return $0 * 2}))
			},
			reduce: {(s, r) -> Int in
				var greatest = r
				for number in s {
					greatest = (greatest == nil || number > greatest) ? number : greatest
				}
				return greatest ?? 0
			}
		)
		
		future.get {(result) in
			XCTAssert(result != nil && result! == 10000000, "Parallel M/R delivers the correct result")
			expectFinish.fulfill()
		}
		
		self.waitForExpectationsWithTimeout(5.0, handler: { (err) -> Void in
			print("Error=\(err)")
		})
	}
}
