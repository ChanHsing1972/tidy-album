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

    @Published private(set) var libraryRevision = 0
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
    @Published private(set) var sessionSummary = CleaningSessionSummary()
    @Published private(set) var viewedAssetCount = 0
    @Published private(set) var similarityProgress: Double?
    @Published private(set) var similarityGroups: [SimilarPhotoGroup] = []
    @Published var currentFilter: PhotoFilter = .all
    @Published private var favoriteStates: [String: Bool] = [:]

    // MARK: Private State

    private var pendingFavoriteActions: [UUID: String] = [:]
    private var favoriteRevision = 0
    private var history: [ReviewAction] = []
    private var reviewedIdentifiers: Set<String> = []
    private var sessionDeletedIdentifiers: Set<String> = []
    private var groupReviewedIdentifiers: Set<String> = []
    private var currentGroupIdentifiers: Set<String> = []
    private var removedSessionIndices: [String: Int] = [:]
    private var sessionQueue: [PHAsset] = []
    private var sessionCursor = 0
    private var isSessionActive = false
    private var sessionRevision = 0
    private var sessionFetchRevision = 0
    private var authorizationRevision = 0
    private var lastAuthorization: PHAuthorizationStatus?
    private var libraryRefreshTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?
    private var overviewTask: Task<Void, Never>?
    private var fetchRevision = 0
    private var overviewRevision = 0
    // Identifiers own queue membership; trashBin is its currently accessible projection.
    // A missing fetch result can mean Limited access, not deletion of the user's intent.
    private var pendingDeletionIdentifiers: [String]
    private var pendingQueueRevision = 0
    private var pendingQueueFetchRevision = 0
    private var overviewRefreshTask: Task<Void, Never>?
    private var photoFetchTask: Task<Void, Never>?
    private var similarityScanTask: Task<Void, Never>?
    private var hasCompletedSimilarityScan = false
    private var persistedViewedIdentifiers: Set<String> = []
    private let pendingDeletionKey = "photoManager.pendingDeletionIdentifiers.v1"
    private let viewedIdentifiersKey = "photoManager.viewedIdentifiers.v1"

    // MARK: Derived State

    var calendarSnapshotID: PhotoLibrarySnapshotID {
        PhotoLibrarySnapshotID(library: libraryRevision, queue: pendingQueueRevision)
    }

    var canUndo: Bool {
        guard let action = history.last else { return false }
        if case .deletion = action.kind { return !isDeleting }
        return true
    }
    var canBeginSession: Bool { loadedFilter == currentFilter && cleaningCandidateCount > 0 && !isLoading }
    var cleaningCandidateCount: Int {
        guard settings.sortOrder == .random, settings.excludesViewedInRandomMode else { return assets.count }
        return assets.lazy.filter { !self.persistedViewedIdentifiers.contains($0.localIdentifier) }.count
    }
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
        var seen = Set<String>()
        pendingDeletionIdentifiers = (defaults.stringArray(forKey: pendingDeletionKey) ?? [])
            .filter { seen.insert($0).inserted }
        persistedViewedIdentifiers = Set(defaults.stringArray(forKey: viewedIdentifiersKey) ?? [])
        viewedAssetCount = persistedViewedIdentifiers.count
        super.init()
        photoService.registerChangeObserver(self)
        checkPermission()
    }

    deinit {
        libraryRefreshTask?.cancel()
        authorizationTask?.cancel()
        overviewTask?.cancel()
        overviewRefreshTask?.cancel()
        photoFetchTask?.cancel()
        similarityScanTask?.cancel()
        photoService.unregisterChangeObserver(self)
    }

    // MARK: Permission

    func checkPermission() {
        let status = photoService.authorizationStatus
        applyAuthorization(status)
        if status == .notDetermined, authorizationTask == nil {
            authorizationTask = Task { [weak self, photoService] in
                _ = await photoService.requestAuthorization()
                guard let self, !Task.isCancelled else { return }
                self.authorizationTask = nil
                // Read the current status, not a potentially superseded response.
                self.applyAuthorization(photoService.authorizationStatus)
            }
        }
    }

    private func applyAuthorization(_ status: PHAuthorizationStatus) {
        if lastAuthorization != status {
            authorizationRevision += 1
            lastAuthorization = status
        }
        isAuthorized = status == .authorized || status == .limited
        isLimited = status == .limited
        libraryRevision += 1
        fetchRevision += 1
        overviewRevision += 1
        pendingQueueFetchRevision += 1
        libraryRefreshTask?.cancel()
        photoFetchTask?.cancel()
        overviewTask?.cancel()
        overviewRefreshTask?.cancel()
        invalidateSimilarityScan()
        guard isAuthorized else {
            assets = []
            trashBin = []
            filterCounts = [:]
            similarityGroups = []
            favoriteStates = [:]
            loadedFilter = nil
            isLoading = false
            deletionError = nil
            endSession()
            reviewedIdentifiers.removeAll()
            sessionDeletedIdentifiers.removeAll()
            sessionSummary = CleaningSessionSummary()
            AssetImagePipeline.shared.invalidate()
            return
        }
        libraryRefreshTask = Task { [weak self] in
            await self?.refreshLibraryState()
        }
    }

    /// Reconciles accessible projections without changing persisted queue membership.
    /// Session and library revisions protect against navigation and permission changes
    /// while PhotoKit is responding. Kept async so callers can await a complete refresh.
    func refreshLibraryState() async {
        let revision = libraryRevision
        await reconcilePendingQueue()
        guard !Task.isCancelled, isAuthorized, revision == libraryRevision else { return }
        await reconcileSession(libraryRevision: revision)
        guard !Task.isCancelled, isAuthorized, revision == libraryRevision else { return }
        fetchPhotos()
        refreshLibraryOverview()
    }

    // MARK: Fetching

    func setFilter(_ filter: PhotoFilter) {
        guard filter != currentFilter else { return }
        currentFilter = filter
        if filter == .similar {
            assets = []
            loadedFilter = nil
        } else {
            similarityProgress = nil
        }
        fetchPhotos()
    }

    func fetchPhotos() {
        guard isAuthorized else { return }
        if currentFilter == .similar {
            prepareSimilarityScan()
            return
        }
        isLoading = true
        loadedFilter = nil
        fetchRevision += 1
        let revision = fetchRevision
        let requestedFilter = currentFilter
        photoFetchTask?.cancel()
        photoFetchTask = Task { [weak self] in
            guard let self else { return }
            let source = await self.photoService.fetchAssets(filter: requestedFilter)
            guard !Task.isCancelled else { return }
            let fetched = source
            guard !Task.isCancelled else { return }
            let trashIDs = Set(self.pendingDeletionIdentifiers)
            let available = fetched.filter { !trashIDs.contains($0.localIdentifier) }
            guard revision == self.fetchRevision,
                  requestedFilter == self.currentFilter,
                  self.isAuthorized else { return }
            self.assets = available
            self.filterCounts[requestedFilter] = available.count
            self.loadedFilter = requestedFilter
            self.isLoading = false
        }
    }

    /// Starts the on-device scan as soon as the library is available. The
    /// result is grouped and cached, so opening the Similar Photos card never
    /// turns into a second blocking scan.
    func prepareSimilarityScan() {
        guard isAuthorized,
              !hasCompletedSimilarityScan,
              similarityScanTask == nil else {
            if currentFilter == .similar, hasCompletedSimilarityScan {
                applySimilarityGroupsToCurrentFilter()
            }
            return
        }
        isLoading = currentFilter == .similar
        if currentFilter == .similar { loadedFilter = nil }
        similarityProgress = 0
        let revision = libraryRevision
        similarityScanTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let source = await self.photoService.fetchAssets(filter: .similar)
            guard !Task.isCancelled else { return }
            let groups = await LocalSimilarityService.shared.similarGroups(in: source) { progress in
                guard !Task.isCancelled, self.isAuthorized, revision == self.libraryRevision else { return }
                self.similarityProgress = progress
            }
            guard !Task.isCancelled else { return }
            guard self.isAuthorized, revision == self.libraryRevision else { return }
            self.similarityGroups = groups
            self.hasCompletedSimilarityScan = true
            self.similarityProgress = nil
            self.filterCounts[.similar] = groups.reduce(0) { $0 + $1.assets.count }
            if self.currentFilter == .similar {
                self.applySimilarityGroupsToCurrentFilter()
            }
            self.similarityScanTask = nil
        }
    }

    func refreshSimilarityScan() {
        invalidateSimilarityScan()
        prepareSimilarityScan()
    }

    func pauseSimilarityScan() {
        guard !hasCompletedSimilarityScan else { return }
        similarityScanTask?.cancel()
        similarityScanTask = nil
        similarityProgress = nil
        if currentFilter == .similar {
            isLoading = false
        }
    }

    private func applySimilarityGroupsToCurrentFilter() {
        guard currentFilter == .similar else { return }
        let trashIDs = Set(pendingDeletionIdentifiers)
        assets = similarityGroups
            .map { group in group.assets.filter { !trashIDs.contains($0.localIdentifier) } }
            .filter { $0.count > 1 }
            .flatMap { $0 }
        filterCounts[.similar] = assets.count
        loadedFilter = .similar
        isLoading = false
    }

    private func invalidateSimilarityScan() {
        similarityScanTask?.cancel()
        similarityScanTask = nil
        similarityProgress = nil
        hasCompletedSimilarityScan = false
    }

    func refreshLibraryOverview() {
        guard isAuthorized else { return }
        overviewRevision += 1
        let revision = overviewRevision
        overviewTask?.cancel()
        overviewTask = Task {
            let trashIDs = Set(pendingDeletionIdentifiers)
            var counts: [PhotoFilter: Int] = [:]
            for filter in PhotoFilter.allCases where filter != .similar {
                let fetched = await photoService.fetchAssets(filter: filter)
                guard !Task.isCancelled, revision == overviewRevision, isAuthorized else { return }
                counts[filter] = fetched.lazy.filter { !trashIDs.contains($0.localIdentifier) }.count
            }
            if let similarCount = filterCounts[.similar] {
                counts[.similar] = similarCount
            }
            filterCounts = counts
        }
    }

    // MARK: Grouped Sessions

    func beginSession() {
        pauseSimilarityScan()
        let trashIDs = Set(pendingDeletionIdentifiers)
        var available = assets.filter { !trashIDs.contains($0.localIdentifier) }
        if settings.sortOrder == .random, settings.excludesViewedInRandomMode {
            available.removeAll { persistedViewedIdentifiers.contains($0.localIdentifier) }
        }
        beginSession(with: available)
    }

    func beginSession(with requestedAssets: [PHAsset]) {
        guard isAuthorized else { return }
        sessionRevision += 1
        pauseSimilarityScan()
        let trashIDs = Set(pendingDeletionIdentifiers)
        let available = orderedForCleaning(
            requestedAssets.filter { !trashIDs.contains($0.localIdentifier) }
        )
        sessionQueue = available
        sessionCursor = 0
        isSessionActive = true
        sessionGroupNumber = 0
        sessionGroupCount = max(
            1,
            Int(ceil(Double(sessionQueue.count) / Double(settings.cleaningGroupSize.rawValue)))
        )
        reviewedIdentifiers.removeAll()
        sessionDeletedIdentifiers.removeAll()
        sessionSummary = CleaningSessionSummary()
        loadNextGroup()
    }

    func beginSession(around anchor: PHAsset, from requestedAssets: [PHAsset]) {
        let trashIDs = Set(pendingDeletionIdentifiers)
        let chronological = requestedAssets
            .filter { !trashIDs.contains($0.localIdentifier) }
            .sorted {
                ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
            }
        guard let anchorIndex = chronological.firstIndex(where: {
            $0.localIdentifier == anchor.localIdentifier
        }) else {
            beginSession(with: [anchor])
            return
        }
        let count = min(settings.cleaningGroupSize.rawValue, chronological.count)
        let idealLowerBound = anchorIndex - count / 2
        let lowerBound = min(max(idealLowerBound, 0), chronological.count - count)
        beginSession(with: Array(chronological[lowerBound..<(lowerBound + count)]))
    }

    private func orderedForCleaning(_ candidates: [PHAsset]) -> [PHAsset] {
        switch settings.sortOrder {
        case .newestFirst:
            return candidates.sorted {
                ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
            }
        case .oldestFirst:
            return candidates.sorted {
                ($0.creationDate ?? .distantFuture) < ($1.creationDate ?? .distantFuture)
            }
        case .largestFirst:
            return candidates.sorted { lhs, rhs in
                let lhsBytes = estimatedBytes(for: lhs)
                let rhsBytes = estimatedBytes(for: rhs)
                if lhsBytes != rhsBytes { return lhsBytes > rhsBytes }
                return (lhs.creationDate ?? .distantPast) > (rhs.creationDate ?? .distantPast)
            }
        case .random:
            return candidates.shuffled()
        }
    }

    @discardableResult
    func loadNextGroup() -> Bool {
        guard isAuthorized, sessionCursor < sessionQueue.count else { return false }
        sessionRevision += 1
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
        if persistedViewedIdentifiers.insert(identifier).inserted {
            viewedAssetCount = persistedViewedIdentifiers.count
            persistViewedIdentifiers()
        }
        if groupReviewedIdentifiers.insert(identifier).inserted {
            sessionGroupReviewedCount = groupReviewedIdentifiers.count
        }
        if reviewedIdentifiers.insert(identifier).inserted {
            analytics.recordReview()
            sessionSummary.reviewedCount += 1
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

    func fetchCalendarAssets() async -> [PHAsset] {
        guard isAuthorized, !Task.isCancelled else { return [] }
        let revision = libraryRevision
        let fetched = await photoService.fetchAssets(filter: .all)
        guard !Task.isCancelled, isAuthorized, revision == libraryRevision else { return [] }
        let trashIDs = Set(pendingDeletionIdentifiers)
        return fetched.filter { !trashIDs.contains($0.localIdentifier) }
    }

    func fetchUserAlbums() async -> [PHAssetCollection] {
        await photoService.fetchUserAlbums()
    }

    func addToAlbum(_ asset: PHAsset, album: PHAssetCollection) async throws {
        try await photoService.add(asset, to: album)
    }

    func createAlbum(named title: String, adding asset: PHAsset) async throws {
        let album = try await photoService.createAlbum(named: title)
        try await photoService.add(asset, to: album)
    }

    func endSession() {
        sessionRevision += 1
        pauseSimilarityScan()
        isSessionActive = false
        AssetImagePipeline.shared.stopCaching()
        sessionAssets.removeAll()
        sessionQueue.removeAll()
        sessionCursor = 0
        history.removeAll()
        removedSessionIndices.removeAll()
        currentGroupIdentifiers.removeAll()
        groupReviewedIdentifiers.removeAll()
        sessionGroupNumber = 0
        sessionGroupCount = 0
        sessionGroupReviewedCount = 0
        sessionGroupTotalCount = 0
    }

    private func reconcileSession(libraryRevision revision: Int) async {
        guard isSessionActive else { return }
        let session = sessionRevision
        sessionFetchRevision += 1
        let request = sessionFetchRevision
        let favorites = favoriteRevision
        let identifiers = sessionQueue.map(\.localIdentifier)
        let fetched = await photoService.fetchAssets(localIdentifiers: identifiers)
        guard !Task.isCancelled, isAuthorized, revision == libraryRevision,
              session == sessionRevision, request == sessionFetchRevision, isSessionActive else { return }
        let accessible = Dictionary(fetched.map { ($0.localIdentifier, $0) },
                                    uniquingKeysWith: { _, latest in latest })
        let availableIDs = Set(accessible.keys)
        let pendingIDs = Set(pendingDeletionIdentifiers)
        // Preserve review order and the boundary between visited and future groups.
        let previous = sessionQueue.prefix(sessionCursor).compactMap { accessible[$0.localIdentifier] }
        let remaining = sessionQueue.dropFirst(sessionCursor).compactMap { asset -> PHAsset? in
            guard !pendingIDs.contains(asset.localIdentifier) else { return nil }
            return accessible[asset.localIdentifier]
        }
        sessionQueue = previous + remaining
        sessionCursor = previous.count
        sessionAssets = sessionAssets.compactMap { accessible[$0.localIdentifier] }
        currentGroupIdentifiers.formIntersection(availableIDs)
        groupReviewedIdentifiers.formIntersection(currentGroupIdentifiers)
        sessionGroupReviewedCount = groupReviewedIdentifiers.count
        sessionGroupTotalCount = sessionAssets.count
        sessionGroupCount = sessionGroupNumber + Int(ceil(
            Double(remaining.count) / Double(settings.cleaningGroupSize.rawValue)
        ))
        removedSessionIndices = removedSessionIndices.filter { availableIDs.contains($0.key) }
        history = history.compactMap { action in
            guard let asset = accessible[action.asset.localIdentifier] else { return nil }
            return ReviewAction(id: action.id, asset: asset, index: action.index, kind: action.kind)
        }
        favoriteStates = favoriteStates.filter { availableIDs.contains($0.key) }
        for asset in fetched where favorites == favoriteRevision && !pendingFavoriteActions.values.contains(asset.localIdentifier) {
            favoriteStates[asset.localIdentifier] = asset.isFavorite
        }
        AssetImagePipeline.shared.stopCaching()
    }

    func clearViewedHistory() {
        persistedViewedIdentifiers.removeAll()
        viewedAssetCount = 0
        defaults.removeObject(forKey: viewedIdentifiersKey)
    }

    // MARK: Review Actions

    func queueSimilarPhotosForDeletion(_ targets: [PHAsset]) {
        guard isAuthorized else { return }
        let trashIDs = Set(pendingDeletionIdentifiers)
        let uniqueTargets = Dictionary(
            uniqueKeysWithValues: targets.map { ($0.localIdentifier, $0) }
        ).values.filter { !trashIDs.contains($0.localIdentifier) }
        guard !uniqueTargets.isEmpty else { return }

        switch settings.deletionMode {
        case .appTrash:
            removeSimilarAssetsFromResults(uniqueTargets)
            appendToPendingQueue(Array(uniqueTargets))
            for asset in uniqueTargets {
                adjustFilterCounts(for: asset, delta: -1)
            }
            scheduleLibraryOverviewRefresh()
        case .systemTrash:
            Task { await deleteSimilarAssets(Array(uniqueTargets)) }
        }
    }

    private func removeSimilarAssetsFromResults(_ targets: [PHAsset]) {
        let identifiers = Set(targets.map(\.localIdentifier))
        similarityGroups = similarityGroups.compactMap { group in
            let remaining = group.assets.filter { !identifiers.contains($0.localIdentifier) }
            return remaining.count > 1 ? SimilarPhotoGroup(assets: remaining) : nil
        }
        assets.removeAll { identifiers.contains($0.localIdentifier) }
        filterCounts[.similar] = similarityGroups.reduce(0) { $0 + $1.assets.count }
    }

    private func deleteSimilarAssets(_ targets: [PHAsset]) async {
        guard isAuthorized, !targets.isEmpty, !isDeleting else { return }
        deletionError = nil
        isDeleting = true
        let authorization = authorizationRevision
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(targets)
            targets.forEach { analytics.recordDeletion(asset: $0, bytes: estimatedBytes(for: $0)) }
            removeSimilarAssetsFromResults(targets)
            fetchPhotos()
            refreshLibraryOverview()
        } catch {
            guard isAuthorized, authorization == authorizationRevision else { return }
            deletionError = isDeletionCancellation(error) ? nil : error
        }
    }

    func markForDeletion(_ asset: PHAsset, at index: Int) {
        guard isAuthorized, !pendingDeletionIdentifiers.contains(asset.localIdentifier) else { return }
        recordViewed(asset)
        let removalIndex = sessionAssets.firstIndex {
            $0.localIdentifier == asset.localIdentifier
        } ?? min(index, sessionAssets.count)
        removedSessionIndices[asset.localIdentifier] = removalIndex
        if sessionDeletedIdentifiers.insert(asset.localIdentifier).inserted {
            sessionSummary.markedForDeletionCount += 1
            sessionSummary.estimatedReclaimBytes += estimatedBytes(for: asset)
        }
        appendToPendingQueue([asset])
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
        guard isAuthorized else { return }
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
        let authorization = authorizationRevision
        let session = sessionRevision
        favoriteRevision += 1
        pendingFavoriteActions[actionID] = asset.localIdentifier
        Task {
            defer { pendingFavoriteActions[actionID] = nil }
            do {
                try await photoService.setFavorite(target, for: asset)
                guard isAuthorized, authorization == authorizationRevision,
                      session == sessionRevision, currentGroupIdentifiers.contains(asset.localIdentifier) else { return }
                let desired = favoriteStates[asset.localIdentifier] ?? target
                if desired != target { try? await photoService.setFavorite(desired, for: asset) }
            } catch {
                guard isAuthorized, authorization == authorizationRevision,
                      session == sessionRevision, currentGroupIdentifiers.contains(asset.localIdentifier) else { return }
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
        guard isAuthorized, canUndo, let action = history.popLast() else { return nil }
        let restoresDeletedAsset: Bool
        switch action.kind {
        case .deletion:
            restoresDeletedAsset = true
            removeFromPendingQueue([action.asset.localIdentifier])
            removeFromSessionDeletionSummary(action.asset)
            insertIntoSession(action.asset, at: action.index)
            removedSessionIndices[action.asset.localIdentifier] = nil
            adjustFilterCounts(for: action.asset, delta: 1)
            scheduleLibraryOverviewRefresh()
        case let .favorite(previous, _):
            restoresDeletedAsset = false
            favoriteRevision += 1
            let current = isFavorite(action.asset)
            favoriteStates[action.asset.localIdentifier] = previous
            if current != previous {
                filterCounts[.favorites] = max(
                    0,
                    (filterCounts[.favorites] ?? 0) + (previous ? 1 : -1)
                )
            }
            Task { [photoService] in
                try? await photoService.setFavorite(previous, for: action.asset)
            }
        }
        return UndoResult(
            assetIdentifier: action.asset.localIdentifier,
            restoresDeletedAsset: restoresDeletedAsset
        )
    }

    // MARK: Pending Deletion

    @discardableResult
    func restoreFromTrash(_ asset: PHAsset) -> Bool {
        // Once handed to PhotoKit, a local restore cannot cancel the system transaction.
        guard isAuthorized, !isDeleting, pendingDeletionIdentifiers.contains(asset.localIdentifier) else { return false }
        removeFromPendingQueue([asset.localIdentifier])
        removeFromSessionDeletionSummary(asset)
        history.removeAll { $0.asset.localIdentifier == asset.localIdentifier }
        if let index = removedSessionIndices[asset.localIdentifier] {
            insertIntoSession(asset, at: index)
            removedSessionIndices[asset.localIdentifier] = nil
        }
        adjustFilterCounts(for: asset, delta: 1)
        scheduleLibraryOverviewRefresh()
        return true
    }

    func restoreAllFromTrash() {
        guard !isDeleting else { return }
        let targets = trashBin
        targets.forEach { restoreFromTrash($0) }
    }

    func emptyTrash() async {
        await deleteAssets(trashBin)
    }

    func deleteFromTrash(_ assets: [PHAsset]) async {
        await deleteAssets(assets)
    }

    private func deleteAssets(_ requestedTargets: [PHAsset], restoreOnFailureAt index: Int? = nil) async {
        guard isAuthorized, !isDeleting else { return }
        // Revalidate when the task starts: a synchronous restore may have already won.
        let pendingIDs = Set(pendingDeletionIdentifiers)
        var seen = Set<String>()
        let targets = requestedTargets.filter {
            pendingIDs.contains($0.localIdentifier) && seen.insert($0.localIdentifier).inserted
        }
        guard !targets.isEmpty else { return }
        deletionError = nil
        isDeleting = true
        let authorization = authorizationRevision
        let session = sessionRevision
        pendingQueueRevision += 1
        defer {
            pendingQueueRevision += 1
            isDeleting = false
        }
        do {
            try await photoService.deleteAssets(targets)
            targets.forEach { analytics.recordDeletion(asset: $0, bytes: estimatedBytes(for: $0)) }
            let identifiers = Set(targets.map(\.localIdentifier))
            removeFromPendingQueue(identifiers)
            history.removeAll { identifiers.contains($0.asset.localIdentifier) }
            identifiers.forEach { removedSessionIndices[$0] = nil }
            fetchPhotos()
            refreshLibraryOverview()
        } catch {
            guard isAuthorized, authorization == authorizationRevision else { return }
            deletionError = isDeletionCancellation(error) ? nil : error
            if let index, let asset = targets.first, session == sessionRevision {
                removeFromPendingQueue([asset.localIdentifier])
                insertIntoSession(asset, at: index)
                removedSessionIndices[asset.localIdentifier] = nil
                removeFromSessionDeletionSummary(asset)
                adjustFilterCounts(for: asset, delta: 1)
            }
        }
    }

    func clearDeletionError() {
        deletionError = nil
    }

    private func isDeletionCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == PHPhotosErrorDomain && error.code == PHPhotosError.userCancelled.rawValue
    }

    func estimatedBytes(for asset: PHAsset) -> Int64 {
        if asset.mediaType == .video {
            return max(Int64(asset.duration * 500_000), 1_000_000)
        }
        let pixels = Int64(asset.pixelWidth) * Int64(asset.pixelHeight)
        return max(Int64(Double(pixels) * 0.32), 200_000)
    }

    private func insertIntoSession(_ asset: PHAsset, at index: Int) {
        guard isSessionActive,
              currentGroupIdentifiers.contains(asset.localIdentifier),
              !sessionAssets.contains(where: { $0.localIdentifier == asset.localIdentifier }) else { return }
        sessionAssets.insert(asset, at: min(max(index, 0), sessionAssets.count))
        sessionGroupTotalCount = sessionAssets.count
        favoriteStates[asset.localIdentifier] = favoriteStates[asset.localIdentifier] ?? asset.isFavorite
    }

    private func removeFromSessionDeletionSummary(_ asset: PHAsset) {
        guard sessionDeletedIdentifiers.remove(asset.localIdentifier) != nil else { return }
        sessionSummary.markedForDeletionCount = max(0, sessionSummary.markedForDeletionCount - 1)
        sessionSummary.estimatedReclaimBytes = max(
            0,
            sessionSummary.estimatedReclaimBytes - estimatedBytes(for: asset)
        )
    }

    private func adjustFilterCounts(for asset: PHAsset, delta: Int) {
        let matchingFilters = PhotoFilter.allCases.filter { filter in
            switch filter {
            case .all: true
            case .photos: asset.mediaType == .image
            case .screenshots: asset.mediaSubtypes.contains(.photoScreenshot)
            case .videos: asset.mediaType == .video
            case .largeVideos:
                asset.mediaType == .video && (
                    asset.duration >= 60 || (asset.pixelWidth >= 3_840 && asset.pixelHeight >= 2_160)
                )
            case .livePhotos: asset.mediaSubtypes.contains(.photoLive)
            case .favorites: isFavorite(asset)
            case .selfies: currentFilter == .selfies
            case .similar: currentFilter == .similar && assets.contains { $0.localIdentifier == asset.localIdentifier }
            }
        }
        for filter in matchingFilters {
            filterCounts[filter] = max(0, (filterCounts[filter] ?? 0) + delta)
        }
    }

    // MARK: Queue Persistence

    private func reconcilePendingQueue() async {
        pendingQueueFetchRevision += 1
        let requestRevision = pendingQueueFetchRevision
        while isAuthorized, !isDeleting, !Task.isCancelled {
            let revision = pendingQueueRevision
            let authorization = photoService.authorizationStatus
            let identifiers = pendingDeletionIdentifiers
            guard !identifiers.isEmpty else {
                trashBin = []
                return
            }
            let fetched = await photoService.fetchAssets(localIdentifiers: identifiers)
            guard requestRevision == pendingQueueFetchRevision,
                  isAuthorized, !isDeleting, !Task.isCancelled,
                  photoService.authorizationStatus == authorization else { return }
            // Retry from current membership instead of publishing a stale read.
            guard revision == pendingQueueRevision else { continue }
            let byIdentifier = Dictionary(fetched.map { ($0.localIdentifier, $0) },
                                          uniquingKeysWith: { _, latest in latest })
            trashBin = identifiers.compactMap { byIdentifier[$0] }
            return
        }
    }

    private func appendToPendingQueue(_ assets: [PHAsset]) {
        var identifiers = Set(pendingDeletionIdentifiers)
        let additions = assets.filter { identifiers.insert($0.localIdentifier).inserted }
        guard !additions.isEmpty else { return }
        pendingDeletionIdentifiers.append(contentsOf: additions.map(\.localIdentifier))
        trashBin.append(contentsOf: additions)
        persistPendingQueue()
    }

    private func removeFromPendingQueue(_ identifiers: Set<String>) {
        pendingDeletionIdentifiers.removeAll { identifiers.contains($0) }
        trashBin.removeAll { identifiers.contains($0.localIdentifier) }
        persistPendingQueue()
    }

    private func persistPendingQueue() {
        pendingQueueRevision += 1
        defaults.set(pendingDeletionIdentifiers, forKey: pendingDeletionKey)
    }

    private func persistViewedIdentifiers() {
        defaults.set(Array(persistedViewedIdentifiers), forKey: viewedIdentifiersKey)
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

struct PhotoLibrarySnapshotID: Equatable {
    let library: Int
    let queue: Int
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
    let restoresDeletedAsset: Bool
}

// MARK: - Photo Library Changes

extension PhotoManager: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyAuthorization(self.photoService.authorizationStatus)
        }
    }
}
