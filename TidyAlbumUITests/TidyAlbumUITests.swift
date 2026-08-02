//
//  TidyAlbumUITests.swift
//  TidyAlbumUITests
//
//  Created by 尘心 on 2025/12/23.
//

import XCTest

final class TidyAlbumUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testCleaningStageStaysAlignedAcrossReviewGestures() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-settings.cleaningGroupSize", "25"]
        app.launch()

        dismissWelcomeIfNeeded(in: app)
        let startCleaning = firstExistingButton(
            in: app,
            labels: ["开始清理", "Start Cleaning"],
            timeout: 15
        )
        XCTAssertNotNil(startCleaning, "The photo library did not become ready for cleaning")
        startCleaning?.tap()

        var currentCard = try XCTUnwrap(waitForAlignedCurrentCard(in: app, timeout: 10))
        assertCurrentCardIsAligned(currentCard, in: app)
        attachScreenshot(named: "Cleaning - Resting", app: app)

        currentCard.swipeLeft()
        currentCard = try XCTUnwrap(waitForAlignedCurrentCard(in: app, timeout: 3))
        assertCurrentCardIsAligned(currentCard, in: app)
        attachScreenshot(named: "Cleaning - After Left Swipe", app: app)

        currentCard.swipeDown()
        currentCard = try XCTUnwrap(waitForAlignedCurrentCard(in: app, timeout: 3))
        assertCurrentCardIsAligned(currentCard, in: app)
        attachScreenshot(named: "Cleaning - After Favorite", app: app)

        currentCard.swipeUp()
        currentCard = try XCTUnwrap(waitForAlignedCurrentCard(in: app, timeout: 3))
        assertCurrentCardIsAligned(currentCard, in: app)
        attachScreenshot(named: "Cleaning - After Delete", app: app)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    private func dismissWelcomeIfNeeded(in app: XCUIApplication) {
        firstExistingButton(in: app, labels: ["继续", "Continue"], timeout: 5)?.tap()
    }

    @MainActor
    private func firstExistingButton(
        in app: XCUIApplication,
        labels: [String],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels {
                let button = app.buttons[label].firstMatch
                if button.exists { return button }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return nil
    }

    @MainActor
    private func assertCurrentCardIsAligned(
        _ card: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "tidyalbum.cleaning-card.current")
                .count,
            1,
            file: file,
            line: line
        )
        XCTAssertEqual(card.frame.minX, app.frame.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(card.frame.width, app.frame.width, accuracy: 1, file: file, line: line)
    }

    @MainActor
    private func waitForAlignedCurrentCard(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let cards = app.descendants(matching: .any)
            .matching(identifier: "tidyalbum.cleaning-card.current")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let card = cards.firstMatch
            if cards.count == 1,
               card.exists,
               abs(card.frame.minX - app.frame.minX) <= 1,
               abs(card.frame.width - app.frame.width) <= 1 {
                return card
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return nil
    }

    @MainActor
    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
