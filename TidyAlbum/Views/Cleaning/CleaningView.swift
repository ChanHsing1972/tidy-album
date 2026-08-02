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
    @State private var showsTrash = false
    @State private var activityItems: ActivityItems?
    @State private var isPreparingShare = false
    @State private var isUndoing = false
    @State private var isExiting = false
    @State private var showsShareError = false
    @State private var renderingSession = CleaningUIKitSession()

    private let navigationSpring = Animation.spring(duration: 0.34, bounce: 0.12)

    private var currentIndex: Int? {
        manager.sessionAssets.firstIndex { $0.localIdentifier == selectedAssetID }
    }

    private var currentAsset: PHAsset? {
        guard let currentIndex, manager.sessionAssets.indices.contains(currentIndex) else { return nil }
        return manager.sessionAssets[currentIndex]
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

                Group {
                    if manager.sessionGroupNumber == 0 && manager.sessionAssets.isEmpty {
                        emptyState
                    } else {
                        CleaningUIKitCardStage(
                            session: renderingSession,
                            assets: manager.sessionAssets,
                            selectedAssetID: $selectedAssetID,
                            settings: settings,
                            hapticsEnabled: settings.hapticsEnabled,
                            hasNextGroup: manager.hasNextGroup,
                            groupNumber: manager.sessionGroupNumber,
                            groupCount: manager.sessionGroupCount,
                            isFavorite: manager.isFavorite,
                            onDelete: manager.markForDeletion,
                            onToggleFavorite: manager.markFavorite,
                            onNextGroup: loadNextGroup,
                            onEnd: finishSession
                        )
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .bottomBar)
            .toolbar { toolbar }
        }
        .tint(.primary)
        .onAppear { selectInitialAsset() }
        .sheet(item: $detailsSelection) { selection in
            AssetDetailsView(asset: selection.asset, settings: settings).id(selection.id)
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
        ToolbarItem(placement: .topBarLeading) {
            Button(action: exitSession) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(settings.t("Close"))
        }
        ToolbarItem(placement: .principal) { sessionProgress }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showsTrash = true } label: {
                Image(systemName: manager.trashBin.isEmpty ? "trash" : "trash.fill")

                    .contentShape(Rectangle())
            }
            .badge(manager.trashBin.count)
            .id("trash-btn-\(manager.trashBin.count)")
            .accessibilityLabel(settings.t("Trash"))
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button { undo() } label: {
                Group {
                    if isUndoing { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.uturn.backward").font(.body.weight(.semibold)) }
                }
                .contentShape(Rectangle())
            }
            .disabled(!manager.canUndo || isUndoing)
            .opacity(manager.canUndo ? 1 : 0.35)
            .accessibilityLabel(settings.t("Undo"))
            Spacer()
            Button { detailsSelection = currentAsset.map { AssetSheetSelection(asset: $0) } } label: {
                CleaningAssetInfoIsland(
                    asset: currentAsset,
                    settings: settings,
                    isFavorite: currentAsset.map { manager.isFavorite($0) } ?? false
                )
                .frame(width: 210)
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            
            .disabled(currentAsset == nil)
            .opacity(currentAsset == nil ? 0 : 1)
            .accessibilityLabel(settings.t("Details"))
            .frame(width: 210)
            Spacer()
            Button(action: prepareShare) {
                Group {
                    if isPreparingShare { ProgressView().controlSize(.small) }
                    else { Image(systemName: "square.and.arrow.up").font(.body.weight(.semibold)) }
                }
                .contentShape(Rectangle())
            }
            
            .disabled(currentAsset == nil || isPreparingShare)
            .opacity(currentAsset == nil ? 0.35 : 1)
            .accessibilityLabel(settings.t("Share"))
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

    private func undo() {
        guard !isUndoing else { return }
        isUndoing = true
        Task {
            defer { isUndoing = false }
            guard let result = await manager.undoLastAction() else { return }
            withAnimation(navigationSpring) {
                selectedAssetID = result.assetIdentifier
            }
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

private struct CleaningAssetInfoIsland: View {
    let asset: PHAsset?
    @ObservedObject var settings: SettingsStore
    let isFavorite: Bool

    @State private var placeName: String?
    @State private var assetFileSize: Int64?

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
                    
                    // 2. 位置/二级信息（只有真实存在时才插入 VStack，以便单行时时间能居中）
                    if hasSecondaryInfo, let text = secondaryInfoText(for: asset) {
                        Text(text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                            // 消失/出现时仅做透明度淡入淡出，高度交由 VStack 弹性平滑挤压
                            .transition(.opacity)
                    }
                }
                
                // 3. 爱心图标
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 12)
        // 核心：当 hasSecondaryInfo 改变（单双行切换）、爱心改变、或切换图片时，
        // 使用弹簧动画平滑过渡 VStack 布局重排（时间移动到中央/移动到顶部）
        .animation(.easeInOut(duration: 0.22), value: assetIdentifier)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: hasSecondaryInfo)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isFavorite)
        .animation(.easeInOut(duration: 0.22), value: placeName)
        .task(id: asset.map { "\($0.localIdentifier)-\(settings.language.rawValue)-\(settings.assetInfoDisplayMode.rawValue)" } ?? "") {
            guard let asset else { return }
            
            switch settings.assetInfoDisplayMode {
            case .location:
                if let location = asset.location {
                    let name = await placeDescription(for: location)
                    withAnimation(.easeInOut(duration: 0.22)) {
                        placeName = name
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        placeName = nil
                    }
                }
            case .fileSize:
                let size = await loadFileSize(for: asset)
                withAnimation(.easeInOut(duration: 0.22)) {
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
            return placeName
        case .fileSize:
            if let size = assetFileSize {
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
        let placemarks = try? await geocoder.reverseGeocodeLocation(
            location,
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
