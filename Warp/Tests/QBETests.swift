import XCTest
import WarpCore
import WarpConduit
@testable import Warp

class QBETests: XCTestCase {
	func testKey() {
		let secret = "omega3"
		let key = QBESecret(serviceName: "nl.pixelspark.Warp.QBETest", accountName: "tester", friendlyName: "Test key")

		if case .failure(let m) = key.setData("xxx".data(using: .utf8)) {
			XCTFail(m)
		}

		if case .failure(let m) = key.delete() {
			XCTFail(m)
		}

		key.stringValue = secret
		let recovered = key.stringValue
		XCTAssert(recovered != nil && recovered! == secret, "Write password")

		// Attempt an update
		let secondSecret = "omega4"
		key.stringValue = secondSecret
		let recoveredSecond = key.stringValue
		XCTAssert(recoveredSecond != nil && recoveredSecond! == secondSecret, "Update password")

		if case .failure(let m) = key.delete() {
			XCTFail(m)
		}
	}

	private func asyncTest(_ block: (_ callback: @escaping () -> ()) -> ()) {
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

	func testCSV() {
		let locale = Language()
		let job = Job(.userInitiated)

		// Test general functioning of CSV stream
		let url = Bundle(for: QBETests.self).url(forResource: "regular", withExtension: "csv")
		let csv = CSVStream(url: url!, fieldSeparator: ";".utf16.first!, hasHeaders: true, locale: locale)

		asyncTest { callback in
			csv.columns(job) { result in
				result.require { cols in
					XCTAssert(cols == ["a","b","c"], "Invalid columns loaded")
					callback()
				}
			}
		}

		asyncTest { callback in
			StreamDataset(source: csv).raster(job) { result in
				result.require { raster in
					XCTAssert(raster.rowCount == 3, "Need three rows")
					XCTAssert(QBETests.rasterEquals(raster, grid: [
						[1,2,3].map { Value.int($0) },
						[4,5,6].map { Value.int($0) },
						[7,8,9].map { Value.int($0) }
					]), "Raster invalid")

					callback()
				}
			}
		}

		// Test functioning of CSV stream with file that contains rows that have more columns than specified
		let url2 = Bundle(for: QBETests.self).url(forResource: "extraneous-columns", withExtension: "csv")
		let csv2 = CSVStream(url: url2!, fieldSeparator: ";".utf16.first!, hasHeaders: true, locale: locale)

		asyncTest { callback in
			StreamDataset(source: csv2).raster(job) { result in
				result.require { raster in
					XCTAssert(raster.rowCount == 3, "Need three rows")
					XCTAssert(QBETests.rasterEquals(raster, grid: [
						[1,2,3].map { Value.int($0) },
						[4,5,6].map { Value.int($0) },
						[7,8,9].map { Value.int($0) }
						]), "Raster invalid")

					callback()
				}
			}
		}

		// Test functioning of CSV stream with file that contains rows that have less columns then specified
		let url3 = Bundle(for: QBETests.self).url(forResource: "missing-columns", withExtension: "csv")
		let csv3 = CSVStream(url: url3!, fieldSeparator: ";".utf16.first!, hasHeaders: true, locale: locale)

		asyncTest { callback in
			StreamDataset(source: csv3).raster(job) { result in
				result.require { raster in
					XCTAssert(raster.rowCount == 3, "Need three rows")
					XCTAssert(QBETests.rasterEquals(raster, grid: [
						[Value.int(1), Value.int(2), Value.empty],
						[4,5,6].map { Value.int($0) },
						[7,8,9].map { Value.int($0) }
						]), "Raster invalid")

					callback()
				}
			}
		}

		// Test escapes in CSV
		let url4 = Bundle(for: QBETests.self).url(forResource: "escapes", withExtension: "csv")
		let csv4 = CSVStream(url: url4!, fieldSeparator: ";".utf16.first!, hasHeaders: true, locale: locale)

		asyncTest { callback in
			StreamDataset(source: csv4).raster(job) { result in
				result.require { raster in
					XCTAssert(raster.rowCount == 2, "Need two rows")
					XCTAssert(raster.columns == ["a;a","b","c"], "Wrong columns")
					XCTAssert(QBETests.rasterEquals(raster, grid: [
						[Value.int(1), Value.string("a;\nb"), Value.int(3)],
						[4,5,6].map { Value.int($0) }
					]), "Raster invalid")

					callback()
				}
			}
		}
	}
}
