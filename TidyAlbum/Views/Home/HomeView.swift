import Photos
import PhotosUI
import SwiftUI

// MARK: - Clean Home

struct CleanHomeView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore

    @State private var showsCleaning = false
    @State private var showsTrash = false

    var body: some View {
        NavigationStack {
            Group {
                if manager.isAuthorized {
                    cleanContent
                } else {
                    PermissionView(settings: settings)
                }
            }
            .navigationTitle(settings.t("TidyAlbum"))
            .toolbar {
                if manager.isAuthorized {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showsTrash = true } label: {
                            Image(systemName: manager.trashBin.isEmpty ? "trash" : "trash.fill")
                        }
                        .badge(manager.trashBin.count)
                        .accessibilityLabel(settings.t("Trash"))
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showsCleaning) {
            CleaningView(manager: manager, settings: settings)
        }
        .sheet(isPresented: $showsTrash) {
            TrashView(manager: manager, settings: settings)
        }
    }

    private var cleanContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                librarySummary
                filterSection
                startButton
                privacyFooter
            }
            .padding(.horizontal)
            .padding(.top, 16) 
            .padding(.bottom, 28)
        }
        .refreshable { manager.fetchPhotos() }
    }

    // MARK: Library Summary

    private var librarySummary: some View {
        HStack(spacing: 0) {
            summaryMetric(value: manager.assets.count, title: "Photos and videos", symbol: "photo.on.rectangle")
            Divider().frame(height: 48)
            summaryMetric(value: manager.trashBin.count, title: "Pending deletion", symbol: "trash")
        }
        .padding(.vertical, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryMetric(value: Int, title: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Label("\(value)", systemImage: symbol)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(settings.t(title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Filters

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.t("Choose a collection"))
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(PhotoFilter.allCases) { filter in
                    FilterCardView(
                        filter: filter,
                        title: localizedTitle(for: filter),
                        isSelected: manager.currentFilter == filter
                    ) {
                        manager.setFilter(filter)
                    }
                }
            }
        }
    }

    private func localizedTitle(for filter: PhotoFilter) -> String {
        switch filter {
        case .all: settings.t("All Photos")
        case .screenshots: settings.t("Screenshots")
        case .selfies: settings.t("Selfies")
        case .favorites: settings.t("Favorites")
        }
    }

    // MARK: Start

    private var startButton: some View {
        Button {
            manager.beginSession()
            showsCleaning = true
        } label: {
            Label(settings.t("Start Cleaning"), systemImage: "arrow.right.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .disabled(manager.assets.isEmpty || manager.isLoading)
    }

    private var privacyFooter: some View {
        Label(settings.t("All processing stays on this iPhone or iPad."), systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
