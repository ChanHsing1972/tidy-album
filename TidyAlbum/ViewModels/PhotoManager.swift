import Combine
import Photos
import SwiftUI

// MARK: - Photo Manager

/// The app-level ViewModel. It owns PhotoKit state, review history and the pending
/// deletion queue while views remain focused on presentation and gestures.
@MainActor
final class PhotoManager: NSObject, ObservableObject {
    // MARK: Dependencies

    private let photoService: PhotoLibraryServiceProtocol
    let settings: SettingsStore
    let analytics: AnalyticsStore

    // MARK: Published State

    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var sessionAssets: [PHAsset] = []
    @Published private(set) var trashBin: [PHAsset] = []
    @Published private(set) var isAuthorized = false
    @Published private(set) var isLimited = false
    @Published private(set) var isLoading = false
    @Published private(set) var deletionError: Error?
    @Published var currentFilter: PhotoFilter = .all

    private var history: [ReviewAction] = []
    private var reviewedIdentifiers: Set<String> = []

    var canUndo: Bool { !history.isEmpty }

    // MARK: Initialization

    init(
        photoService: PhotoLibraryServiceProtocol,
        settings: SettingsStore,
        analytics: AnalyticsStore
    ) {
        self.photoService = photoService
        self.settings = settings
        self.analytics = analytics
        super.init()
        photoService.registerChangeObserver(self)
        checkPermission()
    }

    deinit {
        photoService.unregisterChangeObserver(self)
    }

    // MARK: Permission

    func checkPermission() {
        applyAuthorization(photoService.authorizationStatus)
        if photoService.authorizationStatus == .notDetermined {
            Task {
                applyAuthorization(await photoService.requestAuthorization())
            }
        }
    }

    private func applyAuthorization(_ status: PHAuthorizationStatus) {
        isAuthorized = status == .authorized || status == .limited
        isLimited = status == .limited
        if isAuthorized { fetchPhotos() }
    }

    // MARK: Fetching and Sessions

    func setFilter(_ filter: PhotoFilter) {
        guard filter != currentFilter else { return }
        currentFilter = filter
        fetchPhotos()
    }

    func fetchPhotos() {
        isLoading = true
        Task {
            let fetched = await photoService.fetchAssets(filter: currentFilter)
            let trashIDs = Set(trashBin.map(\.localIdentifier))
            let available = fetched.filter { !trashIDs.contains($0.localIdentifier) }
            assets = settings.sortOrder == .random ? available.shuffled() : available
            isLoading = false
        }
    }

    func beginSession() {
        sessionAssets = settings.sortOrder == .random ? assets.shuffled() : assets
        history.removeAll()
        reviewedIdentifiers.removeAll()
        objectWillChange.send()
        AssetImagePipeline.shared.preheat(
            Array(sessionAssets.prefix(8)),
            targetSize: CGSize(width: 1200, height: 1600)
        )
    }

    func recordViewed(_ asset: PHAsset) {
        if reviewedIdentifiers.insert(asset.localIdentifier).inserted {
            analytics.recordReview()
        }
    }

    func preheat(around index: Int) {
        let lower = max(0, index - 2)
        let upper = min(sessionAssets.count, index + 7)
        guard lower < upper else { return }
        AssetImagePipeline.shared.preheat(
            Array(sessionAssets[lower..<upper]),
            targetSize: CGSize(width: 1200, height: 1600)
        )
    }

    // MARK: Review Actions

    func markForDeletion(_ asset: PHAsset, at index: Int) {
        guard !trashBin.contains(where: { $0.localIdentifier == asset.localIdentifier }) else { return }
        trashBin.append(asset)
        if settings.deletionMode == .appTrash {
            history.append(ReviewAction(id: UUID(), asset: asset, index: index, kind: .deletion))
        } else {
            Task { await deleteAssets([asset]) }
        }
        objectWillChange.send()
    }

    func markFavorite(_ asset: PHAsset, at index: Int) {
        let previous = asset.isFavorite
        let actionID = UUID()
        history.append(ReviewAction(id: actionID, asset: asset, index: index, kind: .favorite(previous: previous, target: !previous)))
        objectWillChange.send()
        Task {
            do {
                try await photoService.setFavorite(!previous, for: asset)
            } catch {
                history.removeAll { $0.id == actionID }
                objectWillChange.send()
            }
        }
    }

    func undoLastAction() async -> Int? {
        guard let action = history.popLast() else { return nil }
        switch action.kind {
        case .deletion:
            trashBin.removeAll { $0.localIdentifier == action.asset.localIdentifier }
        case let .favorite(previous, _):
            try? await photoService.setFavorite(previous, for: action.asset)
        }
        objectWillChange.send()
        return action.index
    }

    // MARK: Pending Deletion

    func restoreFromTrash(_ asset: PHAsset) {
        trashBin.removeAll { $0.localIdentifier == asset.localIdentifier }
        history.removeAll { $0.asset.localIdentifier == asset.localIdentifier }
        objectWillChange.send()
    }

    func restoreAllFromTrash() {
        let identifiers = Set(trashBin.map(\.localIdentifier))
        trashBin.removeAll()
        history.removeAll { identifiers.contains($0.asset.localIdentifier) }
        objectWillChange.send()
    }

    func emptyTrash() async {
        await deleteAssets(trashBin)
    }

    private func deleteAssets(_ targets: [PHAsset]) async {
        guard !targets.isEmpty else { return }
        deletionError = nil
        do {
            try await photoService.deleteAssets(targets)
            for asset in targets {
                analytics.recordDeletion(asset: asset, bytes: estimatedBytes(for: asset))
            }
            let identifiers = Set(targets.map(\.localIdentifier))
            trashBin.removeAll { identifiers.contains($0.localIdentifier) }
            history.removeAll { identifiers.contains($0.asset.localIdentifier) }
            fetchPhotos()
        } catch {
            deletionError = error
        }
    }

    func clearDeletionError() {
        deletionError = nil
    }

    private func estimatedBytes(for asset: PHAsset) -> Int64 {
        if asset.mediaType == .video {
            return max(Int64(asset.duration * 500_000), 1_000_000)
        }
        let pixels = Int64(asset.pixelWidth) * Int64(asset.pixelHeight)
        return max(Int64(Double(pixels) * 0.32), 200_000)
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

// MARK: - Photo Library Changes

extension PhotoManager: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            fetchPhotos()
        }
    }
}
