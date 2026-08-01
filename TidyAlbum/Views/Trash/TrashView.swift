import Photos
import SwiftUI

// MARK: - Pending Deletion Queue

struct TrashView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var detailsSelection: TrashAssetSelection?
    @State private var restoringAssetIDs: Set<String> = []

    // 💡 保持 Grid 布局稳定
    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 3)]

    var body: some View {
        NavigationStack {
            Group {
                if manager.trashBin.isEmpty { emptyState } else { queueContent }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .overlay {
                if manager.isDeleting {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
        .sheet(item: $detailsSelection) { selection in
            AssetDetailsView(asset: selection.asset, settings: settings)
                .id(selection.id)
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
    }

    // MARK: Content

    private var emptyState: some View {
        ContentUnavailableView(
            settings.t("Trash is Empty"),
            systemImage: "trash",
            description: Text(settings.t("Items marked for deletion appear here."))
        )
    }

    private var queueContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(manager.trashBin, id: \.localIdentifier) { asset in
                    TrashQueueItem(
                        asset: asset,
                        isRestoring: restoringAssetIDs.contains(asset.localIdentifier),
                        detailsLabel: settings.t("View Details"),
                        restoreLabel: settings.t("Restore"),
                        onDetails: { detailsSelection = TrashAssetSelection(asset: asset) },
                        onRestore: { restore(asset) }
                    )
                    // 💡 1. 给每个 Cell 指定唯一 ID，防止 Layout 复用错位
                    .id(asset.localIdentifier)
                    // 💡 2. 使用 transition 确保照片被移除时缩小淡出，后面的照片自然滑过来
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .equatable()
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            // 💡 3. 核心：只对 trashBin 数组变化开启轻量弹簧动画，保证前移平滑流畅！
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: manager.trashBin)
        }
    }

    // MARK: 高性能撤回逻辑

    private func restore(_ asset: PHAsset) {
        let identifier = asset.localIdentifier
        guard !restoringAssetIDs.contains(identifier) else { return }

        // 标记正在撤回
        restoringAssetIDs.insert(identifier)

        // 💡 离开当前帧，触发微量的缩放淡出，随后将数据从 TrashBin 中移除，激发 LazyVGrid 补位动画
        withAnimation(.easeOut(duration: 0.15)) {
            _ = restoringAssetIDs.insert(identifier)
        }

        Task { @MainActor in
            // 稍作微小延迟让淡出动画完成
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            
            // 💡 在 spring 动画上下文中从数据源中剔除，引发后面的 Cell 自动前移动画
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                manager.restoreFromTrash(asset)
                restoringAssetIDs.remove(identifier)
            }
        }
    }

    // MARK: Actions & Title Navigation Bar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .accessibilityLabel(settings.t("Close"))
        }
        
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(settings.t("Trash"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                if !manager.trashBin.isEmpty {
                    let formattedBytes = ByteCountFormatter.string(fromByteCount: manager.pendingDeletionBytes, countStyle: .file)
                    Text("\(manager.trashBin.count) \(settings.t("Items")) • \(formattedBytes)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        manager.restoreAllFromTrash()
                    }
                } label: {
                    Label(settings.t("Restore All"), systemImage: "arrow.uturn.backward")
                }
                .tint(.primary)
                .disabled(manager.trashBin.isEmpty || manager.isDeleting)

                Button(role: .destructive) {
                    Task { await manager.emptyTrash() }
                } label: {
                    Label {
                        Text(settings.t("Delete All"))
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
                .tint(.red)
                .disabled(manager.trashBin.isEmpty || manager.isDeleting)

            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .disabled(manager.trashBin.isEmpty)
        }
    }
}

// MARK: - Item View

private struct TrashQueueItem: View, Equatable {
    let asset: PHAsset
    let isRestoring: Bool
    let detailsLabel: String
    let restoreLabel: String
    let onDetails: () -> Void
    let onRestore: () -> Void

    static func == (lhs: TrashQueueItem, rhs: TrashQueueItem) -> Bool {
        lhs.asset.localIdentifier == rhs.asset.localIdentifier &&
            lhs.isRestoring == rhs.isRestoring &&
            lhs.detailsLabel == rhs.detailsLabel &&
            lhs.restoreLabel == rhs.restoreLabel
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button(action: onDetails) {
                AssetMediaView(asset: asset, contentMode: .fill)
                    .aspectRatio(1, contentMode: .fill)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRestoring)
            .accessibilityLabel(detailsLabel)

            Button(action: onRestore) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRestoring)
            .accessibilityLabel(restoreLabel)
        }
        .opacity(isRestoring ? 0 : 1)
        .scaleEffect(isRestoring ? 0.8 : 1)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct TrashAssetSelection: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}
