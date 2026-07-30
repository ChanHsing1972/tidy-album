import Photos
import SwiftUI

// MARK: - Pending Deletion Queue

struct TrashView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsDeleteConfirmation = false

    private let columns = [GridItem(.adaptive(minimum: 112), spacing: 3)]

    var body: some View {
        NavigationStack {
            Group {
                if manager.trashBin.isEmpty {
                    ContentUnavailableView(
                        settings.t("Trash"),
                        systemImage: "trash",
                        description: Text(settings.t("No items in this collection"))
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(manager.trashBin, id: \.localIdentifier) { asset in
                                queueItem(asset)
                            }
                        }
                    }
                }
            }
            .navigationTitle(settings.t("Trash"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(settings.t("Close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            manager.restoreAllFromTrash()
                        } label: {
                            Label(settings.t("Restore All"), systemImage: "arrow.uturn.backward")
                        }
                        Button(role: .destructive) {
                            showsDeleteConfirmation = true
                        } label: {
                            Label(settings.t("Delete All"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(manager.trashBin.isEmpty)
                }
            }
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
    }

    private func queueItem(_ asset: PHAsset) -> some View {
        ZStack(alignment: .bottomTrailing) {
            AssetMediaView(asset: asset, contentMode: .fill)
                .aspectRatio(1, contentMode: .fill)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    manager.restoreFromTrash(asset)
                }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .padding(8)
            }
            .accessibilityLabel(settings.t("Restore"))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
