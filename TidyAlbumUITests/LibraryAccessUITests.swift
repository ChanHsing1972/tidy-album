import XCTest

/// Run the denied-access case with simctl Photos permission revoked before launch.
final class LibraryAccessUITests: XCTestCase {
    @MainActor
    func testCalendarExplainsDeniedAccess() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-app.hasLaunchedBefore", "YES", "-settings.language", "english"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 10))
        // Other suites require granted access. Keep their shared simulator untouched.
        guard app.staticTexts["Photo Access Required"].waitForExistence(timeout: 3) else {
            throw XCTSkip("Run this case on a simulator with Photos access revoked before launch.")
        }
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.staticTexts["Photo Access Required"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Settings"].isHittable)
        XCTAssertFalse(app.staticTexts["No Dated Photos"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Calendar - Permission recovery"
        image.lifetime = .keepAlways
        add(image)
        app.tabBars.buttons["Clean"].tap()
        XCTAssertTrue(app.staticTexts["Photo Access Required"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCalendarCanOpenAndCloseReviewWithAccess() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-app.hasLaunchedBefore", "YES", "-settings.language", "english"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Calendar"].tap()
        let month = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Items"))
            .matching(NSPredicate(format: "enabled == true")).firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 15))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Calendar - Loaded months"
        image.lifetime = .keepAlways
        add(image)
        month.tap()
        let card = app.descendants(matching: .any)["tidyalbum.cleaning-card.current"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let close = try XCTUnwrap(app.buttons.matching(identifier: "Close")
            .allElementsBoundByIndex.first { $0.isHittable })
        close.tap()
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        XCTAssertFalse(card.exists)
    }
}
