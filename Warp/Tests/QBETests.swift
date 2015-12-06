import XCTest
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
}
