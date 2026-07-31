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
    @State private var presentsSummaryAfterCleaning = false

    var body: some View {
        NavigationStack {
            Group {
                if manager.isAuthorized {
                    cleanContent
                } else {
                    PermissionView(settings: settings)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(settings.t("TidyAlbum"))
            .toolbar { homeToolbar }
        }
        .fullScreenCover(isPresented: $showsCleaning, onDismiss: cleaningDidDismiss) {
            CleaningView(manager: manager, settings: settings) {
                presentsSummaryAfterCleaning = true
            }
        }
        .sheet(isPresented: $showsTrash) {
            TrashView(manager: manager, settings: settings)
        }
        .sheet(isPresented: $showsSummary) {
            SummaryView(
                manager: manager,
                settings: settings,
                onHome: { showsSummary = false }
            )
        }
    }

    @ToolbarContentBuilder private var homeToolbar: some ToolbarContent {
        if manager.isAuthorized {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsTrash = true } label: {
                    Image(systemName: manager.trashBin.isEmpty ? "trash" : "trash.fill")
                        .contentShape(Rectangle())
                }
                .badge(manager.trashBin.count)
                .buttonStyle(.plain)
                .accessibilityLabel(settings.t("Trash"))
            }
        }
    }

    private var cleanContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if manager.isLimited { limitedAccessBanner }
                libraryOverview
                if !manager.trashBin.isEmpty { pendingDeletionRow }
                collectionSection
                privacyFooter
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 92)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            manager.fetchPhotos()
            manager.refreshLibraryOverview()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            startActionBar
        }
    }

    // MARK: Library Overview

    private var libraryOverview: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(settings.t("Library Overview"), systemImage: "photo.stack")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(libraryCount)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(settings.t("Photos and videos"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 0) {
                overviewMetric(
                    value: manager.isLoading ? "-" : "\(manager.assets.count)",
                    title: settings.t("Selected Collection")
                )
                Divider().frame(height: 42)
                overviewMetric(
                    value: "\(min(manager.assets.count, settings.cleaningGroupSize.rawValue))",
                    title: settings.t("Next Group")
                )
            }
        }
        .padding(22)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private func overviewMetric(value: String, title: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var libraryCount: Int {
        manager.filterCounts[.all] ?? (manager.currentFilter == .all ? manager.assets.count : 0)
    }

    // MARK: Pending Deletion

    private var pendingDeletionRow: some View {
        Button { showsTrash = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "trash")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.primary.opacity(0.06), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.t("Pending deletion"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(manager.trashBin.count) \(settings.t("Items")) · \(formattedPendingBytes)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(settings.t("Review Pending Items"))
    }

    private var formattedPendingBytes: String {
        ByteCountFormatter.string(fromByteCount: manager.pendingDeletionBytes, countStyle: .file)
    }

    // MARK: Collections

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(settings.t("Collections"))
                .font(.title3.bold())

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(PhotoFilter.allCases) { filter in
                    FilterCardView(
                        filter: filter,
                        title: localizedTitle(for: filter),
                        count: count(for: filter),
                        isSelected: manager.currentFilter == filter,
                        isLoading: manager.isLoading && manager.currentFilter == filter
                    ) {
                        manager.setFilter(filter)
                    }
                }
            }
        }
    }

    private func count(for filter: PhotoFilter) -> Int {
        manager.filterCounts[filter] ?? (filter == manager.currentFilter ? manager.assets.count : 0)
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

    private var startActionBar: some View {
        Button(action: beginCleaning) {
            HStack(spacing: 10) {
                if manager.isLoading {
                    ProgressView()
                        .tint(.white)
                    Text(settings.t("Loading Photos"))
                } else {
                    Image(systemName: "sparkles")
                    Text(settings.t("Start Cleaning"))
                    Spacer()
                    if !manager.assets.isEmpty {
                        Text("\(min(manager.assets.count, settings.cleaningGroupSize.rawValue))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    Image(systemName: "arrow.right")
                }
            }
            .font(.headline)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .disabled(!manager.canBeginSession)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .animation(.easeInOut(duration: 0.2), value: manager.isLoading)
    }

    private func beginCleaning() {
        guard manager.canBeginSession else { return }
        presentsSummaryAfterCleaning = false
        manager.beginSession()
        showsCleaning = true
    }

    private func cleaningDidDismiss() {
        manager.endSession()
        guard presentsSummaryAfterCleaning else { return }
        presentsSummaryAfterCleaning = false
        Task { @MainActor in
            await Task.yield()
            showsSummary = true
        }
    }

    // MARK: Access and Privacy

    private var limitedAccessBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
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
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
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
