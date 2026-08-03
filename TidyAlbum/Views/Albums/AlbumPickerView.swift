import Photos
import SwiftUI

struct AlbumPickerView: View {
    let asset: PHAsset
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore

    @Environment(\.dismiss) private var dismiss
    @State private var albums: [UserAlbumItem] = []
    @State private var isLoading = true
    @State private var busyAlbumID: String?
    @State private var showsNewAlbum = false
    @State private var newAlbumName = ""
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    selectedPhotoHeader
                    albumContent
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(settings.t("Choose Album"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("tidyalbum.album-picker")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.t("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newAlbumName = ""
                        showsNewAlbum = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(settings.t("New Album"))
                }
            }
        }
        .task { await loadAlbums() }
        .alert(settings.t("New Album"), isPresented: $showsNewAlbum) {
            TextField(settings.t("Album Name"), text: $newAlbumName)
            Button(settings.t("Cancel"), role: .cancel) {}
            Button(settings.t("Add")) { createAlbum() }
                .disabled(newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(
            settings.t("Unable to Add to Album"),
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )
        ) {
            Button(settings.t("Done"), role: .cancel) { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "")
        }
    }

    private var selectedPhotoHeader: some View {
        ZStack(alignment: .bottomLeading) {
            AssetMediaView(asset: asset, contentMode: .fill, showsVideoBadge: false)
                .frame(height: 148)
            Label(settings.t("Add to Album"), systemImage: "rectangle.stack.badge.plus")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(.regularMaterial, in: Capsule())
                .padding(14)
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder private var albumContent: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if albums.isEmpty {
            VStack(spacing: 20) {
                ContentUnavailableView(
                    settings.t("No Albums"),
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text(settings.t("Create an album to organize this photo."))
                )
                Button(settings.t("New Album"), systemImage: "plus") {
                    newAlbumName = ""
                    showsNewAlbum = true
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .padding(.horizontal, 20)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(settings.t("Albums"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 8)
                ForEach(albums) { album in
                    albumButton(album)
                    if album.id != albums.last?.id {
                        Divider().padding(.leading, 94)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .padding(.top, 10)
        }
    }

    private func albumButton(_ album: UserAlbumItem) -> some View {
        Button { add(to: album.collection) } label: {
            HStack(spacing: 14) {
                Group {
                    if let coverAsset = album.coverAsset {
                        AssetMediaView(
                            asset: coverAsset,
                            contentMode: .fill,
                            showsVideoBadge: false
                        )
                    } else {
                        Image(systemName: "rectangle.stack")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.primary.opacity(0.05))
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(album.count.formatted()) \(settings.t("Items"))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if busyAlbumID == album.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(ApplePressButtonStyle())
        .disabled(busyAlbumID != nil)
    }

    private func loadAlbums() async {
        isLoading = true
        let collections = await manager.fetchUserAlbums()
        guard !Task.isCancelled else { return }
        albums = collections.map { collection in
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assets = PHAsset.fetchAssets(in: collection, options: options)
            return UserAlbumItem(
                collection: collection,
                title: collection.localizedTitle ?? settings.t("New Album"),
                count: assets.count,
                coverAsset: assets.firstObject
            )
        }
        isLoading = false
    }

    private func add(to album: PHAssetCollection) {
        guard busyAlbumID == nil else { return }
        busyAlbumID = album.localIdentifier
        Task {
            do {
                try await manager.addToAlbum(asset, album: album)
                dismiss()
            } catch {
                self.error = error
                busyAlbumID = nil
            }
        }
    }

    private func createAlbum() {
        let title = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, busyAlbumID == nil else { return }
        busyAlbumID = "new"
        Task {
            do {
                try await manager.createAlbum(named: title, adding: asset)
                dismiss()
            } catch {
                self.error = error
                busyAlbumID = nil
            }
        }
    }
}

private struct UserAlbumItem: Identifiable {
    let collection: PHAssetCollection
    let title: String
    let count: Int
    let coverAsset: PHAsset?
    var id: String { collection.localIdentifier }
}
