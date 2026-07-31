import Photos
import PhotosUI
import SwiftUI

// MARK: - Clean Home

struct CleanHomeView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore

    @State private var showsCleaning = false
    @State private var showsTrash = false
    @State private var showsSummary = false

    var body: some View {
        NavigationStack {
            Group {
                if manager.isAuthorized { cleanContent } else { PermissionView(settings: settings) }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(settings.t("TidyAlbum"))
            .toolbar {
                if manager.isAuthorized {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showsTrash = true } label: {
                            Image(systemName: manager.trashBin.isEmpty ? "trash" : "trash.fill")
                        }
                        .badge(manager.trashBin.count)
                        .buttonStyle(.plain)
                        .id("home-trash-btn-\(manager.trashBin.count)")
                        .accessibilityLabel(settings.t("Trash"))
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showsCleaning) {
            CleaningView(manager: manager, settings: settings) { showsSummary = true }
        }
        .sheet(isPresented: $showsTrash) {
            TrashView(manager: manager, settings: settings)
        }
//        .sheet(isPresented: $showsSummary) {
//            SummaryView(manager: manager, settings: settings, onHome: { showsSummary = false })
//        }
    }

    private var cleanContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if manager.isLimited { limitedAccessBanner }
//                librarySummary
                filterSection
                startButton
                privacyFooter
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .refreshable {
            manager.fetchPhotos()
            manager.refreshLibraryOverview()
        }
    }

    // MARK: Library Summary

    private var librarySummary: some View {
        HStack(spacing: 0) {
            summaryMetric(
                value: "\(manager.filterCounts[.all] ?? manager.assets.count)",
                title: settings.t("Photos and videos"),
                symbol: "photo.on.rectangle"
            )
            Divider().frame(height: 52)
            summaryMetric(
                value: manager.trashBin.isEmpty
                    ? "0"
                    : ByteCountFormatter.string(fromByteCount: manager.pendingDeletionBytes, countStyle: .file),
                title: settings.t("Pending deletion"),
                symbol: "trash"
            )
        }
        .padding(.vertical, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func summaryMetric(value: String, title: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Label(value, systemImage: symbol)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Collections
    
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let columns = [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ]
            
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(PhotoFilter.allCases) { filter in
                    FilterCardView(
                        filter: filter,
                        title: localizedTitle(for: filter),
                        count: manager.filterCounts[filter]
                            ?? (filter == manager.currentFilter ? manager.assets.count : 0),
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
        case .videos: settings.t("Videos")
        case .largeVideos: settings.t("Large Videos")
        case .livePhotos: settings.t("Live Photos")
        case .selfies: settings.t("Selfies")
        case .favorites: settings.t("Favorites")
        }
    }

    // MARK: Primary Action

    private var startButton: some View {
        Button {
            guard manager.canBeginSession else { return }
            manager.beginSession()
            showsCleaning = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text(settings.t("Start Cleaning"))
                Spacer()
                Text("\(min(manager.assets.count, settings.cleaningGroupSize.rawValue))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                Image(systemName: "arrow.right")
            }
            .font(.headline)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .transaction { $0.animation = nil }
    }

    // MARK: Limited Access

    private var limitedAccessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.t("Limited Library"))
                    .font(.subheadline.weight(.semibold))
                Text(settings.t("Some photos are not available to TidyAlbum."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(settings.t("Manage Access")) { presentLimitedLibraryPicker() }
                .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }

    private var privacyFooter: some View {
        Label(settings.t("All processing stays on this iPhone or iPad."), systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
