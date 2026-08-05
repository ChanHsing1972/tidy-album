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

        for _ in 0..<3 {
            currentCard.swipeLeft()
            currentCard = try XCTUnwrap(waitForAlignedCurrentCard(in: app, timeout: 3))
            assertCurrentCardIsAligned(currentCard, in: app)
        }
        attachScreenshot(named: "Cleaning - Three Photos Past Delete", app: app)

        let undo = firstEnabledButton(in: app, labels: ["撤回", "Undo"], timeout: 3)
        XCTAssertNotNil(undo, "Undo did not become available after deleting an item")
        undo?.tap()
        currentCard = try XCTUnwrap(waitForAlignedCurrentCard(in: app, timeout: 3))
        assertCurrentCardIsAligned(currentCard, in: app)
        attachScreenshot(named: "Cleaning - After Undo", app: app)

        var finish: XCUIElement?
        for _ in 0..<25 {
            currentCard.swipeLeft()
            if let button = firstExistingButton(in: app, labels: ["完成", "Finish"], timeout: 0.15) {
                finish = button
                break
            }
            currentCard = try XCTUnwrap(waitForAlignedCurrentCard(in: app, timeout: 3))
        }
        XCTAssertNotNil(finish, "The completion page did not become active")
        XCTAssertTrue(
            waitForButtonsToDisappear(in: app, labels: ["详情", "Details"], timeout: 1),
            "The details island remained accessible after its fade-out"
        )
        XCTAssertNotNil(
            firstExistingButton(in: app, labels: ["分享", "Share"], timeout: 1),
            "The Share button was replaced or removed on the completion page"
        )
        attachScreenshot(named: "Cleaning - Completion", app: app)

        let stage = app.descendants(matching: .any)
            .matching(identifier: "tidyalbum.cleaning-stage")
            .firstMatch
        XCTAssertTrue(stage.exists)
        stage.swipeRight()
        currentCard = try XCTUnwrap(waitForAlignedCurrentCard(in: app, timeout: 3))
        assertCurrentCardIsAligned(currentCard, in: app)
        XCTAssertNotNil(
            firstExistingButton(in: app, labels: ["详情", "Details"], timeout: 1),
            "The details island did not fade back in after leaving completion"
        )
        attachScreenshot(named: "Cleaning - Back From Completion", app: app)
    }

    @MainActor
    func testCalendarSimilarityAndAlbumSwipeFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-settings.cleaningGroupSize", "25",
            "-settings.downwardSwipeAction", "addToAlbum"
        ]
        app.launch()

        dismissWelcomeIfNeeded(in: app)

        let similar = app.descendants(matching: .any)
            .matching(identifier: "tidyalbum.filter.similar")
            .firstMatch
        XCTAssertTrue(similar.waitForExistence(timeout: 15), "Similar Photos was not available on the Clean tab")

        let calendarTab = try XCTUnwrap(firstExistingButton(
            in: app,
            labels: ["日历", "Calendar"],
            timeout: 3
        ))
        calendarTab.tap()
        let calendar = app.descendants(matching: .any)
            .matching(identifier: "tidyalbum.calendar")
            .firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 10), "The Calendar tab did not load")
        attachScreenshot(named: "Calendar - Month Grid", app: app)

        let settingsTab = try XCTUnwrap(firstExistingButton(
            in: app,
            labels: ["设置", "Settings"],
            timeout: 3
        ))
        settingsTab.tap()
        let photoOrder = app.descendants(matching: .any)
            .matching(identifier: "tidyalbum.settings.photo-order")
            .firstMatch
        XCTAssertTrue(photoOrder.waitForExistence(timeout: 3), "Photo Order was not available in Settings")
        photoOrder.tap()
        XCTAssertNotNil(
            firstExistingButton(in: app, labels: ["按时间正序", "Oldest First"], timeout: 2),
            "Photo Order did not expose chronological ascending order"
        )
        let largestFirst = firstExistingButton(
            in: app,
            labels: ["按文件大小", "Largest First"],
            timeout: 2
        )
        XCTAssertNotNil(largestFirst, "Photo Order did not expose file-size order")
        largestFirst?.tap()
        let downwardAction = app.descendants(matching: .any)
            .matching(identifier: "tidyalbum.settings.downward-swipe-action")
            .firstMatch
        XCTAssertTrue(downwardAction.waitForExistence(timeout: 3), "Swipe Down Action was not available in Settings")
        downwardAction.tap()
        let addToAlbum = firstExistingButton(in: app, labels: ["加入相簿", "Add to Album"], timeout: 2)
        XCTAssertNotNil(addToAlbum, "The Swipe Down Action picker did not expose Add to Album")
        addToAlbum?.tap()

        let cleanTab = try XCTUnwrap(firstExistingButton(
            in: app,
            labels: ["清理", "Clean"],
            timeout: 3
        ))
        cleanTab.tap()
        let startCleaning = firstExistingButton(
            in: app,
            labels: ["开始清理", "Start Cleaning"],
            timeout: 15
        )
        XCTAssertNotNil(startCleaning, "The photo library did not become ready for cleaning")
        startCleaning?.tap()

        let currentCard = try XCTUnwrap(waitForAlignedCurrentCard(in: app, timeout: 10))
        currentCard.swipeDown()
        let albumPicker = app.descendants(matching: .any)
            .matching(identifier: "tidyalbum.album-picker")
            .firstMatch
        XCTAssertTrue(albumPicker.waitForExistence(timeout: 5), "Swipe down did not present the album picker")
        XCTAssertNotNil(
            firstExistingButton(in: app, labels: ["新建相簿", "New Album"], timeout: 2),
            "The album picker did not expose album creation"
        )
        attachScreenshot(named: "Cleaning - Album Picker", app: app)
    }

    @MainActor
    func testCleaningPinchGesturesAndDoubleTap() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-settings.cleaningGroupSize", "25"]
        app.launch()

        dismissWelcomeIfNeeded(in: app)
        let startCleaning = firstExistingButton(
            in: app,
            labels: ["开始清理", "Start Cleaning"],
            timeout: 15
        )
        XCTAssertNotNil(startCleaning)
        startCleaning?.tap()

        var currentCard = try XCTUnwrap(waitForAlignedCurrentCard(in: app, timeout: 10))
        currentCard.doubleTap()
        XCTAssertNotNil(
            firstEnabledButton(in: app, labels: ["撤回", "Undo"], timeout: 2),
            "Double tap did not toggle Favorite"
        )

        currentCard.pinch(withScale: 0.55, velocity: -1)
        let timeline = app.descendants(matching: .any)
            .matching(identifier: "tidyalbum.cleaning-timeline")
            .firstMatch
        XCTAssertTrue(timeline.waitForExistence(timeout: 5), "Pinching inward did not open the timeline")
        attachScreenshot(named: "Cleaning - Timeline", app: app)
        let close = firstExistingButton(in: app, labels: ["关闭", "Close"], timeout: 2)
        XCTAssertNotNil(close)
        close?.tap()

        currentCard = try XCTUnwrap(waitForAlignedCurrentCard(in: app, timeout: 5))
        currentCard.pinch(withScale: 1.8, velocity: 1)
        XCTAssertTrue(
            waitForButtonsToDisappear(in: app, labels: ["详情", "Details"], timeout: 2),
            "Pinching outward did not fade the surrounding UI"
        )
        currentCard.pinch(withScale: 0.5, velocity: -1)
        XCTAssertFalse(
            timeline.waitForExistence(timeout: 0.5),
            "Pinching a zoomed image back to fit incorrectly reopened the timeline"
        )
        XCTAssertNotNil(
            firstExistingButton(in: app, labels: ["详情", "Details"], timeout: 3),
            "Returning to the fitted scale did not restore the surrounding UI"
        )
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
    private func firstEnabledButton(
        in app: XCUIApplication,
        labels: [String],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels {
                let button = app.buttons[label].firstMatch
                if button.exists, button.isEnabled { return button }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return nil
    }

    @MainActor
    private func waitForButtonsToDisappear(
        in app: XCUIApplication,
        labels: [String],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if labels.allSatisfy({ !app.buttons[$0].firstMatch.exists }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return labels.allSatisfy { !app.buttons[$0].firstMatch.exists }
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
