import Photos
import SwiftUI

// MARK: - Pending Deletion Queue

struct TrashView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var showsDeleteConfirmation = false
    @State private var detailsSelection: TrashAssetSelection?
    @State private var restoringAssetIDs: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 3)]

    var body: some View {
        NavigationStack {
            Group {
                if manager.trashBin.isEmpty { emptyState } else { queueContent }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline) // 保持居中布局
            .toolbar { toolbar }
            .overlay {
                if manager.isDeleting {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .sheet(item: $detailsSelection) { selection in
            AssetDetailsView(asset: selection.asset, settings: settings)
                .id(selection.id)
        }
        .confirmationDialog(
            settings.t("Delete from Photos?"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(settings.t("Delete All"), role: .destructive) {
                Task { await manager.emptyTrash() }
            }
            Button(settings.t("Cancel"), role: .cancel) {}
        } message: {
            Text(settings.t("These items will move to Recently Deleted in Photos."))
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
            // 移除了原先的 queueSummary 区域，让照片直接顶上
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
                    .equatable()
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
    }

    private func restore(_ asset: PHAsset) {
        let identifier = asset.localIdentifier
        guard !restoringAssetIDs.contains(identifier) else { return }
        _ = withAnimation(.easeOut(duration: 0.14)) {
            restoringAssetIDs.insert(identifier)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                manager.restoreFromTrash(asset)
                restoringAssetIDs.remove(identifier)
            }
        }
    }

    // MARK: Actions & Title Navigation Bar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // 左边关闭按钮
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .accessibilityLabel(settings.t("Close"))
        }
        
        // 中间自定义标题（“待删除” + 数量与体积）
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

        // 右边三个点菜单
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        manager.restoreAllFromTrash()
                    }
                } label: {
                    Label(settings.t("Restore All"), systemImage: "arrow.uturn.backward")
                }
                .tint(.primary)
                .disabled(manager.trashBin.isEmpty || manager.isDeleting)

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label {
                        Text(settings.t("Delete All"))
                    } icon: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
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
        .scaleEffect(isRestoring ? 0.96 : 1)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct TrashAssetSelection: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}
