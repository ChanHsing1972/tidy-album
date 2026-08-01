import CoreLocation
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
    @State private var backdropImages: [String: UIImage] = [:]
    @State private var backdropImageRequestIDs: [String: PHImageRequestID] = [:]
    @State private var fallbackBackdropImage: UIImage?
    @State private var backdropTransition = BackdropTransition.idle

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
                    if manager.sessionGroupNumber == 0 && manager.sessionAssets.isEmpty {
                        emptyState
                    } else {
                        CleaningCardStage(
                            assets: manager.sessionAssets,
                            selectedAssetID: $selectedAssetID,
                            backdropTransition: $backdropTransition,
                            settings: settings,
                            hapticsEnabled: settings.hapticsEnabled,
                            hasNextGroup: manager.hasNextGroup,
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
        .onAppear { selectInitialAsset() }
        .onDisappear {
            cancelBackdropRequests()
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
        .onChange(of: selectedAssetID) { previousIdentifier, identifier in
            if let previousImage = backdropImages[previousIdentifier] {
                fallbackBackdropImage = previousImage
            }
            guard let index = manager.sessionAssets.firstIndex(where: { $0.localIdentifier == identifier }) else {
                return
            }
            manager.recordViewed(manager.sessionAssets[index])
            manager.preheat(around: index)
            loadBackdropImages(around: index)
        }
        .onChange(of: manager.sessionAssets.count) { _, _ in
            guard selectedAssetID != CleaningPageID.groupCompletion else { return }
            guard !manager.sessionAssets.contains(where: { $0.localIdentifier == selectedAssetID }) else { return }
            selectedAssetID = manager.sessionAssets.first?.localIdentifier ?? CleaningPageID.groupCompletion
        }
        .onChange(of: manager.sessionGroupNumber) { _, _ in
            cancelBackdropRequests()
            backdropImages.removeAll(keepingCapacity: true)
            fallbackBackdropImage = nil
            backdropTransition = .idle
            guard let index = currentIndex else { return }
            loadBackdropImages(around: index)
        }
    }

    // MARK: - Backdrop View

    private var backdrop: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if let image = backdropImages[selectedAssetID]
                    ?? backdropTransition.sourceID.flatMap({ backdropImages[$0] })
                    ?? fallbackBackdropImage {
                    backdropLayer(image, size: proxy.size)
                }

                if selectedAssetID == CleaningPageID.groupCompletion {
                    Color.black.opacity(0.48)
                }

                if let targetID = backdropTransition.targetID {
                    if targetID == CleaningPageID.groupCompletion {
                        Color.black.opacity(0.48 * backdropTransition.progress)
                    } else if let targetImage = backdropImages[targetID] {
                        backdropLayer(targetImage, size: proxy.size)
                            .opacity(backdropTransition.progress)
                    }
                }

                Color.black.opacity(0.34)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .task(id: selectedAssetID) {
            guard let index = currentIndex else { return }
            loadBackdropImages(around: index)
        }
        .onChange(of: backdropTransition.targetID) { _, targetID in
            guard let targetID,
                  let index = manager.sessionAssets.firstIndex(where: { $0.localIdentifier == targetID }) else { return }
            requestBackdrop(for: manager.sessionAssets[index])
        }
    }

    private func backdropLayer(_ image: UIImage, size: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .scaleEffect(1.18)
            .blur(radius: 54, opaque: true)
    }

    private func loadBackdropImages(around index: Int) {
        let lower = max(index - 1, 0)
        let upper = min(index + 1, manager.sessionAssets.count - 1)
        guard lower <= upper else { return }
        for asset in manager.sessionAssets[lower...upper] {
            requestBackdrop(for: asset)
        }
    }

    private func requestBackdrop(for asset: PHAsset) {
        let identifier = asset.localIdentifier
        guard backdropImages[identifier] == nil, backdropImageRequestIDs[identifier] == nil else { return }
        let targetSize = CGSize(width: 160, height: 160)
        if let cached = AssetImagePipeline.shared.cachedImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill
        ) {
            backdropImages[identifier] = cached
            return
        }
        backdropImageRequestIDs[identifier] = AssetImagePipeline.shared.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill
        ) { image in
            backdropImages[identifier] = image
            backdropImageRequestIDs[identifier] = nil
        }
    }

    private func cancelBackdropRequests() {
        backdropImageRequestIDs.values.forEach(AssetImagePipeline.shared.cancel)
        backdropImageRequestIDs.removeAll()
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
            .buttonStyle(.plain)
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
            .buttonStyle(.plain)
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

// MARK: Gesture Stage

private struct CleaningCardStage: View {
    let assets: [PHAsset]
    @Binding var selectedAssetID: String
    @Binding var backdropTransition: BackdropTransition
    let settings: SettingsStore
    let hapticsEnabled: Bool
    let hasNextGroup: Bool
    let isFavorite: (PHAsset) -> Bool
    let onDelete: (PHAsset, Int) -> Void
    let onToggleFavorite: (PHAsset, Int) -> Void
    let onNextGroup: () -> Void
    let onEnd: () -> Void

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

    private var currentPageIndex: Int? {
        if selectedAssetID == CleaningPageID.groupCompletion { return assets.count }
        return currentIndex
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
                ForEach(visiblePageIndices, id: \.self) { pageIndex in
                    let relation = pageIndex - (currentPageIndex ?? 0)
                    let isCurrent = relation == 0
                    Group {
                        if assets.indices.contains(pageIndex) {
                            CardView(asset: assets[pageIndex], isActive: isCurrent)
                                .equatable()
                                .overlay {
                                    if isCurrent { actionOverlay(for: assets[pageIndex]) }
                                }
                        } else {
                            GroupCompletionPage(
                                settings: settings,
                                hasNextGroup: hasNextGroup,
                                onNextGroup: onNextGroup,
                                onEnd: onEnd
                            )
                        }
                    }
                        .scaleEffect(cardScale(relation: relation, verticalProgress: verticalProgress))
                        .offset(
                            x: CGFloat(relation) * pageWidth + horizontalDrag,
                            y: cardVerticalOffset(relation: relation, progress: verticalProgress)
                        )
                        .zIndex(isCurrent ? 10 : Double(4 - abs(relation)))
                        .accessibilityHidden(!isCurrent)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(reviewGesture(in: proxy.size))
        }
        .padding(.bottom, 4)
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

    private var visiblePageIndices: [Int] {
        guard let currentPageIndex else { return [] }
        let lower = max(0, currentPageIndex - 1)
        let upper = min(assets.count, currentPageIndex + 1)
        return Array(lower...upper)
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
                        updateBackdropTransition(
                            horizontalTranslation: value.translation.width,
                            pageWidth: size.width + 18
                        )
                    case .vertical:
                        dragTranslation = CGSize(width: 0, height: value.translation.height)
                        backdropTransition = .idle
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
        guard let currentPageIndex else {
            resetGesture(animated: true)
            return
        }
        let destination = currentPageIndex + direction
        guard (0...assets.count).contains(destination) else {
            resetGesture(animated: true)
            boundaryHaptic()
            return
        }

        isTransitioning = true
        let destinationID = pageID(at: destination)
        if backdropTransition.targetID != destinationID {
            backdropTransition = BackdropTransition(
                sourceID: selectedAssetID,
                targetID: destinationID,
                progress: 0
            )
        }
        withAnimation(navigationSpring) {
            dragTranslation = CGSize(width: -CGFloat(direction) * pageWidth, height: 0)
            backdropTransition.progress = 1
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
            nextID = CleaningPageID.groupCompletion
        }

        let startOffset = cardVerticalOffset(relation: 0, progress: 1)
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isTransitioning = true
            isDeleting = true
            dragTranslation = CGSize(width: 0, height: startOffset)
            backdropTransition = BackdropTransition(
                sourceID: asset.localIdentifier,
                targetID: nextID,
                progress: 0
            )
        }
        withAnimation(.easeOut(duration: 0.24)) {
            dragTranslation = CGSize(width: 0, height: -max(canvasSize.height * 1.18, 760))
            backdropTransition.progress = 1
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
        backdropTransition = .idle
    }

    private func updateBackdropTransition(horizontalTranslation: CGFloat, pageWidth: CGFloat) {
        guard let currentPageIndex, horizontalTranslation != 0 else {
            backdropTransition = .idle
            return
        }
        let direction = horizontalTranslation < 0 ? 1 : -1
        let destination = currentPageIndex + direction
        guard (0...assets.count).contains(destination) else {
            backdropTransition = .idle
            return
        }
        backdropTransition = BackdropTransition(
            sourceID: selectedAssetID,
            targetID: pageID(at: destination),
            progress: min(abs(horizontalTranslation) / max(pageWidth, 1), 1)
        )
    }

    private func pageID(at index: Int) -> String {
        assets.indices.contains(index) ? assets[index].localIdentifier : CleaningPageID.groupCompletion
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

private enum CleaningPageID {
    static let groupCompletion = "tidyalbum.group-completion"
}

private struct BackdropTransition: Equatable {
    var sourceID: String?
    var targetID: String?
    var progress: CGFloat

    static let idle = BackdropTransition(sourceID: nil, targetID: nil, progress: 0)
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

private struct GroupCompletionPage: View {
    @ObservedObject var settings: SettingsStore
    let hasNextGroup: Bool
    let onNextGroup: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: hasNextGroup ? "checkmark" : "flag.checkered")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 64, height: 64)
                .background(.primary.opacity(0.1), in: Circle())
            Text(settings.t(hasNextGroup ? "Group Finished" : "All Done"))
                .font(.title2.weight(.bold))
            if hasNextGroup {
                Text(settings.t("Continue with the next group?"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(settings.t("Next Group"), action: onNextGroup)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                Button(settings.t("Finish Session"), action: onEnd)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button(settings.t("Finish"), action: onEnd)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: 420, minHeight: 330)
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .padding(.horizontal, 24)
    }
}

private struct CleaningAssetInfoIsland: View {
    let asset: PHAsset?
    @ObservedObject var settings: SettingsStore
    let isFavorite: Bool

    @State private var placeName: String?
    @State private var assetFileSize: Int64?

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
