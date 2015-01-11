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
	}
	
	func testArithmetic() {
		XCTAssert(QBEValue(12) * QBEValue(13) == QBEValue(156), "Integer multiplication")
		XCTAssert(QBEValue(12.2) * QBEValue(13.3) == QBEValue(162.26), "Double multiplication")
		XCTAssert(QBEValue(12) * QBEValue(13) == QBEValue(156), "Integer multiplication to double")
		XCTAssert(QBEValue("1337") & QBEValue("h4x0r") == QBEValue("1337h4x0r"), "String string concatenation")
		
		XCTAssert(QBEValue(12) / QBEValue(2) == QBEValue(6), "Integer division to double")
		XCTAssert(QBEValue(10.0) / QBEValue(0) == QBEValue(), "Division by zero")
		
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
		XCTAssert(QBEFormula(formula: "=6/(1-3/4)", locale: locale)!.root.apply(raster, rowNumber: 0, inputValue: nil) == QBEValue(24), "Formula in default dialect")
		
		// Test whether parsing goes wrong when it should
		XCTAssert(QBEFormula(formula: "", locale: locale) == nil, "Empty formula")
		XCTAssert(QBEFormula(formula: "=", locale: locale) == nil, "Empty formula with equals sign")
		XCTAssert(QBEFormula(formula: "=1+22@D@D@", locale: locale) == nil, "Garbage formula")
		

		XCTAssert(QBEFormula(formula: "=fALse", locale: locale) != nil, "Constant names should be case-insensitive")
		XCTAssert(QBEFormula(formula: "=siN(1)", locale: locale) != nil, "Function names should be case-insensitive")
	}
	
	func testFunctions() {
		XCTAssert(QBEFunction.And.apply([QBEValue(true), QBEValue(true)]) == QBEValue(true), "AND(true, true)")
		XCTAssert(QBEFunction.And.apply([QBEValue(true), QBEValue(false)]) == QBEValue(false), "AND(true, false)")
		XCTAssert(QBEFunction.And.apply([QBEValue(false), QBEValue(false)]) == QBEValue(false), "AND(false, false)")
		
		XCTAssert(QBEFunction.Lowercase.apply([QBEValue("Tommy")]) == QBEValue("tommy"), "Lowercase")
		XCTAssert(QBEFunction.Uppercase.apply([QBEValue("Tommy")]) == QBEValue("TOMMY"), "Uppercase")
		
		XCTAssert(QBEFunction.Absolute.apply([QBEValue(-1)]) == QBEValue(1), "Absolute")
	}
	
    func testQBERaster() {
		var d: [[QBEValue]] = []
		d.append([QBEValue("X"), QBEValue("Y"), QBEValue( "Z")])
		for i in 0...1000 {
			d.append([QBEValue(i), QBEValue(i+1), QBEValue(i+2)])
		}
		
		let rasterData = QBERasterData(data: d)
		let raster = rasterData.raster()
		
		XCTAssert(raster.indexOfColumnWithName("X")==0, "First column has index 0")
		XCTAssert(raster.indexOfColumnWithName("x")==0, "Column names should be case-insensitive")
		XCTAssert(rasterData.raster().rowCount == 1001, "Row count matches")
		XCTAssert(rasterData.raster().columnCount == 3, "Column count matches")
		
		self.measureBlock() {
			var td: QBEData = rasterData
			for i in 1...11 {
				td = td.transpose()
			}

			XCTAssert(td.raster().rowCount == 2, "Row count matches")
			XCTAssert(td.raster().columnCount == 1002, "Column count matches")
        }
    }
    
}
