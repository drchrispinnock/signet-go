import XCTest

/// Drives the real app: menus, sheets and typing, which unit tests cannot reach.
final class WatchAddressUITests: XCTestCase {
    func testTypingIntoWatchAnAddress() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-showsDisclaimer", "NO"]
        app.launch()
        // From the welcome screen, or from the dashboard's ••• menu.
        if app.buttons["Watch an address"].waitForExistence(timeout: 5) {
            app.buttons["Watch an address"].tap()
        } else {
            app.buttons["More"].tap()
            XCTAssertTrue(app.buttons["Watch an address…"].waitForExistence(timeout: 5))
            app.buttons["Watch an address…"].tap()
        }
        XCTAssertTrue(app.navigationBars["Watch an address"].waitForExistence(timeout: 5))
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(field.value as? String, "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
    }
}
