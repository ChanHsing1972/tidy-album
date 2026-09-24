import XCTest

/// Requires the disposable Queue QA simulator populated by PendingDeletionTests.
/// Exercises real navigation and PhotoKit cancellation without deleting media.
final class PendingDeletionUITests: XCTestCase {
    @MainActor
    func testRestorePersistsAndSystemCancellationKeepsQueue() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-app.hasLaunchedBefore", "YES", "-settings.language", "english",
            "-settings.deletionMode", "appTrash", "-settings.cleaningGroupSize", "25"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Trash"].firstMatch.waitForExistence(timeout: 15))
        try tapVisible("Trash", in: app)
        if app.buttons["Restore"].firstMatch.waitForExistence(timeout: 2) {
            try tapVisible("More", in: app)
            try tapVisible("Restore All", in: app)
        }
        XCTAssertTrue(app.staticTexts["Trash is Empty"].waitForExistence(timeout: 3))
        try tapVisible("Close", in: app)
        let start = app.buttons["Start Cleaning"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let card = app.descendants(matching: .any)["tidyalbum.cleaning-card.current"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.swipeUp()
        try tapVisible("Trash", in: app)
        let restore = app.buttons["Restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        attachScreenshot("Queue before restore", app: app)
        restore.tap()
        XCTAssertTrue(app.staticTexts["Trash is Empty"].waitForExistence(timeout: 3))
        attachScreenshot("Queue after immediate restore", app: app)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Trash"].firstMatch.waitForExistence(timeout: 10))
        try tapVisible("Trash", in: app)
        XCTAssertTrue(app.staticTexts["Trash is Empty"].waitForExistence(timeout: 3))
        try tapVisible("Close", in: app)
        app.buttons["Start Cleaning"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.swipeUp()
        try tapVisible("Trash", in: app)
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        try tapVisible("More", in: app)
        try tapVisible("Delete All", in: app)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let systemAlert = springboard.alerts.firstMatch
        XCTAssertTrue(systemAlert.waitForExistence(timeout: 10))
        attachScreenshot("PhotoKit confirmation", app: springboard)
        let cancel = systemAlert.buttons.matching(NSPredicate(
            format: "label IN %@", ["Don't Allow", "Don’t Allow", "Cancel", "不允许", "取消"]
        )).firstMatch
        XCTAssertTrue(cancel.exists, systemAlert.debugDescription)
        cancel.tap()
        XCTAssertFalse(app.alerts["Delete Failed"].waitForExistence(timeout: 2))
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertTrue(restore.isEnabled)
        attachScreenshot("Queue preserved after system cancellation", app: app)
        restore.tap()
        XCTAssertTrue(app.staticTexts["Trash is Empty"].waitForExistence(timeout: 3))
    }

    @MainActor private func tapVisible(_ label: String, in app: XCUIApplication) throws {
        let button = try XCTUnwrap(app.buttons.matching(identifier: label)
            .allElementsBoundByIndex.first { $0.isHittable }, "No visible button: \(label)")
        button.tap()
    }

    @MainActor private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
