import XCTest
import WarpCore
@testable import Warp

class QBETests: XCTestCase {
	func testKey() {
		let secret = "omega3"
		let key = QBESecret(serviceName: "nl.pixelspark.Warp.QBETest", accountName: "tester", friendlyName: "Test key")
		key.delete()
		key.stringValue = secret
		let recovered = key.stringValue
		XCTAssert(recovered != nil && recovered! == secret, "Write password")

		// Attempt an update
		let secondSecret = "omega4"
		key.stringValue = secondSecret
		let recoveredSecond = key.stringValue
		XCTAssert(recoveredSecond != nil && recoveredSecond! == secondSecret, "Update password")

		XCTAssert(key.delete(), "Delete key")
	}

	func testCSV() {
		var outstanding = 2

		func testAsync(block: (callback: () -> ()) -> ()) {
			let expectFinish = self.expectationWithDescription("CSV tests")

			block {
				expectFinish.fulfill()
			}

			self.waitForExpectationsWithTimeout(5.0) { (err) -> Void in
				if let e = err {
					// Note: referencing self here deliberately to prevent test from being destroyed prematurely
					print("Error=\(e) \(self)")
				}
			}
		}

		func rasterEquals(raster: Raster, grid: [[Value]]) -> Bool {
			for row in 0..<raster.rowCount {
				if raster[row] != grid[row] {
					return false
				}
			}
			return true
		}

		let locale = Locale()
		let job = Job(.UserInitiated)

		// Test general functioning of CSV stream
		let url = NSBundle(forClass: QBETests.self).URLForResource("regular", withExtension: "csv")
		let csv = QBECSVStream(url: url!, fieldSeparator: ";".utf16.first!, hasHeaders: true, locale: locale)

		testAsync { callback in
			csv.columns(job) { result in
				result.require { cols in
					XCTAssert(cols == ["a","b","c"], "Invalid columns loaded")
					callback()
				}
			}
		}

		testAsync { callback in
			StreamData(source: csv).raster(job) { result in
				result.require { raster in
					XCTAssert(raster.rowCount == 3, "Need three rows")
					XCTAssert(rasterEquals(raster, grid: [
						[1,2,3].map { Value.IntValue($0) },
						[4,5,6].map { Value.IntValue($0) },
						[7,8,9].map { Value.IntValue($0) }
					]), "Raster invalid")

					callback()
				}
			}
		}

		// Test functioning of CSV stream with file that contains rows that have more columns than specified
		let url2 = NSBundle(forClass: QBETests.self).URLForResource("extraneous-columns", withExtension: "csv")
		let csv2 = QBECSVStream(url: url2!, fieldSeparator: ";".utf16.first!, hasHeaders: true, locale: locale)

		testAsync { callback in
			StreamData(source: csv2).raster(job) { result in
				result.require { raster in
					XCTAssert(raster.rowCount == 3, "Need three rows")
					XCTAssert(rasterEquals(raster, grid: [
						[1,2,3].map { Value.IntValue($0) },
						[4,5,6].map { Value.IntValue($0) },
						[7,8,9].map { Value.IntValue($0) }
						]), "Raster invalid")

					callback()
				}
			}
		}

		// Test functioning of CSV stream with file that contains rows that have less columns then specified
		let url3 = NSBundle(forClass: QBETests.self).URLForResource("missing-columns", withExtension: "csv")
		let csv3 = QBECSVStream(url: url3!, fieldSeparator: ";".utf16.first!, hasHeaders: true, locale: locale)

		testAsync { callback in
			StreamData(source: csv3).raster(job) { result in
				result.require { raster in
					XCTAssert(raster.rowCount == 3, "Need three rows")
					XCTAssert(rasterEquals(raster, grid: [
						[Value.IntValue(1), Value.IntValue(2), Value.EmptyValue],
						[4,5,6].map { Value.IntValue($0) },
						[7,8,9].map { Value.IntValue($0) }
						]), "Raster invalid")

					callback()
				}
			}
		}
	}
}
