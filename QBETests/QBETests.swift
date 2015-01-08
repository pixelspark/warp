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
	
	func testArithmetic() {
		XCTAssert(QBEValue(12) * QBEValue(13) == QBEValue(156), "Integer multiplication")
		XCTAssert(QBEValue(12.2) * QBEValue(13.3) == QBEValue(162.26), "Double multiplication")
		XCTAssert(QBEValue(12) * QBEValue(13) == QBEValue(156), "Integer multiplication to double")
		XCTAssert(QBEValue("1337") & QBEValue("h4x0r") == QBEValue("1337h4x0r"), "String string concatenation")
		
		XCTAssert(QBEValue(12) / QBEValue(2) == QBEValue(6), "Integer division to double")
		XCTAssert(QBEValue(10.0) / QBEValue(0) == QBEValue(), "Division by zero")
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
		XCTAssert(raster.indexOfColumnWithName("x") == nil, "Column names should be case-sensitive")
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
