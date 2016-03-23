import XCTest

class WarpUITests: XCTestCase {
        
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let app = XCUIApplication()
		app.launchArguments.append("-AppleLanguages")
		app.launchArguments.append("(en)")
		app.launch()

		let tourWindow = XCUIApplication().windows["Untitled"]
		tourWindow.buttons["Okay, show me!"].click()
		tourWindow.buttons["Skip tour"].click()
    }
    
    override func tearDown() {
        super.tearDown()
    }

    func testExample() {

    }
}
