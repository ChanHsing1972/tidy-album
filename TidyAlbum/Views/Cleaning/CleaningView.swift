import Photos
import SwiftUI
import UIKit

// MARK: - Cleaning Session

struct CleaningView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var offset: CGSize = .zero
    @State private var isDragging = false
    @State private var thresholdHapticSent = false
    @State private var detailsAsset: PHAsset?
    @State private var showsDetails = false
    @State private var showsTrash = false

    private let swipeThreshold: CGFloat = 96
    private let flyDistance: CGFloat = 900
    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)

    private var currentAsset: PHAsset? {
        guard manager.sessionAssets.indices.contains(index) else { return nil }
        return manager.sessionAssets[index]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background
                if manager.sessionAssets.isEmpty {
                    emptyState
                } else if currentAsset == nil {
                    finishedState
                } else {
                    reviewSurface
                }
            }
            .navigationTitle(settings.t("Clean"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .sheet(isPresented: $showsDetails) {
            if let detailsAsset {
                AssetDetailsView(asset: detailsAsset, settings: settings)
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
            index = 0
            manager.preheat(around: index)
            if let asset = currentAsset { manager.recordViewed(asset) }
        }
    }

    // MARK: Background and Toolbar

    @ViewBuilder private var background: some View {
        if let asset = currentAsset {
            AssetMediaView(asset: asset, contentMode: .fill, showsVideoBadge: false)
                .blur(radius: 44)
                .opacity(0.2)
                .ignoresSafeArea()
        } else {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        }
    }

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
                VStack(spacing: 3) {
                    Text("\(min(index + 1, manager.sessionAssets.count)) / \(manager.sessionAssets.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                    ProgressView(value: Double(min(index, manager.sessionAssets.count)), total: Double(manager.sessionAssets.count))
                        .frame(width: 108)
                        .tint(.blue)
                }
                .accessibilityElement(children: .combine)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showsTrash = true } label: {
                Image(systemName: manager.trashBin.isEmpty ? "trash" : "trash.fill")
            }
            .badge(manager.trashBin.count)
            .accessibilityLabel(settings.t("Trash"))
        }
    }

    // MARK: Review Surface

    private var reviewSurface: some View {
        GeometryReader { proxy in
            ZStack {
                if index + 1 < manager.sessionAssets.count {
                    CardView(asset: manager.sessionAssets[index + 1])
                        .scaleEffect(0.94 + min(verticalProgress * 0.04, 0.04))
                        .offset(y: 18 - min(verticalProgress * 18, 18))
                        .opacity(0.72 + min(verticalProgress * 0.28, 0.28))
                }
                if let asset = currentAsset {
                    CardView(asset: asset)
                        .offset(offset)
                        .rotationEffect(.degrees(Double(offset.width / 22)))
                        .scaleEffect(isDragging ? 0.98 : 1)
                        .overlay(actionOverlay)
                        .gesture(dragGesture(container: proxy.size))
                        .id(asset.localIdentifier)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private var verticalProgress: CGFloat {
        min(abs(offset.height) / 180, 1)
    }

    private var actionOverlay: some View {
        let isUp = offset.height < 0 && abs(offset.height) > abs(offset.width)
        let isDown = offset.height > 0 && abs(offset.height) > abs(offset.width)
        let progress = min(abs(offset.height) / 150, 1)
        return ZStack {
            Image(systemName: "trash.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white)
                .padding(22)
                .background(.red, in: Circle())
                .scaleEffect(0.72 + progress * 0.38)
                .opacity(isUp ? progress : 0)
            Image(systemName: "heart.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white)
                .padding(22)
                .background(.pink, in: Circle())
                .scaleEffect(0.72 + progress * 0.38)
                .opacity(isDown ? progress : 0)
        }
        .animation(.easeOut(duration: 0.12), value: isUp)
        .animation(.easeOut(duration: 0.12), value: isDown)
    }

    // MARK: Gesture Handling

    private func dragGesture(container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                isDragging = true
                offset = value.translation
                let vertical = abs(value.translation.height) > abs(value.translation.width)
                let crossed = vertical && abs(value.translation.height) >= swipeThreshold
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
                isDragging = false
                thresholdHapticSent = false
                let translation = value.translation
                if abs(translation.width) > abs(translation.height), abs(translation.width) >= swipeThreshold {
                    browseHorizontally(direction: translation.width < 0 ? 1 : -1, width: container.width)
                } else if translation.height <= -swipeThreshold {
                    commitDelete()
                } else if translation.height >= swipeThreshold {
                    commitFavorite()
                } else {
                    withAnimation(spring) { offset = .zero }
                }
            }
    }

    private func browseHorizontally(direction: Int, width: CGFloat) {
        let target = index + direction
        guard manager.sessionAssets.indices.contains(target) else {
            withAnimation(spring) { offset = .zero }
            return
        }
        withAnimation(spring) { offset.width = CGFloat(-direction) * min(width, 520) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            index = target
            offset = CGSize(width: CGFloat(direction) * 26, height: 0)
            manager.recordViewed(manager.sessionAssets[index])
            manager.preheat(around: index)
            withAnimation(spring) { offset = .zero }
        }
    }

    private func commitDelete() {
        guard let asset = currentAsset else { return }
        withAnimation(spring) { offset = CGSize(width: 0, height: -flyDistance) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            manager.markForDeletion(asset, at: index)
            advance()
        }
    }

    private func commitFavorite() {
        guard let asset = currentAsset else { return }
        withAnimation(spring) { offset = CGSize(width: 0, height: flyDistance) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            manager.markFavorite(asset, at: index)
            advance()
        }
    }

    private func advance() {
        index += 1
        offset = .zero
        if index < manager.sessionAssets.count {
            manager.recordViewed(manager.sessionAssets[index])
            manager.preheat(around: index)
        }
    }

    // MARK: Bottom Controls

    private var bottomBar: some View {
        HStack {
            Button {
                Task {
                    if let restoredIndex = await manager.undoLastAction() {
                        index = min(restoredIndex, max(manager.sessionAssets.count - 1, 0))
                        offset = .zero
                    }
                }
            } label: {
                Label(settings.t("Undo"), systemImage: "arrow.uturn.backward")
            }
            .disabled(!manager.canUndo)

            Spacer()

            Button {
                if let asset = currentAsset {
                    detailsAsset = asset
                    showsDetails = true
                }
            } label: {
                Label(settings.t("Details"), systemImage: "info.circle")
            }
            .disabled(currentAsset == nil)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
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
    }
}
