import Cocoa
import XCTest
import QBE

class QBETests: XCTestCase {
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
	
	func testQBEValue() {
		XCTAssert(QBEValue("hello") == QBEValue("hello"), "String equality")
		XCTAssert(QBEValue("hello") != QBEValue("HELLO"), "String equality is case sensitive")
		XCTAssert(QBEValue(1337) == QBEValue("1337"), "Numbers are strings")
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
		XCTAssert(QBEValue(12) * QBEValue(13) == QBEValue(156), "Integer multiplication")
		XCTAssert(QBEValue(12.2) * QBEValue(13.3) == QBEValue(162.26), "Double multiplication")
		XCTAssert(QBEValue(12) * QBEValue(13) == QBEValue(156), "Integer multiplication to double")
		XCTAssert(QBEValue("1337") & QBEValue("h4x0r") == QBEValue("1337h4x0r"), "String string concatenation")
		
		XCTAssert(QBEValue(12) / QBEValue(2) == QBEValue(6), "Integer division to double")
		XCTAssert(!(QBEValue(10.0) / QBEValue(0)).isValid, "Division by zero")
		
		XCTAssert((QBEValue(12) < QBEValue(25)) == QBEValue(true), "Less than")
		XCTAssert((QBEValue(12) > QBEValue(25)) == QBEValue(false), "Greater than")
		XCTAssert((QBEValue(12) <= QBEValue(25)) == QBEValue(true), "Less than or equal")
		XCTAssert((QBEValue(12) >= QBEValue(25)) == QBEValue(false), "Greater than or equal")
		XCTAssert((QBEValue(12) <= QBEValue(12)) == QBEValue(true), "Less than or equal")
		XCTAssert((QBEValue(12) >= QBEValue(12)) == QBEValue(true), "Greater than or equal")
		
		XCTAssert((QBEValue(12.0) == QBEValue(12)) == QBEValue(true), "Double == int")
		XCTAssert((QBEValue(12) == QBEValue(12.0)) == QBEValue(true), "Int == double")
		XCTAssert((QBEValue(12.0) != QBEValue(12)) == QBEValue(false), "Double != int")
		XCTAssert((QBEValue(12) != QBEValue(12.0)) == QBEValue(false), "Int != double")
		XCTAssert(QBEValue("12") == QBEValue(12), "String number is treated as number")
		XCTAssert((QBEValue("12") + QBEValue("13")) == QBEValue(25), "String number is treated as number")
		
		XCTAssert(QBEValue.EmptyValue == QBEValue.EmptyValue, "Empty equals empty")
		XCTAssert(QBEValue.EmptyValue != QBEValue(0), "Empty is not equal to zero")
		XCTAssert(QBEValue.EmptyValue != QBEValue(Double.NaN), "Empty is not equal to double NaN")
		XCTAssert(QBEValue.EmptyValue != QBEValue(""), "Empty is not equal to empty string")
		
		XCTAssert(!(QBEValue.InvalidValue == QBEValue.InvalidValue), "Invalid value equals nothing")
		XCTAssert(QBEValue.InvalidValue != QBEValue.InvalidValue, "Invalid value inequals other invalid value")
	}
	
	func testFormulaParser() {
		let locale = QBEDefaultLocale()
		
		// Test whether parsing goes right
		XCTAssert(QBEFormula(formula: "=6/(1-3/4)", locale: locale) != nil, "Formula in default dialect")
		XCTAssert(QBEFormula(formula: "6/(1-3/4)", locale: locale) == nil, "Formula needs to start with equals sign")
		XCTAssert(QBEFormula(formula: "=6/(1-3/4)±", locale: locale) == nil, "Formula needs to ignore any garbage near the end of a formula")
		XCTAssert(QBEFormula(formula: "=6/(1-3/4)+[@colRef]", locale: locale) != nil, "Formula in default dialect with column ref")
		XCTAssert(QBEFormula(formula: "=6/(1-3/4)+[@colRef]&\"stringLit\"", locale: locale) != nil, "Formula in default dialect with string literal")
		
		// Test results
		let raster = QBERaster()
		XCTAssert(QBEFormula(formula: "=6/(1-3/4)", locale: locale)!.root.apply([], columns: raster.columnNames, inputValue: nil) == QBEValue(24), "Formula in default dialect")
		
		// Test whether parsing goes wrong when it should
		XCTAssert(QBEFormula(formula: "", locale: locale) == nil, "Empty formula")
		XCTAssert(QBEFormula(formula: "=", locale: locale) == nil, "Empty formula with equals sign")
		XCTAssert(QBEFormula(formula: "=1+22@D@D@", locale: locale) == nil, "Garbage formula")
		

		XCTAssert(QBEFormula(formula: "=fALse", locale: locale) != nil, "Constant names should be case-insensitive")
		XCTAssert(QBEFormula(formula: "=siN(1)", locale: locale) != nil, "Function names should be case-insensitive")
	}
	
	func testExpressions() {
		XCTAssert(QBELiteralExpression(QBEValue(13.46)).isConstant, "Literal expression should be constant")
		XCTAssert(!QBEFunctionExpression(arguments: [], type: QBEFunction.RandomItem).isConstant, "Non-deterministic function expression should not be constant")
		
		XCTAssert(!QBEBinaryExpression(first: QBELiteralExpression(QBEValue(13.45)), second: QBEFunctionExpression(arguments: [], type: QBEFunction.RandomItem), type: QBEBinary.Equal).isConstant, "Binary operator applied to at least one non-constant expression should not be constant itself")
	}
	
	func testFunctions() {
		XCTAssert(QBEFunction.And.apply([QBEValue(true), QBEValue(true)]) == QBEValue(true), "AND(true, true)")
		XCTAssert(QBEFunction.And.apply([QBEValue(true), QBEValue(false)]) == QBEValue(false), "AND(true, false)")
		XCTAssert(QBEFunction.And.apply([QBEValue(false), QBEValue(false)]) == QBEValue(false), "AND(false, false)")
		
		XCTAssert(QBEFunction.Lowercase.apply([QBEValue("Tommy")]) == QBEValue("tommy"), "Lowercase")
		XCTAssert(QBEFunction.Uppercase.apply([QBEValue("Tommy")]) == QBEValue("TOMMY"), "Uppercase")
		
		XCTAssert(QBEFunction.Absolute.apply([QBEValue(-1)]) == QBEValue(1), "Absolute")
		
		XCTAssert(QBEFunction.Count.apply([]) == QBEValue(0), "Empty count returns zero")
		XCTAssert(QBEFunction.Count.apply([QBEValue(1), QBEValue(1), QBEValue.InvalidValue, QBEValue.EmptyValue]) == QBEValue(2), "Count does not include invalid values and empty values")
		XCTAssert(QBEFunction.CountAll.apply([QBEValue(1), QBEValue(1), QBEValue.InvalidValue, QBEValue.EmptyValue]) == QBEValue(4), "CountAll includes invalid values and empty values")
	}
	
	func testInferer() {
		var suggestions: [QBEExpression] = []
		let cols = ["A","B","C","D"].map({QBEColumn($0)})
		let row = [1,3,4,6].map({QBEValue($0)})
		QBEExpression.infer(nil, toValue: QBEValue(24), suggestions: &suggestions, level: 10, columns: cols, row: row, column: 0, maxComplexity: Int.max, previousValues: [])
		suggestions.each({println($0.explain(QBEDefaultLocale()))})
		XCTAssert(suggestions.count>0, "Can solve the 1-3-4-6 24 game.")
	}
	
	func testQBEDataImplementations() {
		var d: [[QBEValue]] = []
		for i in 0...1000 {
			d.append([QBEValue(i), QBEValue(i+1), QBEValue(i+2)])
		}
		
		// Test the raster data implementation (the tests below are valid for all QBEData implementations)
		let data = QBERasterData(data: d, columnNames: [QBEColumn("X"), QBEColumn("Y"), QBEColumn("Z")])
		data.limit(5).raster({ (r) -> () in
			XCTAssert(r.rowCount == 5, "Limit actually works")
		}, job: nil)
		
		data.selectColumns(["THIS_DOESNT_EXIST"]).columnNames { (r) -> () in
			XCTAssert(r.count == 0, "Selecting an invalid column returns a set without columns")
		}
		
		// Repeatedly transpose and check whether the expected number of rows and columns results
		data.raster({ (r) -> () in
			let rowsBefore = r.rowCount
			let columnsBefore = r.columnCount
			
			self.measureBlock {
				var td: QBEData = data
				for i in 1...11 {
					td = td.transpose()
				}
			
				td.raster({ (s) -> () in
					XCTAssert(s.rowCount == columnsBefore-1, "Row count matches")
					XCTAssert(s.columnCount == rowsBefore+1, "Column count matches")
				}, job: nil)
			}
		}, job: nil)
		
		// Test an empty raster
		let emptyRasterData = QBERasterData(data: [], columnNames: [])
		emptyRasterData.limit(5).raster({(r) -> () in
			XCTAssert(r.rowCount == 0, "Limit works when number of rows > available rows")
		}, job: nil)
		
		emptyRasterData.selectColumns([QBEColumn("THIS_DOESNT_EXIST")]).raster({ (r) -> () in
			XCTAssert(r.columnNames.count == 0, "Selecting an invalid column works properly in empty raster")
		}, job: nil)
	}
	
    func testQBERaster() {
		var d: [[QBEValue]] = []
		for i in 0...1000 {
			d.append([QBEValue(i), QBEValue(i+1), QBEValue(i+2)])
		}
		
		let rasterData = QBERasterData(data: d, columnNames: [QBEColumn("X"), QBEColumn("Y"), QBEColumn("Z")])
		rasterData.raster({ (raster) -> () in
			XCTAssert(raster.indexOfColumnWithName("X")==0, "First column has index 0")
			XCTAssert(raster.indexOfColumnWithName("x")==0, "Column names should be case-insensitive")
			XCTAssert(raster.rowCount == 1001, "Row count matches")
			XCTAssert(raster.columnCount == 3, "Column count matches")
		}, job: nil)
    }
    
}
