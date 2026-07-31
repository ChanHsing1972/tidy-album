import Combine
import Photos
import SwiftUI

// MARK: - Photo Manager

/// Owns PhotoKit state, bounded review groups, action history and the persisted
/// pending-deletion queue. All published mutations remain on the main actor.
@MainActor
final class PhotoManager: NSObject, ObservableObject {
    // MARK: Dependencies

    private let photoService: PhotoLibraryServiceProtocol
    private let defaults: UserDefaults
    let settings: SettingsStore
    let analytics: AnalyticsStore

    // MARK: Published State

    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var sessionAssets: [PHAsset] = []
    @Published private(set) var trashBin: [PHAsset] = []
    @Published private(set) var filterCounts: [PhotoFilter: Int] = [:]
    @Published private(set) var isAuthorized = false
    @Published private(set) var isLimited = false
    @Published private(set) var isLoading = false
    @Published private(set) var isDeleting = false
    @Published private(set) var deletionError: Error?
    @Published private(set) var loadedFilter: PhotoFilter?
    @Published private(set) var sessionGroupNumber = 0
    @Published private(set) var sessionGroupCount = 0
    @Published private(set) var sessionGroupReviewedCount = 0
    @Published private(set) var sessionGroupTotalCount = 0
    @Published var currentFilter: PhotoFilter = .all
    @Published private var favoriteStates: [String: Bool] = [:]

    // MARK: Private State

    private var history: [ReviewAction] = []
    private var reviewedIdentifiers: Set<String> = []
    private var groupReviewedIdentifiers: Set<String> = []
    private var currentGroupIdentifiers: Set<String> = []
    private var removedSessionIndices: [String: Int] = [:]
    private var sessionQueue: [PHAsset] = []
    private var sessionCursor = 0
    private var fetchRevision = 0
    private var overviewRevision = 0
    private var hasRestoredPendingQueue = false
    private var overviewRefreshTask: Task<Void, Never>?
    private let pendingDeletionKey = "photoManager.pendingDeletionIdentifiers.v1"

    // MARK: Derived State

    var canUndo: Bool { !history.isEmpty }
    var canBeginSession: Bool { loadedFilter == currentFilter && !assets.isEmpty && !isLoading }
    var hasNextGroup: Bool { sessionCursor < sessionQueue.count }
    var isCurrentGroupComplete: Bool {
        sessionGroupTotalCount > 0 && sessionGroupReviewedCount >= sessionGroupTotalCount
    }
    var pendingDeletionBytes: Int64 {
        trashBin.reduce(0) { $0 + estimatedBytes(for: $1) }
    }

    // MARK: Initialization

    init(
        photoService: PhotoLibraryServiceProtocol,
        settings: SettingsStore,
        analytics: AnalyticsStore,
        defaults: UserDefaults = .standard
    ) {
        self.photoService = photoService
        self.settings = settings
        self.analytics = analytics
        self.defaults = defaults
        super.init()
        photoService.registerChangeObserver(self)
        checkPermission()
    }

    deinit {
        overviewRefreshTask?.cancel()
        photoService.unregisterChangeObserver(self)
    }

    // MARK: Permission

    func checkPermission() {
        let status = photoService.authorizationStatus
        applyAuthorization(status)
        if status == .notDetermined {
            Task { applyAuthorization(await photoService.requestAuthorization()) }
        }
    }

    private func applyAuthorization(_ status: PHAuthorizationStatus) {
        isAuthorized = status == .authorized || status == .limited
        isLimited = status == .limited
        guard isAuthorized else {
            fetchRevision += 1
            overviewRevision += 1
            assets = []
            loadedFilter = nil
            isLoading = false
            return
        }
        Task {
            await restorePendingQueueIfNeeded()
            fetchPhotos()
            refreshLibraryOverview()
        }
    }

    // MARK: Fetching

    func setFilter(_ filter: PhotoFilter) {
        guard filter != currentFilter else { return }
        currentFilter = filter
        fetchPhotos()
    }

    func fetchPhotos() {
        guard isAuthorized else { return }
        isLoading = true
        loadedFilter = nil
        fetchRevision += 1
        let revision = fetchRevision
        let requestedFilter = currentFilter
        Task {
            let fetched = await photoService.fetchAssets(filter: requestedFilter)
            let trashIDs = Set(trashBin.map(\.localIdentifier))
            let available = fetched.filter { !trashIDs.contains($0.localIdentifier) }
            guard revision == fetchRevision, requestedFilter == currentFilter, isAuthorized else { return }
            assets = available
            filterCounts[requestedFilter] = available.count
            loadedFilter = requestedFilter
            isLoading = false
        }
    }

    func refreshLibraryOverview() {
        guard isAuthorized else { return }
        overviewRevision += 1
        let revision = overviewRevision
        Task {
            let trashIDs = Set(trashBin.map(\.localIdentifier))
            var counts: [PhotoFilter: Int] = [:]
            for filter in PhotoFilter.allCases {
                let fetched = await photoService.fetchAssets(filter: filter)
                guard revision == overviewRevision, isAuthorized else { return }
                counts[filter] = fetched.lazy.filter { !trashIDs.contains($0.localIdentifier) }.count
            }
            filterCounts = counts
        }
    }

    // MARK: Grouped Sessions

    func beginSession() {
        sessionQueue = settings.sortOrder == .random ? assets.shuffled() : assets
        sessionCursor = 0
        sessionGroupNumber = 0
        sessionGroupCount = max(
            1,
            Int(ceil(Double(sessionQueue.count) / Double(settings.cleaningGroupSize.rawValue)))
        )
        reviewedIdentifiers.removeAll()
        loadNextGroup()
    }

    @discardableResult
    func loadNextGroup() -> Bool {
        guard sessionCursor < sessionQueue.count else { return false }
        history.removeAll()
        removedSessionIndices.removeAll()
        groupReviewedIdentifiers.removeAll()
        let upperBound = min(sessionCursor + settings.cleaningGroupSize.rawValue, sessionQueue.count)
        sessionAssets = Array(sessionQueue[sessionCursor..<upperBound])
        sessionCursor = upperBound
        sessionGroupNumber += 1
        sessionGroupTotalCount = sessionAssets.count
        sessionGroupReviewedCount = 0
        currentGroupIdentifiers = Set(sessionAssets.map(\.localIdentifier))
        favoriteStates.merge(
            Dictionary(uniqueKeysWithValues: sessionAssets.map { ($0.localIdentifier, $0.isFavorite) })
        ) { current, _ in current }
        AssetImagePipeline.shared.preheat(
            Array(sessionAssets.prefix(8)),
            targetSize: CGSize(width: 1_200, height: 1_600)
        )
        return true
    }

    func recordViewed(_ asset: PHAsset) {
        let identifier = asset.localIdentifier
        guard currentGroupIdentifiers.contains(identifier) else { return }
        if groupReviewedIdentifiers.insert(identifier).inserted {
            sessionGroupReviewedCount = groupReviewedIdentifiers.count
        }
        if reviewedIdentifiers.insert(identifier).inserted {
            analytics.recordReview()
        }
    }

    func preheat(around index: Int) {
        let lower = max(0, index - 2)
        let upper = min(sessionAssets.count, index + 4)
        guard lower < upper else { return }
        AssetImagePipeline.shared.preheat(
            Array(sessionAssets[lower..<upper]),
            targetSize: CGSize(width: 1_200, height: 1_600)
        )
    }

    func endSession() {
        AssetImagePipeline.shared.stopCaching()
        sessionAssets.removeAll()
        sessionQueue.removeAll()
        history.removeAll()
        removedSessionIndices.removeAll()
    }

    // MARK: Review Actions

    func markForDeletion(_ asset: PHAsset, at index: Int) {
        guard !trashBin.contains(where: { $0.localIdentifier == asset.localIdentifier }) else { return }
        recordViewed(asset)
        let removalIndex = sessionAssets.firstIndex {
            $0.localIdentifier == asset.localIdentifier
        } ?? min(index, sessionAssets.count)
        removedSessionIndices[asset.localIdentifier] = removalIndex
        trashBin.append(asset)
        persistTrash()
        sessionAssets.removeAll { $0.localIdentifier == asset.localIdentifier }
        sessionGroupTotalCount = sessionAssets.count
        adjustFilterCounts(for: asset, delta: -1)
        scheduleLibraryOverviewRefresh()
        if settings.deletionMode == .appTrash {
            history.append(ReviewAction(id: UUID(), asset: asset, index: removalIndex, kind: .deletion))
        } else {
            Task { await deleteAssets([asset], restoreOnFailureAt: removalIndex) }
        }
    }

    func markFavorite(_ asset: PHAsset, at index: Int) {
        recordViewed(asset)
        let previous = isFavorite(asset)
        let target = !previous
        let actionID = UUID()
        favoriteStates[asset.localIdentifier] = target
        filterCounts[.favorites] = max(0, (filterCounts[.favorites] ?? 0) + (target ? 1 : -1))
        history.append(
            ReviewAction(
                id: actionID,
                asset: asset,
                index: index,
                kind: .favorite(previous: previous, target: target)
            )
        )
        Task {
            do {
                try await photoService.setFavorite(target, for: asset)
                let desired = favoriteStates[asset.localIdentifier] ?? target
                if desired != target { try? await photoService.setFavorite(desired, for: asset) }
            } catch {
                history.removeAll { $0.id == actionID }
                if favoriteStates[asset.localIdentifier] == target {
                    favoriteStates[asset.localIdentifier] = previous
                    filterCounts[.favorites] = max(
                        0,
                        (filterCounts[.favorites] ?? 0) + (previous ? 1 : -1)
                    )
                }
            }
        }
    }

    func isFavorite(_ asset: PHAsset) -> Bool {
        favoriteStates[asset.localIdentifier] ?? asset.isFavorite
    }

    func undoLastAction() async -> UndoResult? {
        guard let action = history.popLast() else { return nil }
        switch action.kind {
        case .deletion:
            trashBin.removeAll { $0.localIdentifier == action.asset.localIdentifier }
            persistTrash()
            insertIntoSession(action.asset, at: action.index)
            removedSessionIndices[action.asset.localIdentifier] = nil
            adjustFilterCounts(for: action.asset, delta: 1)
            scheduleLibraryOverviewRefresh()
        case let .favorite(previous, _):
            let current = isFavorite(action.asset)
            favoriteStates[action.asset.localIdentifier] = previous
            if current != previous {
                filterCounts[.favorites] = max(
                    0,
                    (filterCounts[.favorites] ?? 0) + (previous ? 1 : -1)
                )
            }
            try? await photoService.setFavorite(previous, for: action.asset)
        }
        return UndoResult(assetIdentifier: action.asset.localIdentifier)
    }

    // MARK: Pending Deletion

    func restoreFromTrash(_ asset: PHAsset) {
        trashBin.removeAll { $0.localIdentifier == asset.localIdentifier }
        persistTrash()
        history.removeAll { $0.asset.localIdentifier == asset.localIdentifier }
        if let index = removedSessionIndices[asset.localIdentifier] {
            insertIntoSession(asset, at: index)
            removedSessionIndices[asset.localIdentifier] = nil
        }
        adjustFilterCounts(for: asset, delta: 1)
        scheduleLibraryOverviewRefresh()
    }

    func restoreAllFromTrash() {
        let targets = trashBin
        targets.forEach(restoreFromTrash)
    }

    func emptyTrash() async {
        await deleteAssets(trashBin)
    }

    func deleteFromTrash(_ assets: [PHAsset]) async {
        await deleteAssets(assets)
    }

    private func deleteAssets(_ targets: [PHAsset], restoreOnFailureAt index: Int? = nil) async {
        guard !targets.isEmpty, !isDeleting else { return }
        deletionError = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(targets)
            targets.forEach { analytics.recordDeletion(asset: $0, bytes: estimatedBytes(for: $0)) }
            let identifiers = Set(targets.map(\.localIdentifier))
            trashBin.removeAll { identifiers.contains($0.localIdentifier) }
            persistTrash()
            history.removeAll { identifiers.contains($0.asset.localIdentifier) }
            identifiers.forEach { removedSessionIndices[$0] = nil }
            fetchPhotos()
            refreshLibraryOverview()
        } catch {
            deletionError = error
            if let index, let asset = targets.first {
                trashBin.removeAll { $0.localIdentifier == asset.localIdentifier }
                persistTrash()
                insertIntoSession(asset, at: index)
                removedSessionIndices[asset.localIdentifier] = nil
                adjustFilterCounts(for: asset, delta: 1)
            }
        }
    }

    func clearDeletionError() {
        deletionError = nil
    }

    func estimatedBytes(for asset: PHAsset) -> Int64 {
        if asset.mediaType == .video {
            return max(Int64(asset.duration * 500_000), 1_000_000)
        }
        let pixels = Int64(asset.pixelWidth) * Int64(asset.pixelHeight)
        return max(Int64(Double(pixels) * 0.32), 200_000)
    }

    private func insertIntoSession(_ asset: PHAsset, at index: Int) {
        guard currentGroupIdentifiers.contains(asset.localIdentifier),
              !sessionAssets.contains(where: { $0.localIdentifier == asset.localIdentifier }) else { return }
        sessionAssets.insert(asset, at: min(max(index, 0), sessionAssets.count))
        sessionGroupTotalCount = sessionAssets.count
        favoriteStates[asset.localIdentifier] = favoriteStates[asset.localIdentifier] ?? asset.isFavorite
    }

    private func adjustFilterCounts(for asset: PHAsset, delta: Int) {
        let matchingFilters = PhotoFilter.allCases.filter { filter in
            switch filter {
            case .all: true
            case .screenshots: asset.mediaSubtypes.contains(.photoScreenshot)
            case .videos: asset.mediaType == .video
            case .largeVideos:
                asset.mediaType == .video && (
                    asset.duration >= 60 || (asset.pixelWidth >= 3_840 && asset.pixelHeight >= 2_160)
                )
            case .livePhotos: asset.mediaSubtypes.contains(.photoLive)
            case .favorites: isFavorite(asset)
            case .selfies: currentFilter == .selfies
            }
        }
        for filter in matchingFilters {
            filterCounts[filter] = max(0, (filterCounts[filter] ?? 0) + delta)
        }
    }

    // MARK: Queue Persistence

    private func restorePendingQueueIfNeeded() async {
        guard !hasRestoredPendingQueue else { return }
        hasRestoredPendingQueue = true
        let identifiers = defaults.stringArray(forKey: pendingDeletionKey) ?? []
        guard !identifiers.isEmpty else { return }
        let fetched = await photoService.fetchAssets(localIdentifiers: identifiers)
        let byIdentifier = Dictionary(uniqueKeysWithValues: fetched.map { ($0.localIdentifier, $0) })
        trashBin = identifiers.compactMap { byIdentifier[$0] }
        persistTrash()
    }

    private func reconcilePendingQueue() async {
        guard hasRestoredPendingQueue, !trashBin.isEmpty else { return }
        let identifiers = trashBin.map(\.localIdentifier)
        let fetched = await photoService.fetchAssets(localIdentifiers: identifiers)
        let byIdentifier = Dictionary(uniqueKeysWithValues: fetched.map { ($0.localIdentifier, $0) })
        trashBin = identifiers.compactMap { byIdentifier[$0] }
        persistTrash()
    }

    private func persistTrash() {
        defaults.set(trashBin.map(\.localIdentifier), forKey: pendingDeletionKey)
    }

    private func scheduleLibraryOverviewRefresh() {
        overviewRefreshTask?.cancel()
        overviewRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.refreshLibraryOverview()
        }
    }
}

// MARK: - Review History

private struct ReviewAction {
    enum Kind {
        case deletion
        case favorite(previous: Bool, target: Bool)
    }

    let id: UUID
    let asset: PHAsset
    let index: Int
    let kind: Kind
}

struct UndoResult {
    let assetIdentifier: String
}

// MARK: - Photo Library Changes

extension PhotoManager: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            await reconcilePendingQueue()
            fetchPhotos()
            refreshLibraryOverview()
        }
    }
}
