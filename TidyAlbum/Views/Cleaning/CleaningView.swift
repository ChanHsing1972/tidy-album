import Photos
import SwiftUI
import UIKit

// MARK: - Cleaning Session

struct CleaningView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    var onFinish: (() -> Void)?

    @State private var selectedAssetID = ""
    @State private var verticalOffset: CGFloat = 0
    @State private var dragAxis: DragAxis = .undetermined
    @State private var thresholdHapticSent = false
    @State private var detailsSelection: AssetSheetSelection?
    @State private var showsTrash = false
    @State private var activityItems: ActivityItems?
    @State private var isPreparingShare = false
    @State private var showsShareError = false

    private let actionThreshold: CGFloat = 96
    private let flyDistance: CGFloat = 900
    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.72)

    private var currentIndex: Int? {
        manager.sessionAssets.firstIndex { $0.localIdentifier == selectedAssetID }
    }

    private var currentAsset: PHAsset? {
        guard let currentIndex else { return nil }
        return manager.sessionAssets[currentIndex]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backdrop
                if manager.sessionGroupTotalCount == 0 {
                    emptyState
                } else if manager.sessionAssets.isEmpty {
                    Color.clear
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(0.4))
                                dismiss()
                                onFinish?()
                            }
                        }
                } else {
                    nativePager
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { toolbar }
        }
        .sheet(item: $detailsSelection) { selection in
            AssetDetailsView(asset: selection.asset, settings: settings)
                .id(selection.id)
        }
        .sheet(isPresented: $showsTrash) {
            TrashView(manager: manager, settings: settings)
        }
        .sheet(item: $activityItems) { items in
            ActivityView(items: items.values)
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
        .onAppear { selectInitialAsset() }
        .onChange(of: selectedAssetID) { _, identifier in
            verticalOffset = 0
            dragAxis = .undetermined
            guard let index = manager.sessionAssets.firstIndex(where: { $0.localIdentifier == identifier }) else {
                return
            }
            manager.recordViewed(manager.sessionAssets[index])
            manager.preheat(around: index)
        }
    }

    // MARK: - Background (single layer, crossfade transition)

    @ViewBuilder
    private var backdrop: some View {
        if let asset = currentAsset {
            AssetMediaView(asset: asset, contentMode: .fill, showsVideoBadge: false)
                .id("backdrop-\(asset.localIdentifier)")
                .blur(radius: 60)
                .overlay(Color.black.opacity(0.35))
                .transition(.opacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    // MARK: - Native Pager

    private var nativePager: some View {
        TabView(selection: $selectedAssetID) {
            ForEach(manager.sessionAssets, id: \.localIdentifier) { asset in
                reviewPage(for: asset)
                    .tag(asset.localIdentifier)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.55), value: currentAsset?.localIdentifier)
        .simultaneousGesture(verticalActionGesture)
    }

    private func reviewPage(for asset: PHAsset) -> some View {
        GeometryReader { proxy in
            CardView(
                asset: asset,
                isActive: asset.localIdentifier == selectedAssetID,
                isFavorite: manager.isFavorite(asset)
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .offset(y: asset.localIdentifier == selectedAssetID ? verticalOffset : 0)
            .scaleEffect(
                asset.localIdentifier == selectedAssetID && dragAxis == .vertical ? 0.988 : 1
            )
            .overlay {
                if asset.localIdentifier == selectedAssetID { actionOverlay }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Vertical Action Gesture

    private var verticalActionGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                if dragAxis == .undetermined {
                    let h = abs(value.translation.width)
                    let v = abs(value.translation.height)
                    guard max(h, v) > 12 else { return }
                    dragAxis = v > h * 1.3 ? .vertical : .horizontal
                }
                guard dragAxis == .vertical else { return }
                verticalOffset = value.translation.height
                updateHaptic(for: value.translation.height)
            }
            .onEnded { value in
                defer {
                    dragAxis = .undetermined
                    thresholdHapticSent = false
                }
                guard dragAxis == .vertical else { return }
                let projected = value.predictedEndTranslation.height
                if verticalOffset <= -actionThreshold || projected <= -actionThreshold * 1.5 {
                    commitDeletion()
                } else if verticalOffset >= actionThreshold || projected >= actionThreshold * 1.5 {
                    commitFavorite()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { verticalOffset = 0 }
                }
            }
    }

    private func updateHaptic(for translation: CGFloat) {
        let crossed = abs(translation) >= actionThreshold
        if crossed, !thresholdHapticSent {
            thresholdHapticSent = true
            guard settings.hapticsEnabled else { return }
            UIImpactFeedbackGenerator(style: translation < 0 ? .heavy : .light).impactOccurred()
        } else if !crossed {
            thresholdHapticSent = false
        }
    }

    private func commitDeletion() {
        guard let asset = currentAsset, let index = currentIndex else { return }
        let nextID: String
        if manager.sessionAssets.indices.contains(index + 1) {
            nextID = manager.sessionAssets[index + 1].localIdentifier
        } else if index > 0 {
            nextID = manager.sessionAssets[index - 1].localIdentifier
        } else {
            nextID = ""
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { verticalOffset = -flyDistance }
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                manager.markForDeletion(asset, at: index)
                selectedAssetID = nextID
                verticalOffset = 0
            }
        }
    }

    private func commitFavorite() {
        guard let asset = currentAsset, let index = currentIndex else { return }
        let hasNext = manager.sessionAssets.indices.contains(index + 1)
        let nextID = hasNext ? manager.sessionAssets[index + 1].localIdentifier : asset.localIdentifier
        manager.markFavorite(asset, at: index)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { verticalOffset = flyDistance }
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            if hasNext {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    selectedAssetID = nextID
                    verticalOffset = 0
                }
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { verticalOffset = 0 }
            }
        }
    }

    private var actionOverlay: some View {
        let progress = min(abs(verticalOffset) / 150, 1)
        let isUp = verticalOffset < 0 && dragAxis == .vertical
        let isDown = verticalOffset > 0 && dragAxis == .vertical
        return ZStack {
            IconOverlayView(icon: "trash.fill", color: .red, progress: isUp ? progress : 0)
            IconOverlayView(
                icon: (currentAsset.map { manager.isFavorite($0) } ?? false) ? "heart.slash.fill" : "heart.fill",
                color: .pink,
                progress: isDown ? progress : 0
            )
        }
        .animation(.easeOut(duration: 0.1), value: progress)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { exitSession() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.t("Close"))
        }
        ToolbarItem(placement: .principal) {
            sessionProgress
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showsTrash = true } label: {
                Image(systemName: manager.trashBin.isEmpty ? "trash" : "trash.fill")
            }
            .buttonStyle(.plain)
            .badge(manager.trashBin.count)
            .id("trash-btn-\(manager.trashBin.count)")
            .accessibilityLabel(settings.t("Trash"))
        }
        ToolbarItemGroup(placement: .bottomBar) {
            // 1. 左侧：撤回按钮
            Button {
                Task {
                    if let result = await manager.undoLastAction() {
                        withAnimation(spring) {
                            selectedAssetID = result.assetIdentifier
                            verticalOffset = 0
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.primary) // 强制使用黑色/Primary
            .disabled(!manager.canUndo)
            .opacity(manager.canUndo ? 1 : 0.35)
            .accessibilityLabel(settings.t("Undo"))

            Spacer() // 弹簧 1：把中间挤向正中央

            // 2. 中间：信息按钮（展示日期 + 像素尺寸 / 文件大小）
            if let currentAsset {
                Button {
                    detailsSelection = AssetSheetSelection(asset: currentAsset)
                } label: {
                    HStack(spacing: 8) {
                        VStack(spacing: 2) {
                            Text(currentAsset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            
                            Text("\(currentAsset.pixelWidth) × \(currentAsset.pixelHeight)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        
                        if manager.isFavorite(currentAsset) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.pink)
                        }
                    }
                    .padding(.horizontal, 20) // 👈 1. 增加左右内边距，让背景/点击区域更宽
                    .padding(.vertical, 4)
                    .frame(minWidth: 200)     // 👈 2. 强行设定最小宽度，避免文字短时浮岛显得太窄
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.t("Details"))
            }

            Spacer() // 弹簧 2：把右侧挤向最右端

            // 3. 右侧：分享按钮
            Button { prepareShare() } label: {
                if isPreparingShare {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(.primary) // 强制使用黑色/Primary
            .disabled(currentAsset == nil || isPreparingShare)
            .opacity(currentAsset == nil ? 0.35 : 1)
            .accessibilityLabel(settings.t("Share"))
        }
    }

    @ViewBuilder private var sessionProgress: some View {
        let total = max(manager.sessionGroupTotalCount, 1)
        let reviewed = min(manager.sessionGroupReviewedCount, total)
        let value = Double(reviewed) / Double(total)
        switch settings.progressDisplayMode {
        case .barOnly:
            AnimatedProgressBar(value: value).frame(width: 108, height: 4)
        case .textOnly:
            Text("\(reviewed) / \(total)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        case .both:
            VStack(spacing: 5) {
                Text("\(reviewed) / \(total) · \(manager.sessionGroupNumber)/\(manager.sessionGroupCount)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                AnimatedProgressBar(value: value).frame(width: 108, height: 4)
            }
        }
    }

    private func prepareShare() {
        guard let currentAsset else { return }
        isPreparingShare = true
        Task {
            let values = await AssetSharingService.shared.activityItems(for: currentAsset)
            isPreparingShare = false
            if values.isEmpty {
                showsShareError = true
            } else {
                activityItems = ActivityItems(values: values)
            }
        }
    }

    private func exitSession() {
        manager.endSession()
        dismiss()
    }

    // MARK: - States

    private var emptyState: some View {
        ContentUnavailableView(
            settings.t("No items in this collection"),
            systemImage: "photo.on.rectangle.angled",
            description: Text(settings.t("Review another collection"))
        )
    }

    private func selectInitialAsset() {
        guard selectedAssetID.isEmpty, let first = manager.sessionAssets.first else { return }
        selectedAssetID = first.localIdentifier
        manager.recordViewed(first)
        manager.preheat(around: 0)
    }
}

// MARK: - Supporting Types

private enum DragAxis {
    case undetermined
    case horizontal
    case vertical
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
        .animation(.easeInOut(duration: 0.38), value: value)
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}
