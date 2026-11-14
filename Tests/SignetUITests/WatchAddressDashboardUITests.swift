import XCTest

/// The dashboard path: with an account already there, through the ••• menu, after the
/// dashboard's refreshes and node lights have run.
final class WatchAddressDashboardUITests: XCTestCase {
    func testTypingFromTheDashboard() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appLockEnabled", "NO"]
        app.launch()
        if app.alerts.firstMatch.waitForExistence(timeout: 3) { app.alerts.firstMatch.buttons.firstMatch.tap() }
        if app.buttons["Watch an address"].waitForExistence(timeout: 3) {
            // Give the app an account first, so the dashboard shows.
            app.buttons["Watch an address"].tap()
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
            let name = app.textFields.element(boundBy: 1)
            name.tap(); name.typeText("Seed")
            app.navigationBars["Watch an address"].buttons["Add"].tap()
        }
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 10))
        sleep(5)
        app.buttons["More"].tap()
        app.buttons["Watch an address…"].tap()
        XCTAssertTrue(app.navigationBars["Watch an address"].waitForExistence(timeout: 5))
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("tz1")
        sleep(2)
        XCTAssertEqual(field.value as? String, "tz1")
    }
}
