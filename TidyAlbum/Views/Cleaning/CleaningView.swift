import CoreLocation
import Photos
import SwiftUI
import UIKit
import Inject

struct CleaningView: View {
    @ObserveInjection var inject
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    var onFinish: (() -> Void)?

    @State private var selectedAssetID = ""
    @State private var detailsSelection: AssetSheetSelection?
    @State private var albumSelection: AlbumAssetSelection?
    @State private var showsTrash = false
    @State private var activityItems: ActivityItems?
    @State private var isPreparingShare = false
    @State private var isUndoing = false
    @State private var pendingUndoCount = 0
    @State private var activeUndoAnimationToken: UUID?
    @State private var isExiting = false
    @State private var showsTimeline = false
    @State private var isTimelinePreviewVisible = false
    @State private var timelineAssets: [PHAsset] = []
    @State private var isInspecting = false
    @State private var completionControlsHidden = false
    @State private var showsShareError = false
    @State private var renderingSession = CleaningUIKitSession()
    @State private var selectionAnimationRequest: CleaningSelectionAnimationRequest?

    private var currentIndex: Int? {
        manager.sessionAssets.firstIndex { $0.localIdentifier == selectedAssetID }
    }

    private var currentAsset: PHAsset? {
        guard let currentIndex, manager.sessionAssets.indices.contains(currentIndex) else { return nil }
        return manager.sessionAssets[currentIndex]
    }

    private var availableTimelineAssets: [PHAsset] {
        let trashIDs = Set(manager.trashBin.map(\.localIdentifier))
        return timelineAssets.filter { !trashIDs.contains($0.localIdentifier) }
    }

    private var timelineTargetColumn: Int {
        CleaningTimelineLayout.targetColumn(
            in: availableTimelineAssets,
            selectedAssetID: selectedAssetID
        )
    }

    private var hidesCleaningChrome: Bool {
        isInspecting || isTimelinePreviewVisible
    }

    var body: some View {
        let _ = inject
        NavigationStack {
            ZStack {
                CleaningUIKitBackdrop(
                    session: renderingSession,
                    assets: manager.sessionAssets,
                    selectedAssetID: selectedAssetID,
                    sessionGroupNumber: manager.sessionGroupNumber
                )
                    .ignoresSafeArea()

                if isTimelinePreviewVisible || showsTimeline {
                    CleaningTimelineView(
                        assets: availableTimelineAssets,
                        selectedAssetID: selectedAssetID,
                        settings: settings,
                        onSelect: selectTimelineAsset
                    )
                    .transition(.opacity)
                    .allowsHitTesting(showsTimeline)
                    .zIndex(1)
                }

                Group {
                    if manager.sessionGroupNumber == 0 && manager.sessionAssets.isEmpty {
                        emptyState
                    } else {
                        CleaningUIKitCardStage(
                            session: renderingSession,
                            assets: manager.sessionAssets,
                            selectedAssetID: $selectedAssetID,
                            selectionAnimationRequest: selectionAnimationRequest,
                            settings: settings,
                            hapticsEnabled: settings.hapticsEnabled,
                            hasNextGroup: manager.hasNextGroup,
                            groupNumber: manager.sessionGroupNumber,
                            groupCount: manager.sessionGroupCount,
                            isFavorite: manager.isFavorite,
                            onDelete: manager.markForDeletion,
                            onToggleFavorite: manager.markFavorite,
                            onAddToAlbum: { albumSelection = AlbumAssetSelection(asset: $0) },
                            timelineTargetColumn: timelineTargetColumn,
                            onTimelinePreviewChange: { visible in
                                withAnimation(.easeOut(duration: 0.14)) {
                                    isTimelinePreviewVisible = visible
                                }
                            },
                            onShowTimeline: {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    showsTimeline = true
                                    isTimelinePreviewVisible = false
                                }
                            },
                            onImmersiveChange: { immersive in
                                withAnimation(.easeInOut(duration: 0.16)) { isInspecting = immersive }
                            },
                            onCompletionControlsHiddenChange: { hidden in
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    completionControlsHidden = hidden
                                }
                            },
                            onSelectionAnimationFinished: selectionAnimationFinished,
                            onNextGroup: loadNextGroup,
                            onEnd: finishSession
                        )
                    }
                }
                .opacity(showsTimeline ? 0 : 1)
                .allowsHitTesting(!showsTimeline)
                .zIndex(2)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .bottomBar)
            .toolbar { toolbar }
        }
        .tint(.primary)
        .onAppear { selectInitialAsset() }
        .task {
            guard timelineAssets.isEmpty else { return }
            timelineAssets = await manager.fetchCalendarAssets()
        }
        .sheet(item: $detailsSelection) { selection in
            AssetDetailsView(asset: selection.asset, settings: settings).id(selection.id)
        }
        .sheet(item: $albumSelection) { selection in
            AlbumPickerView(asset: selection.asset, manager: manager, settings: settings)
        }
        .sheet(isPresented: $showsTrash) {
            TrashView(manager: manager, settings: settings)
        }
        .sheet(item: $activityItems) { items in
            ActivityView(items: items.values)
                .presentationDetents([.medium, .large])
        }
        .alert(settings.t("Unable to Share"), isPresented: $showsShareError) {
            Button(settings.t("Done"), role: .cancel) {}
        } message: {
            Text(settings.t("The original item could not be prepared. Please check iCloud connectivity and try again."))
        }
        .alert(
            settings.t("Delete Failed"),
            isPresented: Binding(
                get: { manager.deletionError != nil },
                set: { if !$0 { manager.clearDeletionError() } }
            )
        ) {
            Button(settings.t("Done"), role: .cancel) { manager.clearDeletionError() }
        } message: {
            Text(manager.deletionError?.localizedDescription ?? settings.t("Try again from the pending deletion queue."))
        }
        .onChange(of: selectedAssetID) { _, identifier in
            guard let index = manager.sessionAssets.firstIndex(where: { $0.localIdentifier == identifier }) else {
                return
            }
            manager.recordViewed(manager.sessionAssets[index])
            manager.preheat(around: index)
        }
        .onChange(of: manager.sessionAssets.count) { _, _ in
            guard selectedAssetID != CleaningPageID.groupCompletion else { return }
            guard !manager.sessionAssets.contains(where: { $0.localIdentifier == selectedAssetID }) else { return }
            selectedAssetID = manager.sessionAssets.first?.localIdentifier ?? CleaningPageID.groupCompletion
        }
    }
    
    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if showsTimeline {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: closeTimeline) {
                    Label("Close", systemImage: "xmark")
                }
                .accessibilityLabel(settings.t("Close"))
            }
            ToolbarItem(placement: .principal) {
                Text(settings.t("Photos by Date"))
                    .font(.headline)
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: exitSession) {
                    Label("Exit", systemImage: "xmark")
                }
                .opacity(hidesCleaningChrome ? 0 : 1)
                .allowsHitTesting(!hidesCleaningChrome)
                .accessibilityLabel(settings.t("Close"))
            }
            ToolbarItem(placement: .principal) {
                sessionProgress
                    .opacity(hidesCleaningChrome ? 0 : 1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsTrash = true } label: {
                    Label("Trash", systemImage: manager.trashBin.isEmpty ? "trash" : "trash.fill")
                }
                .badge(manager.trashBin.count)
                .opacity(hidesCleaningChrome ? 0 : 1)
                .allowsHitTesting(!hidesCleaningChrome)
                .accessibilityLabel(settings.t("Trash"))
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button { requestUndo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!manager.canUndo)
                .opacity(hidesCleaningChrome ? 0 : (manager.canUndo ? 1 : 0.35))
                .allowsHitTesting(!hidesCleaningChrome)
                .accessibilityLabel(settings.t("Undo"))
                Spacer()
                CleaningAssetInfoIslandButton(
                    asset: completionControlsHidden || hidesCleaningChrome ? nil : currentAsset,
                    settings: settings,
                    isFavorite: currentAsset.map(manager.isFavorite) ?? false,
                    accessibilityLabel: settings.t("Details")
                ) { asset in
                    detailsSelection = AssetSheetSelection(asset: asset)
                }
                Spacer()
                Button(action: prepareShare) {
                    if isPreparingShare {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(currentAsset == nil || isPreparingShare)
                .opacity(hidesCleaningChrome ? 0 : (currentAsset == nil ? 0.35 : 1))
                .allowsHitTesting(!hidesCleaningChrome)
                .accessibilityLabel(settings.t("Share"))
            }
        }
    }

    @ViewBuilder private var sessionProgress: some View {
        let total = manager.sessionAssets.count
        let current = selectedAssetID == CleaningPageID.groupCompletion ? total : (currentIndex ?? 0) + 1
        let value = total == 0 ? 0 : Double(current) / Double(total)
        switch settings.progressDisplayMode {
        case .barOnly:
            AnimatedProgressBar(value: value).frame(width: 108, height: 4)
        case .textOnly:
            Text("\(current) / \(total)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.36, bounce: 0.1), value: current)
        case .both:
            VStack(spacing: 5) {
                Text("\(current) / \(total)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.36, bounce: 0.1), value: current)
                AnimatedProgressBar(value: value).frame(width: 108, height: 4)
            }
        }
    }

    private func requestUndo() {
        guard manager.canUndo else { return }
        pendingUndoCount += 1
        processNextUndoIfNeeded()
    }

    private func processNextUndoIfNeeded() {
        guard !isUndoing, pendingUndoCount > 0 else { return }
        pendingUndoCount -= 1
        isUndoing = true
        Task {
            guard let result = await manager.undoLastAction() else {
                pendingUndoCount = 0
                isUndoing = false
                return
            }
            let token = UUID()
            activeUndoAnimationToken = token
            selectionAnimationRequest = CleaningSelectionAnimationRequest(
                token: token,
                assetIdentifier: result.assetIdentifier,
                style: result.restoresDeletedAsset ? .deletionRestore : .reviewReveal
            )
            selectedAssetID = result.assetIdentifier

            // The controller normally acknowledges the exact animator token.
            // Keep a timeout only as a lifecycle fallback so dismissing or
            // replacing the stage cannot leave the undo queue permanently stuck.
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard activeUndoAnimationToken == token else { return }
                selectionAnimationFinished(token)
            }
        }
    }

    private func selectionAnimationFinished(_ token: UUID) {
        guard activeUndoAnimationToken == token else { return }
        activeUndoAnimationToken = nil
        if selectionAnimationRequest?.token == token {
            selectionAnimationRequest = nil
        }
        isUndoing = false
        processNextUndoIfNeeded()
    }

    private func selectTimelineAsset(_ asset: PHAsset) {
        if !manager.sessionAssets.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
            manager.beginSession(around: asset, from: availableTimelineAssets)
        }
        selectedAssetID = asset.localIdentifier
        closeTimeline()
    }

    private func closeTimeline() {
        withAnimation(.easeInOut(duration: 0.16)) {
            showsTimeline = false
            isTimelinePreviewVisible = false
        }
    }

    private func prepareShare() {
        guard let currentAsset, !isPreparingShare else { return }
        isPreparingShare = true
        Task {
            let values = await AssetSharingService.shared.activityItems(for: currentAsset)
            isPreparingShare = false
            if values.isEmpty { showsShareError = true }
            else { activityItems = ActivityItems(values: values) }
        }
    }

    private func exitSession() {
        guard !isExiting else { return }
        isExiting = true
        dismiss()
    }

    private var emptyState: some View {
        ContentUnavailableView(
            settings.t("No items in this collection"),
            systemImage: "photo.on.rectangle.angled",
            description: Text(settings.t("Review another collection"))
        )
    }

    private func selectInitialAsset() {
        guard selectedAssetID.isEmpty else { return }
        selectedAssetID = manager.sessionAssets.first?.localIdentifier ?? CleaningPageID.groupCompletion
    }

    private func loadNextGroup() {
        guard manager.loadNextGroup() else {
            finishSession()
            return
        }
        selectedAssetID = manager.sessionAssets.first?.localIdentifier ?? CleaningPageID.groupCompletion
    }

    private func finishSession() {
        dismiss()
        onFinish?()
    }
}

private struct AssetSheetSelection: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

private struct AlbumAssetSelection: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

private struct AnimatedProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.15))
                Capsule()
                    .fill(.primary)
                    .frame(width: max(value > 0 ? 3 : 0, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .animation(.spring(duration: 0.36, bounce: 0.1), value: value)
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

private struct CleaningAssetInfoIslandButton: View {
    let asset: PHAsset?
    @ObservedObject var settings: SettingsStore
    let isFavorite: Bool
    let accessibilityLabel: String
    let onSelect: (PHAsset) -> Void

    @State private var displayedAsset: PHAsset?
    @State private var displayedFavorite: Bool
    @State private var isVisible: Bool
    @State private var removalToken: UUID?

    init(
        asset: PHAsset?,
        settings: SettingsStore,
        isFavorite: Bool,
        accessibilityLabel: String,
        onSelect: @escaping (PHAsset) -> Void
    ) {
        self.asset = asset
        self.settings = settings
        self.isFavorite = isFavorite
        self.accessibilityLabel = accessibilityLabel
        self.onSelect = onSelect
        _displayedAsset = State(initialValue: asset)
        _displayedFavorite = State(initialValue: isFavorite)
        _isVisible = State(initialValue: asset != nil)
    }

    var body: some View {
        Group {
            if let displayedAsset {
                Button {
                    onSelect(displayedAsset)
                } label: {
                    CleaningAssetInfoIsland(
                        asset: displayedAsset,
                        settings: settings,
                        isFavorite: displayedFavorite
                    )
                    .frame(width: 210)
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                }
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHidden(!isVisible)
                .allowsHitTesting(isVisible)
                .opacity(isVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: isVisible)
            }
        }
        // Release toolbar layout space as soon as completion begins while the
        // cached island continues drawing outside this zero-width slot for its
        // opacity fade. This prevents the system from overflowing Share into
        // an ellipsis menu on compact widths.
        .frame(width: asset == nil ? 0 : 210)
        .onChange(of: asset?.localIdentifier, initial: true) { _, _ in
            if let asset {
                // Returning from the completion page keeps the previous asset
                // around briefly so the removal can fade out. Use visibility,
                // rather than only the cached asset value, to make the next
                // card fade back in even when the transition finishes before
                // the delayed cache cleanup runs.
                let needsFadeIn = !isVisible || displayedAsset == nil
                removalToken = nil
                displayedAsset = asset
                displayedFavorite = isFavorite
                if needsFadeIn {
                    isVisible = false
                    let identifier = asset.localIdentifier
                    Task {
                        await Task.yield()
                        guard displayedAsset?.localIdentifier == identifier else { return }
                        isVisible = true
                    }
                } else {
                    isVisible = true
                }
            } else {
                isVisible = false
                let token = UUID()
                removalToken = token
                Task {
                    try? await Task.sleep(for: .milliseconds(240))
                    guard removalToken == token, asset == nil else { return }
                    displayedAsset = nil
                }
            }
        }
        .onChange(of: isFavorite) { _, newValue in
            guard asset != nil else { return }
            displayedFavorite = newValue
        }
    }
}

private struct CleaningAssetInfoIsland: View {
    let asset: PHAsset?
    @ObservedObject var settings: SettingsStore
    let isFavorite: Bool

    @State private var placeName: String?
    @State private var placeNameAssetID = ""
    @State private var assetFileSize: Int64?
    @State private var fileSizeAssetID = ""

    private var assetIdentifier: String {
        asset?.localIdentifier ?? ""
    }

    // 同步判断是否有二级信息（决定 VStack 是单行还是双行）
    private var hasSecondaryInfo: Bool {
        guard let asset else { return false }
        switch settings.assetInfoDisplayMode {
        case .location:
            return asset.location != nil
        case .fileSize:
            return true
        case .fullDate:
            return asset.creationDate != nil
        case .resolution:
            return true
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let asset {
                VStack(spacing: 2) {
                    // 1. 时间信息（不使用 .id，依靠 contentTransition 配合 withAnimation 进行无缝淡入淡出）
                    if let creationDate = asset.creationDate {
                        Text(settings.relativeDate(creationDate))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                    
                    // Reserve the second line before asynchronous metadata arrives.
                    // This keeps the time baseline fixed while location text fades in.
                    if hasSecondaryInfo {
                        let text = secondaryInfoText(for: asset)
                        Text(text ?? " ")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .opacity(text == nil ? 0 : 1)
                            .animation(.easeInOut(duration: 0.18), value: text)
                    }
                }
                
                // 3. 爱心图标
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal: .identity
                            )
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.22), value: assetIdentifier)
        .animation(.easeInOut(duration: 0.2), value: hasSecondaryInfo)
        .animation(.easeOut(duration: 0.18), value: isFavorite)
        .task(id: asset.map { "\($0.localIdentifier)-\(settings.language.rawValue)-\(settings.assetInfoDisplayMode.rawValue)" } ?? "") {
            guard let asset else { return }
            
            switch settings.assetInfoDisplayMode {
            case .location:
                placeNameAssetID = ""
                placeName = nil
                if let location = asset.location {
                    let name = await placeDescription(for: location)
                    withAnimation(.easeInOut(duration: 0.22)) {
                        placeNameAssetID = asset.localIdentifier
                        placeName = name
                    }
                }
            case .fileSize:
                fileSizeAssetID = ""
                assetFileSize = nil
                let size = await loadFileSize(for: asset)
                withAnimation(.easeInOut(duration: 0.22)) {
                    fileSizeAssetID = asset.localIdentifier
                    assetFileSize = size
                }
            case .fullDate, .resolution:
                break
            }
        }
    }

    private func secondaryInfoText(for asset: PHAsset) -> String? {
        switch settings.assetInfoDisplayMode {
        case .location:
            return placeNameAssetID == asset.localIdentifier ? placeName : nil
        case .fileSize:
            if fileSizeAssetID == asset.localIdentifier, let size = assetFileSize {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
            return nil
        case .fullDate:
            if let date = asset.creationDate {
                return settings.fullDate(date)
            }
            return nil
        case .resolution:
            return "\(asset.pixelWidth) × \(asset.pixelHeight)"
        }
    }

    private func placeDescription(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        let geocodingLocation = ChinaCoordinateTransform.gcj02Location(fromWGS84: location)
        let placemarks = try? await geocoder.reverseGeocodeLocation(
            geocodingLocation,
            preferredLocale: settings.language.locale
        )
        guard let placemark = placemarks?.first else { return nil }
        let candidates = [placemark.administrativeArea, placemark.locality, placemark.subLocality]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let uniqueParts = candidates.reduce(into: [String]()) { parts, candidate in
            if !parts.contains(candidate) { parts.append(candidate) }
        }
        return uniqueParts.isEmpty ? nil : uniqueParts.joined(separator: " ")
    }

    private func loadFileSize(for asset: PHAsset) async -> Int64 {
        estimatedFileSize(for: asset)
    }

    private func estimatedFileSize(for asset: PHAsset) -> Int64 {
        if asset.mediaType == .video {
            return max(Int64(asset.duration * 500_000), 1_000_000)
        }
        let pixels = Int64(asset.pixelWidth) * Int64(asset.pixelHeight)
        return max(Int64(Double(pixels) * 0.32), 200_000)
    }
}
