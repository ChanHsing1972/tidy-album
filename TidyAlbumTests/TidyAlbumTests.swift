//
//  TidyAlbumTests.swift
//  TidyAlbumTests
//
//  Created by 尘心 on 2025/12/23.
//

import CoreGraphics
import CoreLocation
import Foundation
import Photos
import Testing
@testable import TidyAlbum

struct TidyAlbumTests {
    @Test @MainActor
    func settingsPersistAcrossStoreInstances() {
        let suiteName = "TidyAlbumTests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.language = .english
        settings.hapticsEnabled = false
        settings.autoPlayLivePhotos = false
        settings.deletionMode = .systemTrash
        settings.sortOrder = .random
        settings.excludesViewedInRandomMode = true
        settings.progressDisplayMode = .barOnly
        settings.cleaningGroupSize = .extraLarge
        settings.downwardSwipeAction = .addToAlbum

        let restored = SettingsStore(defaults: defaults)
        #expect(restored.language == .english)
        #expect(restored.hapticsEnabled == false)
        #expect(restored.autoPlayLivePhotos == false)
        #expect(restored.deletionMode == .systemTrash)
        #expect(restored.sortOrder == .random)
        #expect(restored.excludesViewedInRandomMode)
        #expect(restored.progressDisplayMode == .barOnly)
        #expect(restored.cleaningGroupSize == .extraLarge)
        #expect(restored.downwardSwipeAction == .addToAlbum)

        settings.sortOrder = .oldestFirst
        #expect(SettingsStore(defaults: defaults).sortOrder == .oldestFirst)
        settings.sortOrder = .largestFirst
        #expect(SettingsStore(defaults: defaults).sortOrder == .largestFirst)
    }

    @Test @MainActor
    func analyticsPersistAcrossStoreInstances() {
        let suiteName = "TidyAlbumTests.analytics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let analytics = AnalyticsStore(defaults: defaults)
        analytics.recordReview()
        analytics.recordReview()

        let restored = AnalyticsStore(defaults: defaults)
        #expect(restored.statistics.reviewedCount == 2)
        #expect(restored.statistics.cleanedCount == 0)
    }

    @Test @MainActor
    func analyticsResetClearsPersistedHistory() {
        let suiteName = "TidyAlbumTests.analyticsReset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let analytics = AnalyticsStore(defaults: defaults)
        analytics.recordReview()
        analytics.reset()

        let restored = AnalyticsStore(defaults: defaults)
        #expect(analytics.statistics.reviewedCount == 0)
        #expect(restored.statistics.reviewedCount == 0)
    }

    @Test
    func cleanupCategoriesClassifyEverySupportedMediaType() {
        #expect(CleanupCategory.classify(mediaType: .image, mediaSubtypes: .photoScreenshot, bytes: 1, resourceFilenames: ["image.png"]) == .screenshot)
        #expect(CleanupCategory.classify(mediaType: .image, mediaSubtypes: .photoLive, bytes: 1, resourceFilenames: ["image.heic"]) == .livePhoto)
        #expect(CleanupCategory.classify(mediaType: .image, mediaSubtypes: .photoPanorama, bytes: 1, resourceFilenames: ["image.jpg"]) == .panorama)
        #expect(CleanupCategory.classify(mediaType: .image, mediaSubtypes: .photoDepthEffect, bytes: 1, resourceFilenames: ["image.heic"]) == .portrait)
        #expect(CleanupCategory.classify(mediaType: .image, mediaSubtypes: [], bytes: 1, resourceFilenames: ["image.DNG"]) == .rawPhoto)
        #expect(CleanupCategory.classify(mediaType: .image, mediaSubtypes: [], bytes: 1, resourceFilenames: ["image.heic"]) == .photo)
        #expect(CleanupCategory.classify(mediaType: .video, mediaSubtypes: [], bytes: 99_999_999, resourceFilenames: ["clip.mov"]) == .video)
        #expect(CleanupCategory.classify(mediaType: .video, mediaSubtypes: [], bytes: 100_000_000, resourceFilenames: ["clip.mov"]) == .largeVideo)
    }

    @Test @MainActor
    func legacyCleanupStatisticsStillDecode() throws {
        let json = #"{"reviewedCount":1,"events":[{"id":"00000000-0000-0000-0000-000000000001","date":0,"mediaKind":"photo","category":"other","bytes":42}]}"#
        let decoded = try JSONDecoder().decode(CleanupStatistics.self, from: Data(json.utf8))

        #expect(decoded.reviewedCount == 1)
        #expect(decoded.events.first?.category == .other)
        #expect(decoded.reclaimedBytes == 42)
    }

    @Test @MainActor
    func fullDateUsesTheSelectedLanguageForWeekdays() {
        let suiteName = "TidyAlbumTests.dates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 10))!
        let settings = SettingsStore(defaults: defaults)

        settings.language = .simplifiedChinese
        #expect(settings.fullDate(friday).contains("星期五"))

        settings.language = .english
        #expect(settings.fullDate(friday).contains("Friday"))
    }

    @Test @MainActor
    func deletionTargetUsesTheFollowingPageFromTheRight() {
        let target = CleaningMotionGeometry.deletionTarget(currentIndex: 1, assetCount: 4)

        #expect(target == CleaningDeletionGeometry(pageIndex: 2, entryEdge: 1))
    }

    @Test @MainActor
    func deletionTargetUsesThePreviousPageFromTheLeftAtTheEnd() {
        let target = CleaningMotionGeometry.deletionTarget(currentIndex: 3, assetCount: 4)

        #expect(target == CleaningDeletionGeometry(pageIndex: 2, entryEdge: -1))
    }

    @Test @MainActor
    func deletingTheOnlyAssetPullsCompletionFromTheLeft() {
        let target = CleaningMotionGeometry.deletionTarget(currentIndex: 0, assetCount: 1)

        #expect(target == CleaningDeletionGeometry(pageIndex: 1, entryEdge: -1))
    }

    @Test @MainActor
    func deletionPullProgressTracksOnlyUpwardMotionAndClamps() {
        #expect(CleaningMotionGeometry.deletionProgress(verticalTranslation: 40, revealDistance: 200) == 0)
        #expect(CleaningMotionGeometry.deletionProgress(verticalTranslation: -50, revealDistance: 200) == 0.25)
        #expect(CleaningMotionGeometry.deletionProgress(verticalTranslation: -300, revealDistance: 200) == 1)
        #expect(CleaningMotionGeometry.incomingOffset(entryEdge: 1, pageWidth: 400, progress: 0.25) == 300)
        #expect(CleaningMotionGeometry.incomingOffset(entryEdge: -1, pageWidth: 400, progress: 1) == 0)
    }

    @Test @MainActor
    func verticalIntentCannotReverseDuringOneGesture() {
        #expect(CleaningMotionGeometry.lockedVerticalComponent(-120, intent: -1) == -120)
        #expect(CleaningMotionGeometry.lockedVerticalComponent(80, intent: -1) == 0)
        #expect(CleaningMotionGeometry.lockedVerticalComponent(120, intent: 1) == 120)
        #expect(CleaningMotionGeometry.lockedVerticalComponent(-80, intent: 1) == 0)
    }

    @Test @MainActor
    func inspectionPinchCannotReverseIntoTimelineDuringOneGesture() {
        let startedZoomed = CleaningMotionGeometry.resolvedPinchIntent(
            current: .undetermined,
            startingScale: 2,
            gestureScale: 1
        )
        let pinchedBack = CleaningMotionGeometry.resolvedPinchIntent(
            current: startedZoomed,
            startingScale: 2,
            gestureScale: 0.4
        )
        let timeline = CleaningMotionGeometry.resolvedPinchIntent(
            current: .undetermined,
            startingScale: 1,
            gestureScale: 0.8
        )

        #expect(startedZoomed == .inspection)
        #expect(pinchedBack == .inspection)
        #expect(timeline == .timeline)
    }

    @Test @MainActor
    func idlePagesKeepTheirExactPageSpacing() {
        let current = CleaningMotionGeometry.pageMotion(
            pageIndex: 2,
            currentPageIndex: 2,
            pageWidth: 411,
            axis: .undetermined,
            translation: .zero,
            isDeleting: false,
            deletionTarget: nil,
            deletionProgress: 0,
            actionThreshold: 92
        )
        let previous = CleaningMotionGeometry.pageMotion(
            pageIndex: 1,
            currentPageIndex: 2,
            pageWidth: 411,
            axis: .undetermined,
            translation: .zero,
            isDeleting: false,
            deletionTarget: nil,
            deletionProgress: 0,
            actionThreshold: 92
        )
        let next = CleaningMotionGeometry.pageMotion(
            pageIndex: 3,
            currentPageIndex: 2,
            pageWidth: 411,
            axis: .undetermined,
            translation: .zero,
            isDeleting: false,
            deletionTarget: nil,
            deletionProgress: 0,
            actionThreshold: 92
        )

        #expect(current.translation == .zero)
        #expect(previous.translation.x == -411)
        #expect(next.translation.x == 411)
    }

    @Test @MainActor
    func horizontalDragMovesEveryPageByTheFingerTranslation() {
        let translations = (1...3).map { pageIndex in
            CleaningMotionGeometry.pageMotion(
                pageIndex: pageIndex,
                currentPageIndex: 2,
                pageWidth: 411,
                axis: .horizontal,
                translation: CGPoint(x: -73, y: 120),
                isDeleting: false,
                deletionTarget: nil,
                deletionProgress: 0,
                actionThreshold: 92
            ).translation
        }

        #expect(translations.map(\.x) == [-484, -73, 338])
        #expect(translations.allSatisfy { $0.y == 0 })
    }

    @Test @MainActor
    func upwardDragResistsCurrentPageAndPullsOnlyDeletionTarget() {
        let target = CleaningDeletionGeometry(pageIndex: 2, entryEdge: 1)
        let current = CleaningMotionGeometry.pageMotion(
            pageIndex: 1,
            currentPageIndex: 1,
            pageWidth: 411,
            axis: .vertical,
            translation: CGPoint(x: 80, y: -142),
            isDeleting: false,
            deletionTarget: target,
            deletionProgress: 0.25,
            actionThreshold: 92
        )
        let incoming = CleaningMotionGeometry.pageMotion(
            pageIndex: 2,
            currentPageIndex: 1,
            pageWidth: 411,
            axis: .vertical,
            translation: CGPoint(x: 80, y: -142),
            isDeleting: false,
            deletionTarget: target,
            deletionProgress: 0.25,
            actionThreshold: 92
        )

        #expect(current.translation.x == 0)
        #expect(current.translation.y == -121)
        #expect(current.scale == 0.982)
        #expect(incoming.translation.x == 308.25)
        #expect(incoming.translation.y == 0)
        #expect(incoming.zPosition == 9)
    }

    @Test @MainActor
    func committedDeletionUsesUnresistedOffscreenEndpoint() {
        let motion = CleaningMotionGeometry.pageMotion(
            pageIndex: 1,
            currentPageIndex: 1,
            pageWidth: 411,
            axis: .vertical,
            translation: CGPoint(x: 0, y: -760),
            isDeleting: true,
            deletionTarget: CleaningDeletionGeometry(pageIndex: 2, entryEdge: 1),
            deletionProgress: 1,
            actionThreshold: 92
        )

        #expect(motion.translation.y == -760)
        #expect(motion.scale == 0.982)
    }

    @Test
    func mainlandWGS84CoordinateConvertsToGCJ02() {
        let converted = ChinaCoordinateTransform.gcj02Coordinate(
            fromWGS84: CLLocationCoordinate2D(latitude: 39.908823, longitude: 116.397470)
        )

        #expect(abs(converted.latitude - 39.9102265) < 0.00001)
        #expect(abs(converted.longitude - 116.4037136) < 0.00001)
    }

    @Test
    func coordinateOutsideMainlandRemainsUnchanged() {
        let tokyo = CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
        let converted = ChinaCoordinateTransform.gcj02Coordinate(fromWGS84: tokyo)

        #expect(converted.latitude == tokyo.latitude)
        #expect(converted.longitude == tokyo.longitude)
    }
}
