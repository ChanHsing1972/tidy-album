import Photos
import Testing
import UIKit
@testable import TidyAlbum

/// Run only on a disposable simulator with Photos access granted to the test host.
/// Real assets exercise PhotoManager/analytics; the fake never deletes Photos data.
@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct PendingDeletionTests {
    @Test func restorationCannotChangeAnInFlightDeletion() async throws {
        let fixture = try await QueueFixture()
        let asset = fixture.assets[0]
        fixture.manager.markForDeletion(asset, at: 0)
        let deletion = Task { await fixture.manager.emptyTrash() }
        await fixture.service.deletion.waitForRequest()

        fixture.manager.restoreFromTrash(asset)
        fixture.manager.restoreAllFromTrash()
        #expect(fixture.manager.trashBin.map(\.localIdentifier) == [asset.localIdentifier])
        #expect(fixture.persistedIDs == [asset.localIdentifier])
        #expect(fixture.manager.isDeleting)

        fixture.service.deletion.finish(.failure(NSError(domain: PHPhotosErrorDomain,
                                                         code: PHPhotosError.userCancelled.rawValue)))
        await deletion.value
        #expect(!fixture.manager.isDeleting)
        #expect(fixture.manager.deletionError == nil)
        #expect(fixture.manager.trashBin.count == 1)
        fixture.manager.restoreFromTrash(asset)
        #expect(fixture.manager.trashBin.isEmpty)
    }

    @Test func undoDoesNotConsumeHistoryWhileDeletionIsPending() async throws {
        let fixture = try await QueueFixture()
        fixture.manager.markForDeletion(fixture.assets[0], at: 0)
        let deletion = Task { await fixture.manager.emptyTrash() }
        await fixture.service.deletion.waitForRequest()
        #expect(!fixture.manager.canUndo)
        let blockedUndo = await fixture.manager.undoLastAction()
        #expect(blockedUndo == nil)
        #expect(fixture.manager.trashBin.count == 1)

        fixture.service.deletion.finish(.failure(QueueTestError.rejected))
        await deletion.value
        #expect(fixture.manager.deletionError != nil)
        #expect(fixture.manager.canUndo)
        let undo = await fixture.manager.undoLastAction()
        #expect(undo?.assetIdentifier == fixture.assets[0].localIdentifier)
        #expect(fixture.manager.trashBin.isEmpty)
    }

    @Test func restoreIsImmediateAndIdempotentBeforeDeleteAll() async throws {
        let fixture = try await QueueFixture()
        let first = fixture.assets[0], second = fixture.assets[1]
        fixture.manager.markForDeletion(first, at: 0)
        fixture.manager.markForDeletion(second, at: 1)
        fixture.manager.restoreFromTrash(first)
        let count = fixture.manager.filterCounts[.all]
        fixture.manager.restoreFromTrash(first)
        #expect(fixture.manager.filterCounts[.all] == count)
        let deletion = Task { await fixture.manager.emptyTrash() }
        await fixture.service.deletion.waitForRequest()
        #expect(fixture.service.deletedIDs == [[second.localIdentifier]])
        fixture.service.deletion.finish(.success(()))
        await deletion.value
        #expect(fixture.manager.trashBin.isEmpty)
        #expect(fixture.manager.analytics.statistics.cleanedCount == 1)
    }

    @Test func duplicateDeleteDoesNotSubmitTwiceOrConsumeNewItems() async throws {
        let fixture = try await QueueFixture()
        fixture.manager.markForDeletion(fixture.assets[0], at: 0)
        let deletion = Task { await fixture.manager.emptyTrash() }
        await fixture.service.deletion.waitForRequest()
        fixture.manager.markForDeletion(fixture.assets[1], at: 1)
        await fixture.manager.emptyTrash()
        #expect(fixture.service.deletedIDs.count == 1)
        fixture.service.deletion.finish(.success(()))
        await deletion.value
        #expect(fixture.persistedIDs == [fixture.assets[1].localIdentifier])
        #expect(fixture.manager.trashBin.map(\.localIdentifier) == fixture.persistedIDs)
        #expect(fixture.manager.analytics.statistics.cleanedCount == 1)
    }

    @Test func startupReadCannotOverwriteANewlyQueuedItem() async throws {
        let fixture = try await QueueFixture(persistFirstAsset: true)
        fixture.service.authorizationStatus = .authorized
        fixture.manager.checkPermission()
        await fixture.service.lookup.waitForRequest()
        fixture.manager.markForDeletion(fixture.assets[1], at: 0)
        fixture.service.lookup.finish([fixture.assets[0]])
        // A mutation during the query requires a fresh snapshot before publication.
        await fixture.service.lookup.waitForRequest()
        fixture.service.lookup.finish(fixture.assets)
        await fixture.waitForLibraryReady()
        #expect(Set(fixture.persistedIDs) == Set(fixture.assets.map(\.localIdentifier)))
        #expect(Set(fixture.manager.trashBin.map(\.localIdentifier)) == Set(fixture.persistedIDs))
    }

    @Test func reconciliationCannotResurrectRestoredItemsOrDropNewItems() async throws {
        let fixture = try await QueueFixture(persistFirstAsset: true)
        fixture.service.authorizationStatus = .authorized
        fixture.manager.checkPermission()
        await fixture.service.lookup.waitForRequest()
        fixture.service.lookup.finish([fixture.assets[0]])
        await fixture.waitForLibraryReady()

        let previousFetchCount = fixture.service.filterFetchCount
        fixture.manager.photoLibraryDidChange(PHChange())
        await fixture.service.lookup.waitForRequest()
        fixture.manager.restoreFromTrash(fixture.assets[0])
        fixture.manager.markForDeletion(fixture.assets[1], at: 0)
        fixture.service.lookup.finish([fixture.assets[0]])
        await fixture.service.lookup.waitForRequest()
        fixture.service.lookup.finish([fixture.assets[1]])
        await fixture.waitForLibraryReady(after: previousFetchCount)
        #expect(fixture.persistedIDs == [fixture.assets[1].localIdentifier])
        #expect(fixture.manager.trashBin.map(\.localIdentifier) == fixture.persistedIDs)
    }

    @Test func limitedAccessDoesNotEraseInaccessiblePersistedItems() async throws {
        let fixture = try await QueueFixture(persistFirstAsset: true)
        fixture.service.authorizationStatus = .limited
        fixture.manager.checkPermission()
        await fixture.service.lookup.waitForRequest()
        fixture.service.lookup.finish([])
        await fixture.waitForLibraryReady()
        fixture.manager.markForDeletion(fixture.assets[1], at: 0)
        #expect(Set(fixture.persistedIDs) == Set(fixture.assets.map(\.localIdentifier)))
        #expect(fixture.manager.trashBin.map(\.localIdentifier) == [fixture.assets[1].localIdentifier])

        let previousFetchCount = fixture.service.filterFetchCount
        fixture.service.authorizationStatus = .authorized
        fixture.manager.checkPermission()
        await fixture.service.lookup.waitForRequest()
        fixture.service.lookup.finish(fixture.assets)
        await fixture.waitForLibraryReady(after: previousFetchCount)
        #expect(Set(fixture.manager.trashBin.map(\.localIdentifier)) == Set(fixture.persistedIDs))
    }

    @Test func lateLookupCannotHideItemsDuringSystemConfirmation() async throws {
        let fixture = try await QueueFixture(persistFirstAsset: true)
        fixture.service.authorizationStatus = .authorized
        fixture.manager.checkPermission()
        await fixture.service.lookup.waitForRequest()
        fixture.service.lookup.finish([fixture.assets[0]])
        await fixture.waitForLibraryReady()

        let previousFetchCount = fixture.service.filterFetchCount
        fixture.manager.photoLibraryDidChange(PHChange())
        await fixture.service.lookup.waitForRequest()
        let deletion = Task { await fixture.manager.emptyTrash() }
        await fixture.service.deletion.waitForRequest()
        fixture.service.lookup.finish([])
        await fixture.waitForLibraryReady(after: previousFetchCount)
        #expect(fixture.manager.trashBin.map(\.localIdentifier) == [fixture.assets[0].localIdentifier])
        fixture.service.deletion.finish(.failure(QueueTestError.rejected))
        await deletion.value
        #expect(fixture.manager.trashBin.count == 1)
        #expect(fixture.manager.analytics.statistics.cleanedCount == 0)
    }

    @Test func newerLookupWinsWhenResponsesCompleteOutOfOrder() async throws {
        let fixture = try await QueueFixture(persistFirstAsset: true)
        fixture.service.authorizationStatus = .authorized
        fixture.manager.checkPermission()
        await fixture.service.lookup.waitForRequest()
        fixture.service.lookup.finish([fixture.assets[0]])
        await fixture.waitForLibraryReady()

        let older = Task { await fixture.manager.refreshLibraryState() }
        await fixture.service.lookup.waitForRequest()
        let newer = Task { await fixture.manager.refreshLibraryState() }
        await fixture.service.lookup.waitForRequest(count: 2)
        fixture.service.lookup.finish([fixture.assets[0]], at: 1)
        await newer.value
        fixture.service.lookup.finish([])
        await older.value
        #expect(fixture.manager.trashBin.map(\.localIdentifier) == [fixture.assets[0].localIdentifier])
        #expect(fixture.persistedIDs == [fixture.assets[0].localIdentifier])
    }

    @Test func revocationClearsDisplayAndUndoButPreservesPendingIntent() async throws {
        let fixture = try await QueueFixture()
        await fixture.waitForLibraryReady()
        fixture.manager.beginSession(with: fixture.assets)
        fixture.manager.markForDeletion(fixture.assets[0], at: 0)
        #expect(fixture.manager.canUndo)
        fixture.service.authorizationStatus = .denied
        fixture.manager.checkPermission()
        #expect(!fixture.manager.isAuthorized)
        #expect(fixture.manager.sessionAssets.isEmpty)
        #expect(fixture.manager.trashBin.isEmpty)
        #expect(fixture.manager.filterCounts.isEmpty)
        #expect(!fixture.manager.canUndo)
        #expect(!fixture.manager.hasNextGroup)
        #expect(fixture.manager.sessionGroupNumber == 0)
        #expect(fixture.persistedIDs == [fixture.assets[0].localIdentifier])
        // A gesture callback already queued by UIKit must not resurrect display state.
        fixture.manager.markForDeletion(fixture.assets[1], at: 1)
        fixture.manager.beginSession(with: fixture.assets)
        #expect(fixture.manager.sessionAssets.isEmpty)
        #expect(fixture.persistedIDs == [fixture.assets[0].localIdentifier])
        let restored = fixture.manager.restoreFromTrash(fixture.assets[0])
        #expect(!restored)
    }

    @Test func calendarReadFinishingAfterRevocationReturnsNoAssets() async throws {
        let fixture = try await QueueFixture()
        await fixture.waitForLibraryReady()
        fixture.service.gatesFilterReads = true
        let calendar = Task { await fixture.manager.fetchCalendarAssets() }
        await fixture.service.filterRead.waitForRequest()
        fixture.service.authorizationStatus = .denied
        fixture.manager.checkPermission()
        fixture.service.filterRead.finish(fixture.assets)
        #expect(await calendar.value.isEmpty)
    }

    @Test func cancelledCalendarReadDoesNotReturnAnOldSnapshot() async throws {
        let fixture = try await QueueFixture()
        await fixture.waitForLibraryReady()
        fixture.service.gatesFilterReads = true
        let calendar = Task { await fixture.manager.fetchCalendarAssets() }
        await fixture.service.filterRead.waitForRequest()
        calendar.cancel()
        fixture.service.filterRead.finish(fixture.assets)
        #expect(await calendar.value.isEmpty)
    }

    @Test func externalRemovalPrunesSessionAndUndoWithoutErasingPendingIntent() async throws {
        let fixture = try await QueueFixture()
        await fixture.waitForLibraryReady()
        fixture.manager.beginSession(with: fixture.assets)
        fixture.manager.markForDeletion(fixture.assets[0], at: 0)
        fixture.manager.markFavorite(fixture.assets[1], at: 0)
        let refresh = Task { await fixture.manager.refreshLibraryState() }
        await fixture.service.lookup.waitForRequest()
        fixture.service.lookup.finish([]) // Pending item is no longer accessible.
        await fixture.service.lookup.waitForRequest()
        fixture.service.lookup.finish([]) // Both session items were removed externally.
        await refresh.value
        #expect(fixture.manager.sessionAssets.isEmpty)
        #expect(fixture.manager.trashBin.isEmpty)
        #expect(!fixture.manager.canUndo)
        #expect(fixture.manager.sessionGroupTotalCount == 0)
        #expect(fixture.manager.sessionGroupReviewedCount == 0)
        #expect(fixture.persistedIDs == [fixture.assets[0].localIdentifier])
    }

    @Test func lateSessionLookupCannotOverwriteANewSession() async throws {
        let fixture = try await QueueFixture()
        await fixture.waitForLibraryReady()
        fixture.manager.beginSession(with: [fixture.assets[0]])
        let refresh = Task { await fixture.manager.refreshLibraryState() }
        await fixture.service.lookup.waitForRequest()
        fixture.manager.beginSession(with: [fixture.assets[1]])
        fixture.service.lookup.finish([])
        await refresh.value
        #expect(fixture.manager.sessionAssets.map(\.localIdentifier) == [fixture.assets[1].localIdentifier])
        #expect(fixture.manager.sessionGroupTotalCount == 1)
    }

    @Test func latestSessionResponseWinsWhenLookupsFinishOutOfOrder() async throws {
        let fixture = try await QueueFixture()
        await fixture.waitForLibraryReady()
        fixture.manager.beginSession(with: fixture.assets)
        let older = Task { await fixture.manager.refreshLibraryState() }
        await fixture.service.lookup.waitForRequest()
        let newer = Task { await fixture.manager.refreshLibraryState() }
        await fixture.service.lookup.waitForRequest(count: 2)
        fixture.service.lookup.finish([fixture.assets[1]], at: 1)
        await newer.value
        fixture.service.lookup.finish(fixture.assets)
        await older.value
        #expect(fixture.manager.sessionAssets.map(\.localIdentifier) == [fixture.assets[1].localIdentifier])
    }

    @Test func inaccessibleFutureGroupsCannotBeStarted() async throws {
        let fixture = try await QueueFixture()
        await fixture.waitForLibraryReady()
        fixture.manager.settings.cleaningGroupSize = .develop
        fixture.manager.beginSession(with: fixture.assets)
        let current = try #require(fixture.manager.sessionAssets.first)
        #expect(fixture.manager.hasNextGroup)
        let refresh = Task { await fixture.manager.refreshLibraryState() }
        await fixture.service.lookup.waitForRequest()
        fixture.service.lookup.finish([current])
        await refresh.value
        #expect(!fixture.manager.hasNextGroup)
        #expect(fixture.manager.sessionGroupCount == 1)
        let advanced = fixture.manager.loadNextGroup()
        #expect(!advanced)
        #expect(fixture.manager.sessionAssets.map(\.localIdentifier) == [current.localIdentifier])
    }

    @Test func deletionFailureAfterRevocationDoesNotRepopulateDisplay() async throws {
        let fixture = try await QueueFixture()
        await fixture.waitForLibraryReady()
        fixture.manager.markForDeletion(fixture.assets[0], at: 0)
        let deletion = Task { await fixture.manager.emptyTrash() }
        await fixture.service.deletion.waitForRequest()
        fixture.service.authorizationStatus = .denied
        fixture.manager.checkPermission()
        #expect(fixture.manager.isDeleting) // An already submitted system transaction is still pending.
        fixture.service.deletion.finish(.failure(QueueTestError.rejected))
        await deletion.value
        #expect(!fixture.manager.isDeleting)
        #expect(fixture.manager.deletionError == nil)
        #expect(fixture.manager.trashBin.isEmpty)
        #expect(fixture.manager.filterCounts.isEmpty)
        #expect(fixture.persistedIDs == [fixture.assets[0].localIdentifier])
    }

    @Test func lateSessionLookupCannotReopenAnEndedSession() async throws {
        let fixture = try await QueueFixture()
        await fixture.waitForLibraryReady()
        fixture.manager.beginSession(with: fixture.assets)
        let refresh = Task { await fixture.manager.refreshLibraryState() }
        await fixture.service.lookup.waitForRequest()
        fixture.manager.endSession()
        fixture.service.lookup.finish(fixture.assets)
        await refresh.value
        #expect(fixture.manager.sessionAssets.isEmpty)
        #expect(fixture.manager.sessionGroupNumber == 0)
        #expect(!fixture.manager.hasNextGroup)
    }

}

private enum QueueTestError: Error { case rejected, simulatorRequired, photosAccessRequired, missingAssets }

@MainActor private final class QueueFixture {
    static let queueKey = "photoManager.pendingDeletionIdentifiers.v1"
    let suiteName = "PendingDeletionTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let service = ControlledPhotoLibrary()
    let manager: PhotoManager
    let assets: [PHAsset]

    var persistedIDs: [String] { defaults.stringArray(forKey: Self.queueKey) ?? [] }

    init(persistFirstAsset: Bool = false) async throws {
        #if !targetEnvironment(simulator)
        throw QueueTestError.simulatorRequired
        #else
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            throw QueueTestError.photosAccessRequired
        }
        let data = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        var identifiers: [String] = []
        try await PHPhotoLibrary.shared().performChanges {
            for _ in 0..<2 {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "TidyAlbum-Queue-Test-\(UUID().uuidString).png"
                request.addResource(with: .photo, data: data, options: options)
                if let id = request.placeholderForCreatedAsset?.localIdentifier { identifiers.append(id) }
            }
        }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard result.count == 2 else { throw QueueTestError.missingAssets }
        assets = (0..<result.count).map { result.object(at: $0) }
        defaults = UserDefaults(suiteName: suiteName)!
        if persistFirstAsset { defaults.set([assets[0].localIdentifier], forKey: Self.queueKey) }
        if !persistFirstAsset { service.authorizationStatus = .authorized }
        manager = PhotoManager(photoService: service, settings: SettingsStore(defaults: defaults),
                               analytics: AnalyticsStore(defaults: defaults), defaults: defaults)
        #endif
    }

    deinit { defaults.removePersistentDomain(forName: suiteName) }

    func waitForLibraryReady(after count: Int = 0) async {
        await service.waitForFilterFetch(after: count)
    }
}

@MainActor private final class ResponseGate<Value> {
    private var continuations: [CheckedContinuation<Value, Never>] = []
    private var arrival: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    func request() async -> Value {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            if let arrival, continuations.count >= arrival.count {
                self.arrival = nil
                arrival.continuation.resume()
            }
        }
    }

    func waitForRequest(count: Int = 1) async {
        if continuations.count >= count { return }
        await withCheckedContinuation { arrival = (count, $0) }
    }

    func finish(_ value: Value, at index: Int = 0) {
        continuations.remove(at: index).resume(returning: value)
    }
}

@MainActor private final class ControlledPhotoLibrary: PhotoLibraryServiceProtocol {
    var authorizationStatus: PHAuthorizationStatus = .denied
    let lookup = ResponseGate<[PHAsset]>()
    let deletion = ResponseGate<Result<Void, Error>>()
    let filterRead = ResponseGate<[PHAsset]>()
    var gatesFilterReads = false
    var deletedIDs: [[String]] = []
    private(set) var filterFetchCount = 0
    private var filterArrival: CheckedContinuation<Void, Never>?

    func requestAuthorization() async -> PHAuthorizationStatus { authorizationStatus }
    func fetchAssets(filter: PhotoFilter) async -> [PHAsset] {
        filterFetchCount += 1
        filterArrival?.resume()
        filterArrival = nil
        if gatesFilterReads { return await filterRead.request() }
        return []
    }
    func waitForFilterFetch(after count: Int) async {
        if filterFetchCount > count { return }
        await withCheckedContinuation { filterArrival = $0 }
    }
    func fetchAssets(localIdentifiers: [String]) async -> [PHAsset] { await lookup.request() }
    func fetchUserAlbums() async -> [PHAssetCollection] { [] }
    func deleteAssets(_ assets: [PHAsset]) async throws {
        deletedIDs.append(assets.map(\.localIdentifier))
        try await deletion.request().get()
    }
    func setFavorite(_ isFavorite: Bool, for asset: PHAsset) async throws {}
    func add(_ asset: PHAsset, to album: PHAssetCollection) async throws {}
    func createAlbum(named title: String) async throws -> PHAssetCollection { throw QueueTestError.rejected }
    nonisolated func registerChangeObserver(_ observer: PHPhotoLibraryChangeObserver) {}
    nonisolated func unregisterChangeObserver(_ observer: PHPhotoLibraryChangeObserver) {}
}
