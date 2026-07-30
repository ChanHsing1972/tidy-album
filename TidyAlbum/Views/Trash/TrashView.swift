import SwiftUI
import Photos

// MARK: - 垃圾桶视图 (Trash View)
/// 以网格形式展示待删除的照片，支持逐张恢复、一键恢复全部和清空垃圾桶。
struct TrashView: View {

    // MARK: 依赖

    @ObservedObject var manager: PhotoManager
    @Environment(\.dismiss) private var dismiss

    // MARK: 布局

    private let columns = [
        GridItem(.adaptive(minimum: DesignTokens.Dimensions.gridMinimumColumnWidth), spacing: 2)
    ]

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                DesignTokens.Colors.appBackground.ignoresSafeArea()

                if manager.trashBin.isEmpty {
                    emptyState
                } else {
                    gridContent
                }
            }
            .navigationTitle("Trash Bin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarLeading
                toolbarTrailing
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 空状态 (Empty State)

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.large) {
            Image(systemName: "trash")
                .font(DesignTokens.Typography.trashIcon)
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Text("Trash is Empty")
                .font(.title2)
                .foregroundColor(DesignTokens.Colors.textPrimary)
        }
    }

    // MARK: - 网格内容 (Grid Content)

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(manager.trashBin, id: \.localIdentifier) { asset in
                    trashGridItem(asset)
                }
            }
        }
    }

    /// 单个垃圾桶网格项
    private func trashGridItem(_ asset: PHAsset) -> some View {
        ZStack(alignment: .bottomTrailing) {
            AssetMediaView(asset: asset)
                .aspectRatio(1, contentMode: .fill)
                .clipped()

            Button {
                withAnimation {
                    manager.restoreFromTrash(asset: asset)
                }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(DesignTokens.Typography.controlIcon)
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .padding(4)
            }
        }
    }

    // MARK: - 工具栏 (Toolbar)

    @ToolbarContentBuilder
    private var toolbarLeading: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Close") { dismiss() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarTrailing: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if !manager.trashBin.isEmpty {
                Menu {
                    Button(role: .destructive) {
                        manager.emptyTrash()
                    } label: {
                        Label("Empty Trash", systemImage: "trash")
                    }

                    Button {
                        manager.restoreAllFromTrash()
                    } label: {
                        Label("Restore All", systemImage: "arrow.uturn.backward")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}