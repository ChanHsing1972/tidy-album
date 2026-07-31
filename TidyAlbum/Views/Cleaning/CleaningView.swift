import Photos
import SwiftUI
import UIKit

struct CleaningView: View {
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
    @State private var backdropImage: UIImage?
    @State private var backdropImageRequestID: PHImageRequestID?

    private let navigationSpring = Animation.spring(duration: 0.34, bounce: 0.12)

    private var currentIndex: Int? {
        manager.sessionAssets.firstIndex { $0.localIdentifier == selectedAssetID }
    }

    private var currentAsset: PHAsset? {
        guard let currentIndex, manager.sessionAssets.indices.contains(currentIndex) else { return nil }
        return manager.sessionAssets[currentIndex]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backdrop
                    .ignoresSafeArea()

                Group {
                    if manager.sessionAssets.isEmpty {
                        if manager.sessionGroupNumber == 0 {
                            emptyState
                        } else {
                            completionBridge
                        }
                    } else {
                        CleaningCardStage(
                            assets: manager.sessionAssets,
                            selectedAssetID: $selectedAssetID,
                            hapticsEnabled: settings.hapticsEnabled,
                            isFavorite: manager.isFavorite,
                            onDelete: manager.markForDeletion,
                            onToggleFavorite: manager.markFavorite
                        )
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .bottomBar)
            .toolbar { toolbar }
        }
        .onAppear { selectInitialAsset() }
        .onDisappear {
            AssetImagePipeline.shared.cancel(backdropImageRequestID)
            backdropImageRequestID = nil
        }
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
            guard !manager.sessionAssets.contains(where: { $0.localIdentifier == selectedAssetID }) else { return }
            selectedAssetID = manager.sessionAssets.first?.localIdentifier ?? ""
        }
    }

    // MARK: - Backdrop View

    private var backdrop: some View {
            GeometryReader { proxy in
                ZStack {
                    Color.black

                    if let backdropImage {
                        Image(uiImage: backdropImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(1.16)
                            .blur(radius: 54, opaque: true)
                            .transition(.opacity) // 仅保留透明度转场
                    }

                    Color.black.opacity(0.34)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .drawingGroup(opaque: true, colorMode: .nonLinear)
            }
            .allowsHitTesting(false)
            .task(id: selectedAssetID) { loadBackdropImage() }
        }

        // MARK: - Load Image Function

        private func loadBackdropImage() {
            AssetImagePipeline.shared.cancel(backdropImageRequestID)
            backdropImageRequestID = nil
            
            guard let currentAsset else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    backdropImage = nil
                }
                return
            }

            let targetSize = CGSize(width: 80, height: 80)
            let isFirstLoad = (backdropImage == nil)

            let applyImage: (UIImage) -> Void = { newImage in
                if isFirstLoad {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        backdropImage = newImage
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.32)) {
                        backdropImage = newImage
                    }
                }
            }

            // 1. 缓存命中
            if let cached = AssetImagePipeline.shared.cachedImage(
                for: currentAsset,
                targetSize: targetSize,
                contentMode: .aspectFill
            ) {
                applyImage(cached)
                return
            }

            // 2. 异步请求
            let requestedID = currentAsset.localIdentifier
            backdropImageRequestID = AssetImagePipeline.shared.requestImage(
                for: currentAsset,
                targetSize: targetSize,
                contentMode: .aspectFill
            ) { loadedImage in
                guard requestedID == selectedAssetID else { return }
                applyImage(loadedImage)
            }
        }
    
    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: exitSession) {
                Image(systemName: "xmark")
                    
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.t("Close"))
        }
        ToolbarItem(placement: .principal) { sessionProgress }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showsTrash = true } label: {
                Image(systemName: manager.trashBin.isEmpty ? "trash" : "trash.fill")
                    
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
            .buttonStyle(.plain)
            .disabled(!manager.canUndo || isUndoing)
            .opacity(manager.canUndo ? 1 : 0.35)
            .accessibilityLabel(settings.t("Undo"))
            Spacer()
            if let currentAsset {
                Button { detailsSelection = AssetSheetSelection(asset: currentAsset) } label: {
                    HStack(spacing: 8) {
                        VStack(spacing: 2) {
                            Text(currentAsset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "-")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text("\(currentAsset.pixelWidth) x \(currentAsset.pixelHeight)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if manager.isFavorite(currentAsset) {
                            Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minWidth: 200, maxWidth: 200, minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.t("Details"))
            }
            Spacer()
            Button(action: prepareShare) {
                Group {
                    if isPreparingShare { ProgressView().controlSize(.small) }
                    else { Image(systemName: "square.and.arrow.up").font(.body.weight(.semibold)) }
                }
                
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(currentAsset == nil || isPreparingShare)
            .opacity(currentAsset == nil ? 0.35 : 1)
            .accessibilityLabel(settings.t("Share"))
        }
    }

    @ViewBuilder private var sessionProgress: some View {
        let total = manager.sessionAssets.count
        let current = (currentIndex ?? 0) + 1
        let value = total == 0 ? 0 : Double(current) / Double(total)
        switch settings.progressDisplayMode {
        case .barOnly:
            AnimatedProgressBar(value: value).frame(width: 108, height: 4)
        case .textOnly:
            Text("\(current) / \(total)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .contentTransition(.numericText())
        case .both:
            VStack(spacing: 5) {
                Text("\(current) / \(total)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
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

    private var completionBridge: some View {
        GroupCompleteView(
            settings: settings,
            hasNextGroup: manager.hasNextGroup,
            onNextGroup: {
                manager.loadNextGroup()
                selectedAssetID = ""
                selectInitialAsset()
            },
            onEnd: {
                dismiss()
                onFinish?()
            }
        )
    }

    private func selectInitialAsset() {
        guard selectedAssetID.isEmpty, let first = manager.sessionAssets.first else { return }
        selectedAssetID = first.localIdentifier
    }
}

// MARK: Gesture Stage

private struct CleaningCardStage: View {
    let assets: [PHAsset]
    @Binding var selectedAssetID: String
    let hapticsEnabled: Bool
    let isFavorite: (PHAsset) -> Bool
    let onDelete: (PHAsset, Int) -> Void
    let onToggleFavorite: (PHAsset, Int) -> Void

    @State private var dragTranslation = CGSize.zero
    @State private var dragAxis = DragAxis.undetermined
    @State private var thresholdHapticSent = false
    @State private var isTransitioning = false
    @State private var isDeleting = false
    @State private var transitionTask: Task<Void, Never>?

    private let actionThreshold: CGFloat = 92
    private let navigationSpring = Animation.spring(duration: 0.3, bounce: 0.1)
    private let returnSpring = Animation.spring(duration: 0.34, bounce: 0.18)

    private var currentIndex: Int? {
        assets.firstIndex { $0.localIdentifier == selectedAssetID }
    }

    private var currentAsset: PHAsset? {
        guard let currentIndex, assets.indices.contains(currentIndex) else { return nil }
        return assets[currentIndex]
    }

    var body: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width + 18
            let verticalProgress = min(abs(dragTranslation.height) / actionThreshold, 1)
            ZStack {
                ForEach(visibleAssetsWithRelation, id: \.asset.localIdentifier) { item in
                    let isCurrent = item.relation == 0
                    CardView(asset: item.asset, isActive: isCurrent)
                        .equatable()
                        .overlay {
                            if isCurrent { actionOverlay(for: item.asset) }
                        }
                        .scaleEffect(cardScale(relation: item.relation, verticalProgress: verticalProgress))
                        .offset(
                            x: CGFloat(item.relation) * pageWidth + horizontalDrag,
                            y: cardVerticalOffset(relation: item.relation, progress: verticalProgress)
                        )
                        .zIndex(isCurrent ? 10 : Double(4 - abs(item.relation)))
                        .accessibilityHidden(!isCurrent)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(reviewGesture(in: proxy.size))
        }
        .padding(.bottom, 38)
        .onDisappear {
            transitionTask?.cancel()
            transitionTask = nil
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                clearGestureState()
                isDeleting = false
                isTransitioning = false
            }
        }
    }

    private var visibleAssetsWithRelation: [(asset: PHAsset, relation: Int)] {
        guard let currentIndex, !assets.isEmpty else { return [] }
        let lower = max(0, currentIndex - 1)
        let upper = min(assets.count - 1, currentIndex + 1)
        return (lower...upper).map { (assets[$0], $0 - currentIndex) }
    }

    private var horizontalDrag: CGFloat {
        dragAxis == .horizontal ? dragTranslation.width : 0
    }

    private func cardVerticalOffset(relation: Int, progress: CGFloat) -> CGFloat {
        if relation == 0, dragAxis == .vertical {
            if isDeleting { return dragTranslation.height }
            let value = dragTranslation.height
            let magnitude = abs(value)
            let resisted = magnitude <= actionThreshold
                ? magnitude
                : actionThreshold + (magnitude - actionThreshold) * 0.58
            return value < 0 ? -resisted : resisted
        }
        if relation == 1, dragAxis == .vertical {
            return 18 * (1 - progress)
        }
        return 0
    }

    private func cardScale(relation: Int, verticalProgress: CGFloat) -> CGFloat {
        if relation == 0, dragAxis == .vertical { return 1 - verticalProgress * 0.018 }
        if relation == 1, dragAxis == .vertical { return 0.965 + verticalProgress * 0.035 }
        return 1
    }

    private func reviewGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard !isTransitioning else { return }
                if dragAxis == .undetermined {
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    guard max(horizontal, vertical) > 10 else { return }
                    dragAxis = vertical > horizontal * 1.15 ? .vertical : .horizontal
                }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    switch dragAxis {
                    case .horizontal:
                        dragTranslation = CGSize(width: value.translation.width, height: 0)
                    case .vertical:
                        dragTranslation = CGSize(width: 0, height: value.translation.height)
                    case .undetermined:
                        break
                    }
                }
                if dragAxis == .vertical { updateHaptic(for: value.translation.height) }
            }
            .onEnded { value in
                guard !isTransitioning else { return }
                thresholdHapticSent = false
                switch dragAxis {
                case .vertical:
                    finishVerticalGesture(value, canvasSize: size)
                case .horizontal:
                    finishHorizontalGesture(value, pageWidth: size.width + 18)
                case .undetermined:
                    resetGesture(animated: true)
                }
            }
    }

    private func finishHorizontalGesture(_ value: DragGesture.Value, pageWidth: CGFloat) {
        let projected = value.predictedEndTranslation.width
        let trigger = pageWidth * 0.2
        let direction: Int
        if projected < -trigger || value.translation.width < -trigger {
            direction = 1
        } else if projected > trigger || value.translation.width > trigger {
            direction = -1
        } else {
            resetGesture(animated: true)
            return
        }
        guard let currentIndex else {
            resetGesture(animated: true)
            return
        }
        let destination = currentIndex + direction
        guard assets.indices.contains(destination) else {
            resetGesture(animated: true)
            boundaryHaptic()
            return
        }

        isTransitioning = true
        let destinationID = assets[destination].localIdentifier
        withAnimation(navigationSpring) {
            dragTranslation = CGSize(width: -CGFloat(direction) * pageWidth, height: 0)
        }
        scheduleTransition(after: .milliseconds(300)) {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                selectedAssetID = destinationID
                clearGestureState()
                isTransitioning = false
            }
        }
    }

    private func finishVerticalGesture(_ value: DragGesture.Value, canvasSize: CGSize) {
        let projected = value.predictedEndTranslation.height
        let actual = value.translation.height
        let resolved = projected == 0 ? actual : projected
        let shouldCommit = abs(actual) >= actionThreshold || abs(projected) >= actionThreshold * 1.35
        guard shouldCommit else {
            resetGesture(animated: true)
            return
        }
        if resolved < 0 {
            commitDeletion(canvasSize: canvasSize)
        } else {
            commitFavorite()
        }
    }

    private func commitDeletion(canvasSize: CGSize) {
        guard let asset = currentAsset, let index = currentIndex else {
            resetGesture(animated: true)
            return
        }
        let nextID: String
        if assets.indices.contains(index + 1) {
            nextID = assets[index + 1].localIdentifier
        } else if index > 0 {
            nextID = assets[index - 1].localIdentifier
        } else {
            nextID = ""
        }

        let startOffset = cardVerticalOffset(relation: 0, progress: 1)
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isTransitioning = true
            isDeleting = true
            dragTranslation = CGSize(width: 0, height: startOffset)
        }
        withAnimation(.easeOut(duration: 0.24)) {
            dragTranslation = CGSize(width: 0, height: -max(canvasSize.height * 1.18, 760))
        }
        scheduleTransition(after: .milliseconds(240)) {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                onDelete(asset, index)
                selectedAssetID = nextID
                clearGestureState()
                isDeleting = false
                isTransitioning = false
            }
        }
    }

    private func commitFavorite() {
        guard let asset = currentAsset, let index = currentIndex else {
            resetGesture(animated: true)
            return
        }
        isTransitioning = true
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            onToggleFavorite(asset, index)
        }
        withAnimation(returnSpring) {
            clearGestureState()
        }
        scheduleTransition(after: .milliseconds(340)) {
            isTransitioning = false
        }
    }

    private func resetGesture(animated: Bool) {
        if animated {
            withAnimation(returnSpring) { clearGestureState() }
        } else {
            clearGestureState()
        }
    }

    private func clearGestureState() {
        dragTranslation = .zero
        dragAxis = .undetermined
        thresholdHapticSent = false
    }

    private func scheduleTransition(
        after duration: Duration,
        action: @escaping @MainActor () -> Void
    ) {
        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            action()
            transitionTask = nil
        }
    }

    private func updateHaptic(for translation: CGFloat) {
        let crossed = abs(translation) >= actionThreshold
        if crossed, !thresholdHapticSent {
            thresholdHapticSent = true
            guard hapticsEnabled else { return }
            UIImpactFeedbackGenerator(style: translation < 0 ? .rigid : .soft).impactOccurred()
        } else if !crossed {
            thresholdHapticSent = false
        }
    }

    private func boundaryHaptic() {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
    }

    private func actionOverlay(for asset: PHAsset) -> some View {
        let progress = min(abs(dragTranslation.height) / 150, 1)
        return ZStack {
            IconOverlayView(
                icon: "trash.fill",
                color: .red,
                progress: dragAxis == .vertical && dragTranslation.height < 0 ? progress : 0
            )
            IconOverlayView(
                icon: isFavorite(asset) ? "heart.slash.fill" : "heart.fill",
                color: .pink,
                progress: dragAxis == .vertical && dragTranslation.height > 0 ? progress : 0
            )
        }
        .allowsHitTesting(false)
    }
}

private enum DragAxis { case undetermined, horizontal, vertical }

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

private struct GroupCompleteView: View {
    let settings: SettingsStore
    let hasNextGroup: Bool
    let onNextGroup: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: hasNextGroup ? "checkmark.circle.fill" : "flag.checkered.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(settings.t(hasNextGroup ? "本组已完成" : "全部完成"))
                .font(.title2.weight(.semibold))
            if hasNextGroup {
                Text(settings.t("是否继续清理下一组？"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    Button(settings.t("结束")) {
                        onEnd()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.secondary)
                    Button(settings.t("继续")) {
                        onNextGroup()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            } else {
                Button(settings.t("完成")) {
                    onEnd()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            Spacer()
        }
        .padding()
    }
}
