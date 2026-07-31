import Photos
import SwiftUI
import UIKit

// MARK: - Cleaning Session

struct CleaningView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    var onFinish: (() -> Void)?

    // MARK: Scroll & Drag State

    @State private var currentVisibleID: String?
    @State private var verticalOffset: CGFloat = 0
    @State private var isDraggingVertical = false
    @State private var thresholdHapticSent = false
    @State private var detailsAsset: PHAsset?
    @State private var showsDetails = false
    @State private var showsTrash = false
    @State private var gestureLockDirection: GestureDirection? = nil

    private enum GestureDirection {
        case horizontal
        case vertical
    }

    // MARK: Background Crossfade

    @State private var bgPreviousID: String?
    @State private var bgCurrentID: String?
    @State private var bgPreviousOpacity: Double = 0
    @State private var bgCurrentOpacity: Double = 0.65

    /// Tracks whether the session had photos at any point, to distinguish
    /// "empty from the start" vs "all photos reviewed/deleted".
    @State private var sessionHadPhotos = false

    private let swipeThreshold: CGFloat = 96
    private let flyDistance: CGFloat = 900
    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)

    // MARK: Computed

    private var currentIndex: Int {
        guard let id = currentVisibleID else { return 0 }
        return manager.sessionAssets.firstIndex(where: { $0.localIdentifier == id }) ?? 0
    }

    private var currentAsset: PHAsset? {
        guard let id = currentVisibleID else { return manager.sessionAssets.first }
        return manager.sessionAssets.first(where: { $0.localIdentifier == id })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundLayer
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.5), value: bgCurrentID)

                if manager.sessionAssets.isEmpty && !sessionHadPhotos {
                    emptyState
                } else if manager.sessionAssets.isEmpty && sessionHadPhotos {
                    finishedState
                } else {
                    VStack(spacing: 0) {
                        cardScrollView
                        bottomBar
                            .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle(settings.t("Clean"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .sheet(isPresented: $showsDetails) {
            if let detailsAsset {
                AssetDetailsView(asset: detailsAsset, settings: settings)
                    .id(detailsAsset.localIdentifier)
            }
        }
        .sheet(isPresented: $showsTrash) {
            TrashView(manager: manager, settings: settings)
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
        .onAppear {
            sessionHadPhotos = !manager.sessionAssets.isEmpty
            currentVisibleID = manager.sessionAssets.first?.localIdentifier
            updateBackground(for: currentVisibleID)
            if let asset = currentAsset { manager.recordViewed(asset) }
        }
        .onChange(of: currentVisibleID) { _, newID in
            updateBackground(for: newID)
            if let id = newID,
               let idx = manager.sessionAssets.firstIndex(where: { $0.localIdentifier == id }) {
                manager.recordViewed(manager.sessionAssets[idx])
                manager.preheat(around: idx)
            }
        }
    }

    // MARK: Background with Crossfade

    @ViewBuilder
    private var backgroundLayer: some View {
        ZStack {
            Color.black
            // Previous background (fading out)
            if let prevID = bgPreviousID, prevID != bgCurrentID {
                backgroundImage(for: prevID)
                    .opacity(bgPreviousOpacity)
            }
            // Current background (fading in)
            if let curID = bgCurrentID {
                backgroundImage(for: curID)
                    .opacity(bgCurrentOpacity)
            }
        }
    }

    private func backgroundImage(for identifier: String) -> some View {
        Group {
            if let asset = findAssetInSession(identifier) {
                AssetMediaView(asset: asset, contentMode: .fill, showsVideoBadge: false)
                    .blur(radius: 60)
                    .overlay(Color.black.opacity(0.35))
            }
        }
    }

    private func findAssetInSession(_ identifier: String) -> PHAsset? {
        manager.sessionAssets.first(where: { $0.localIdentifier == identifier })
    }

    private func updateBackground(for newID: String?) {
        guard let newID, newID != bgCurrentID else { return }

        // Start crossfade
        bgPreviousID = bgCurrentID
        withAnimation(.easeInOut(duration: 0.45)) {
            bgPreviousOpacity = 0
            bgCurrentOpacity = 0.65
        }

        bgCurrentID = newID

        // After animation, clean up previous
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            bgPreviousID = nil
            bgPreviousOpacity = 0
        }
    }

    // MARK: Card Scroll View

    private var cardScrollView: some View {
        GeometryReader { geometry in
            let cardWidth = geometry.size.width - 36
            let cardMaxHeight = geometry.size.height - 80

            TabView(selection: $currentVisibleID) {
                ForEach(Array(manager.sessionAssets.enumerated()), id: \.element.localIdentifier) { idx, asset in
                    cardView(asset: asset, at: idx, cardWidth: cardWidth, cardMaxHeight: cardMaxHeight)
                        .tag(asset.localIdentifier)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private func cardView(asset: PHAsset, at index: Int, cardWidth: CGFloat, cardMaxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            CardView(asset: asset)
                .frame(maxWidth: cardWidth, maxHeight: cardMaxHeight)
                .offset(y: verticalOffset)
                .overlay(actionOverlay)
                .simultaneousGesture(verticalDragGesture(for: asset, at: index))
        }
    }

    // MARK: Action Overlay

    private var actionOverlay: some View {
        let isUp = isDraggingVertical && verticalOffset < 0 && abs(verticalOffset) > 4
        let isDown = isDraggingVertical && verticalOffset > 0 && abs(verticalOffset) > 4
        let progress = min(abs(verticalOffset) / 150, 1)
        return ZStack {
            IconOverlayView(icon: "trash.fill", color: .red, progress: isUp ? progress : 0)
            IconOverlayView(icon: "heart.fill", color: .pink, progress: isDown ? progress : 0)
        }
        .animation(.easeOut(duration: 0.12), value: isUp)
        .animation(.easeOut(duration: 0.12), value: isDown)
    }

    // MARK: Vertical Drag Gesture

    private func verticalDragGesture(for asset: PHAsset, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                // Lock direction on first significant movement
                if gestureLockDirection == nil {
                    let h = abs(value.translation.width)
                    let v = abs(value.translation.height)
                    if max(h, v) > 20 {
                        gestureLockDirection = h > v ? .horizontal : .vertical
                    }
                    // If still undecided, don't react yet
                    if gestureLockDirection == nil { return }
                }

                // If locked to horizontal, let TabView handle it
                guard gestureLockDirection == .vertical else { return }

                isDraggingVertical = true
                verticalOffset = value.translation.height

                let crossed = abs(value.translation.height) >= swipeThreshold
                if crossed && !thresholdHapticSent {
                    thresholdHapticSent = true
                    guard settings.hapticsEnabled else { return }
                    let generator = UIImpactFeedbackGenerator(style: value.translation.height < 0 ? .heavy : .light)
                    generator.prepare()
                    generator.impactOccurred()
                } else if !crossed {
                    thresholdHapticSent = false
                }
            }
            .onEnded { value in
                defer {
                    gestureLockDirection = nil
                    isDraggingVertical = false
                    thresholdHapticSent = false
                }

                // If locked to horizontal, nothing to do
                guard gestureLockDirection == .vertical else { return }

                if value.translation.height <= -swipeThreshold {
                    commitDelete(asset: asset, at: index)
                } else if value.translation.height >= swipeThreshold {
                    commitFavorite(asset: asset, at: index)
                } else {
                    withAnimation(spring) { verticalOffset = 0 }
                }
            }
    }

    private func commitDelete(asset: PHAsset, at index: Int) {
        withAnimation(spring) { verticalOffset = -flyDistance }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            // Move to next item before removing current one from the session
            let nextID = manager.sessionAssets[safe: index + 1]?.localIdentifier
            if let nextID {
                currentVisibleID = nextID
            }
            manager.markForDeletion(asset, at: index)
            verticalOffset = 0
        }
    }

    private func commitFavorite(asset: PHAsset, at index: Int) {
        withAnimation(spring) { verticalOffset = flyDistance }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            manager.markFavorite(asset, at: index)
            verticalOffset = 0
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel(settings.t("Close"))
        }
        ToolbarItem(placement: .principal) {
            if !manager.sessionAssets.isEmpty {
                progressIndicator
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showsTrash = true } label: {
                Image(systemName: manager.trashBin.isEmpty ? "trash" : "trash.fill")
            }
            .badge(manager.trashBin.count)
            .id("trash-btn-\(manager.trashBin.count)")
            .accessibilityLabel(settings.t("Trash"))
        }
    }

    private var progressIndicator: some View {
        let mode = settings.progressDisplayMode
        let current = min(currentIndex + 1, manager.sessionAssets.count)
        let total = manager.sessionAssets.count

        return Group {
            if mode == .textOnly {
                Text("\(current) / \(total)")
                    .font(.caption.monospacedDigit().weight(.semibold))
            } else if mode == .barOnly {
                ProgressView(value: Double(currentIndex + 1), total: Double(total))
                    .frame(width: 108)
                    .tint(.blue)
            } else {
                VStack(spacing: 3) {
                    Text("\(current) / \(total)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                    ProgressView(value: Double(currentIndex + 1), total: Double(total))
                        .frame(width: 108)
                        .tint(.blue)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Bottom Bar (Transparent Floating)

    private var bottomBar: some View {
        HStack(spacing: 0) {
            // Undo
            Button {
                Task {
                    if let restoredIndex = await manager.undoLastAction() {
                        currentVisibleID = manager.sessionAssets[safe: restoredIndex]?.localIdentifier
                        verticalOffset = 0
                    }
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .disabled(!manager.canUndo)
            .opacity(manager.canUndo ? 1 : 0.35)

            Spacer()

            // Liquid Glass Capsule Info Island
            if let asset = currentAsset {
                infoCapsule(asset: asset)
            }

            Spacer()

            // Details
            Button {
                if let asset = currentAsset {
                    detailsAsset = asset
                    showsDetails = true
                }
            } label: {
                Image(systemName: "info.circle")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .disabled(currentAsset == nil)
            .opacity(currentAsset == nil ? 0.35 : 1)
        }
        .padding(.horizontal, 20)
    }

    private func infoCapsule(asset: PHAsset) -> some View {
        HStack(spacing: 8) {
            if let date = asset.creationDate {
                Text(date, style: .date)
                    .font(.caption2.weight(.medium))
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("\(asset.pixelWidth)×\(asset.pixelHeight)")
                .font(.caption2.weight(.medium))
            if asset.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.pink)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        }
    }

    // MARK: States

    private var emptyState: some View {
        ContentUnavailableView(
            settings.t("No items in this collection"),
            systemImage: "photo.on.rectangle.angled",
            description: Text(settings.t("Review another collection"))
        )
    }

    private var finishedState: some View {
        ContentUnavailableView(
            settings.t("Review complete"),
            systemImage: "checkmark.circle.fill",
            description: Text(settings.t("You reviewed every item in this session."))
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                dismiss()
                onFinish?()
            }
        }
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}