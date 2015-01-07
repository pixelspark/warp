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
    
    func testQBERaster() {
		var d: [[QBEValue]] = []
		d.append([QBEValue("X"), QBEValue("Y"), QBEValue("Z")])
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
