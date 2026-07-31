import Photos
import SwiftUI
import UIKit

struct CleaningView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    var onFinish: (() -> Void)?

    @State private var selectedAssetID = ""
    @State private var dragTranslation = CGSize.zero
    @State private var dragAxis: DragAxis = .undetermined
    @State private var thresholdHapticSent = false
    @State private var flyingCards: [FlyingCard] = []
    @State private var detailsSelection: AssetSheetSelection?
    @State private var showsTrash = false
    @State private var activityItems: ActivityItems?
    @State private var isPreparingShare = false
    @State private var isUndoing = false
    @State private var showsShareError = false
    @State private var backdropImage: UIImage?
    @State private var backdropImageRequestID: PHImageRequestID?
    @State private var topSafeArea: CGFloat = 0

    private let actionThreshold: CGFloat = 92
    private let navigationSpring = Animation.spring(duration: 0.44, bounce: 0.16)
    private let returnSpring = Animation.spring(duration: 0.38, bounce: 0.22)

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
                    .frame(
                        width: UIScreen.main.bounds.width,
                        height: UIScreen.main.bounds.height
                    )
                    .position(
                        x: UIScreen.main.bounds.width / 2,
                        y: UIScreen.main.bounds.height / 2
                    )
                if manager.sessionAssets.isEmpty {
                    if manager.sessionGroupNumber == 0 {
                        emptyState
                    } else {
                        completionBridge
                    }
                } else {
                    cardStage
                }
            }
            .ignoresSafeArea()
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { topSafeArea = proxy.safeAreaInsets.top }
                }
            )
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .bottomBar)
            .toolbar { toolbar }
        }
        .onAppear { selectInitialAsset() }
        .sheet(item: $detailsSelection) { selection in
            AssetDetailsView(asset: selection.asset, settings: settings).id(selection.id)
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
        .onChange(of: selectedAssetID) { _, identifier in
            guard let index = manager.sessionAssets.firstIndex(where: { $0.localIdentifier == identifier }) else {
                return
            }
            manager.recordViewed(manager.sessionAssets[index])
            manager.preheat(around: index)
        }
        .onChange(of: manager.sessionAssets.map(\.localIdentifier)) { _, identifiers in
            guard !identifiers.isEmpty, !identifiers.contains(selectedAssetID) else {
                return
            }
            selectedAssetID = identifiers[0]
        }
    }

    private var backdrop: some View {
        ZStack {
            Color.black
            if let backdropImage {
                Image(uiImage: backdropImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1.16)
                    .blur(radius: 54, opaque: true)
                    .transition(.opacity.animation(.easeInOut(duration: 0.52)))
            }
            Color.black.opacity(0.34)
        }
        .animation(.easeInOut(duration: 0.52), value: backdropImage)
        .clipped()
        .allowsHitTesting(false)
        .onAppear { loadBackdropImage() }
        .onChange(of: selectedAssetID) { _, _ in loadBackdropImage() }
    }

    private func loadBackdropImage() {
        AssetImagePipeline.shared.cancel(backdropImageRequestID)
        guard let currentAsset else { return }
        let screenSize = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: screenSize.width * scale / 3, height: screenSize.height * scale / 3)
        if let cached = AssetImagePipeline.shared.cachedImage(
            for: currentAsset,
            targetSize: targetSize,
            contentMode: .aspectFill
        ) {
            backdropImage = cached
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let requestedID = currentAsset.localIdentifier
        backdropImageRequestID = PHImageManager.default().requestImage(
            for: currentAsset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let image, requestedID == currentAsset.localIdentifier else { return }
            DispatchQueue.main.async {
                guard requestedID == currentAsset.localIdentifier else { return }
                backdropImage = image
            }
        }
    }

    private var cardStage: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width + 18
            let verticalProgress = min(abs(dragTranslation.height) / actionThreshold, 1)
            ZStack {
                ForEach(visibleAssets, id: \.localIdentifier) { asset in
                    let relation = relation(of: asset)
                    let isCurrent = relation == 0
                    CardView(
                        asset: asset,
                        isActive: isCurrent && dragAxis != .vertical,
                        isFavorite: manager.isFavorite(asset)
                    )
                    .overlay {
                        if isCurrent { actionOverlay }
                    }
                    .scaleEffect(cardScale(relation: relation, verticalProgress: verticalProgress))
                    .offset(
                        x: CGFloat(relation) * pageWidth + horizontalDrag,
                        y: cardVerticalOffset(relation: relation, progress: verticalProgress)
                    )
                    .opacity(flyingCards.contains(where: { $0.asset.localIdentifier == asset.localIdentifier }) ? 0 : 1)
                    .zIndex(relation == 0 ? 10 : Double(4 - abs(relation)))
                    .accessibilityHidden(!isCurrent)
                }
                ForEach(flyingCards) { card in
                    FlyingCardView(card: card, canvasSize: proxy.size) {
                        flyingCards.removeAll { $0.id == card.id }
                    }
                    .zIndex(20)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(reviewGesture(in: proxy.size))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var visibleAssets: [PHAsset] {
        guard let currentIndex else { return [] }
        let lower = max(0, currentIndex - 1)
        let upper = min(manager.sessionAssets.count - 1, currentIndex + 1)
        return Array(manager.sessionAssets[lower...upper])
    }

    private func relation(of asset: PHAsset) -> Int {
        guard let currentIndex,
              let index = manager.sessionAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier })
        else { return 0 }
        return index - currentIndex
    }

    private var horizontalDrag: CGFloat {
        dragAxis == .horizontal ? dragTranslation.width : 0
    }

    private func cardVerticalOffset(relation: Int, progress: CGFloat) -> CGFloat {
        if relation == 0, dragAxis == .vertical {
            let value = dragTranslation.height
            let magnitude = abs(value)
            let resisted = magnitude <= actionThreshold
                ? magnitude
                : actionThreshold + (magnitude - actionThreshold) * 0.72
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
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                if dragAxis == .undetermined {
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    guard max(horizontal, vertical) > 8 else { return }
                    dragAxis = vertical > horizontal * 1.15 ? .vertical : .horizontal
                }
                dragTranslation = value.translation
                if dragAxis == .vertical { updateHaptic(for: value.translation.height) }
            }
            .onEnded { value in
                let resolvedAxis = dragAxis
                thresholdHapticSent = false
                switch resolvedAxis {
                case .vertical:
                    finishVerticalGesture(value, canvasSize: size)
                case .horizontal:
                    finishHorizontalGesture(value, pageWidth: size.width + 18)
                case .undetermined:
                    resetGesture()
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
            withAnimation(returnSpring) { resetGesture() }
            return
        }
        guard let currentIndex else {
            withAnimation(returnSpring) { resetGesture() }
            return
        }
        let destination = currentIndex + direction
        guard manager.sessionAssets.indices.contains(destination) else {
            withAnimation(returnSpring) { resetGesture() }
            boundaryHaptic()
            return
        }
        withAnimation(navigationSpring) {
            selectedAssetID = manager.sessionAssets[destination].localIdentifier
            resetGesture()
        }
    }

    private func finishVerticalGesture(_ value: DragGesture.Value, canvasSize: CGSize) {
        let projected = value.predictedEndTranslation.height
        let actual = value.translation.height
        let shouldCommit = abs(actual) >= actionThreshold || abs(projected) >= actionThreshold * 1.35
        guard shouldCommit else {
            withAnimation(returnSpring) { resetGesture() }
            return
        }
        commitVerticalAction(direction: projected == 0 ? actual : projected)
    }

    private func commitVerticalAction(direction: CGFloat) {
        guard let asset = currentAsset, let index = currentIndex else {
            withAnimation(returnSpring) { resetGesture() }
            return
        }
        let isDeletion = direction < 0
        let nextIndex = index + 1
        let hasNext = manager.sessionAssets.indices.contains(nextIndex)
        if !isDeletion, !hasNext {
            manager.markFavorite(asset, at: index)
            withAnimation(returnSpring) { resetGesture() }
            return
        }
        let nextID: String
        if hasNext {
            nextID = manager.sessionAssets[nextIndex].localIdentifier
        } else if index > 0 {
            nextID = manager.sessionAssets[index - 1].localIdentifier
        } else {
            nextID = ""
        }
        let projectedDelta = valueVelocityEstimate(current: dragTranslation.height, projected: direction)
        flyingCards.append(
            FlyingCard(
                asset: asset,
                startOffset: CGSize(width: 0, height: cardVerticalOffset(relation: 0, progress: 1)),
                direction: isDeletion ? -1 : 1,
                initialVelocity: projectedDelta
            )
        )
        withAnimation(navigationSpring) {
            if isDeletion {
                manager.markForDeletion(asset, at: index)
            } else {
                manager.markFavorite(asset, at: index)
            }
            selectedAssetID = nextID
            resetGesture()
        }
    }

    private func valueVelocityEstimate(current: CGFloat, projected: CGFloat) -> CGFloat {
        min(max(abs(projected - current) / 180, 0.8), 5.5)
    }

    private func resetGesture() {
        dragTranslation = .zero
        dragAxis = .undetermined
    }

    private func updateHaptic(for translation: CGFloat) {
        let crossed = abs(translation) >= actionThreshold
        if crossed, !thresholdHapticSent {
            thresholdHapticSent = true
            guard settings.hapticsEnabled else { return }
            UIImpactFeedbackGenerator(style: translation < 0 ? .rigid : .soft).impactOccurred()
        } else if !crossed {
            thresholdHapticSent = false
        }
    }

    private func boundaryHaptic() {
        guard settings.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
    }

    private var actionOverlay: some View {
        let progress = min(abs(dragTranslation.height) / 150, 1)
        return ZStack {
            IconOverlayView(
                icon: "trash.fill",
                color: .red,
                progress: dragAxis == .vertical && dragTranslation.height < 0 ? progress : 0
            )
            IconOverlayView(
                icon: (currentAsset.map { manager.isFavorite($0) } ?? false) ? "heart.slash.fill" : "heart.fill",
                color: .pink,
                progress: dragAxis == .vertical && dragTranslation.height > 0 ? progress : 0
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: exitSession) {
                Image(systemName: "xmark").contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.t("Close"))
        }
        ToolbarItem(placement: .principal) { sessionProgress }
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
            Button { undo() } label: {
                Group {
                    if isUndoing { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.uturn.backward").font(.body.weight(.semibold)) }
                }
                .contentShape(Circle())
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
                .contentShape(Circle())
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
                resetGesture()
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
        manager.endSession()
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
        Color.clear.task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, manager.sessionAssets.isEmpty else { return }
            dismiss()
            onFinish?()
        }
    }

    private func selectInitialAsset() {
        guard selectedAssetID.isEmpty, let first = manager.sessionAssets.first else { return }
        selectedAssetID = first.localIdentifier
    }
}

private enum DragAxis { case undetermined, horizontal, vertical }

private struct FlyingCard: Identifiable {
    let id = UUID()
    let asset: PHAsset
    let startOffset: CGSize
    let direction: CGFloat
    let initialVelocity: CGFloat
}

private struct FlyingCardView: View {
    let card: FlyingCard
    let canvasSize: CGSize
    let completion: () -> Void
    @State private var offset: CGSize
    @State private var scale: CGFloat = 0.99
    @State private var opacity: CGFloat = 1

    init(card: FlyingCard, canvasSize: CGSize, completion: @escaping () -> Void) {
        self.card = card
        self.canvasSize = canvasSize
        self.completion = completion
        _offset = State(initialValue: card.startOffset)
    }

    var body: some View {
        CardView(asset: card.asset, isActive: false)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .scaleEffect(scale)
            .offset(offset)
            .opacity(opacity)
            .task {
                await Task.yield()
                withAnimation(.interpolatingSpring(mass: 0.72, stiffness: 92, damping: 13, initialVelocity: card.initialVelocity)) {
                    offset.height = card.direction * max(canvasSize.height * 1.35, 760)
                    scale = 0.94
                }
                withAnimation(.easeOut(duration: 0.3).delay(0.14)) { opacity = 0 }
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled else { return }
                completion()
            }
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
        .animation(.spring(duration: 0.42, bounce: 0.12), value: value)
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}
