import Photos
import PhotosUI
import SwiftUI
import Inject

// MARK: - Clean Home

struct CleanHomeView: View {
    @ObserveInjection var inject
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore

    @State private var showsCleaning = false
    @State private var showsTrash = false
    @State private var showsSummary = false
    @State private var presentsSummaryAfterCleaning = false

    var body: some View {
        let _ = inject
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
                    Label("Trash", systemImage: manager.trashBin.isEmpty ? "trash" : "trash.fill")
                }
                .badge(manager.trashBin.count)
                .id("trash-badge-\(manager.trashBin.count)")
                .tint(.primary)
                .accessibilityLabel(settings.t("Trash"))
            }
        }
    }

    private var cleanContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if manager.isLimited { limitedAccessBanner }
                reviewStage
//                libraryOverview
                collectionSection
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            manager.fetchPhotos()
            manager.refreshLibraryOverview()
        }
    }

    private var libraryCount: Int {
        manager.filterCounts[.all] ?? (manager.currentFilter == .all ? manager.assets.count : 0)
    }

    private var formattedPendingBytes: String {
        ByteCountFormatter.string(fromByteCount: manager.pendingDeletionBytes, countStyle: .file)
    }

    // MARK: Review stage

    private var reviewStage: some View {
        ZStack(alignment: .bottom) {
            CleaningPreviewMosaic(assets: Array(manager.assets.prefix(4)))
                .frame(height: 224)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizedTitle(for: manager.currentFilter))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(manager.cleaningCandidateCount.formatted()) \(settings.t("Items"))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(action: beginCleaning) {
                    Label(settings.t("Start Cleaning"), systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .modifier(HomePrimaryButtonStyle())
                .buttonBorderShape(.capsule)
                .disabled(!manager.canBeginSession)
                .accessibilityValue("\(manager.cleaningCandidateCount) \(settings.t("Items"))")
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(.ultraThinMaterial) 
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    private var libraryOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(settings.t("Library Overview"))
                .font(.headline)
            HStack(alignment: .top, spacing: 0) {
                overviewMetric(
                    value: libraryCount.formatted(),
                    title: settings.t("Photos and videos")
                )
                Divider().frame(height: 48)
                overviewMetric(
                    value: manager.trashBin.count.formatted(),
                    title: settings.t("Pending deletion")
                )
                Divider().frame(height: 48)
                overviewMetric(
                    value: formattedPendingBytes,
                    title: settings.t("Space Selected")
                )
            }
        }
    }

    private func overviewMetric(value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: Collections

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if manager.currentFilter == .similar, let progress = manager.similarityProgress {
                ProgressView(value: progress) {
                    Text(settings.t("Finding Similar Photos"))
                        .font(.subheadline.weight(.semibold))
                } currentValueLabel: {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                }
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(PhotoFilter.allCases) { filter in
                    FilterCardView(
                        filter: filter,
                        title: localizedTitle(for: filter),
                        count: count(for: filter),
                        isSelected: manager.currentFilter == filter
                    ) {
                        manager.setFilter(filter)
                    }
                    .accessibilityIdentifier("tidyalbum.filter.\(filter.testIdentifier)")
                }
            }
        }
    }

    private func count(for filter: PhotoFilter) -> Int {
        manager.filterCounts[filter] ?? (filter == manager.currentFilter ? manager.assets.count : 0)
    }

    private func localizedTitle(for filter: PhotoFilter) -> String {
        switch filter {
        case .all: settings.t("All")
        case .photos: settings.t("Photos")
        case .screenshots: settings.t("Screenshots")
        case .videos: settings.t("Videos")
        case .largeVideos: settings.t("Large Videos")
        case .livePhotos: settings.t("Live Photos")
        case .selfies: settings.t("Selfies")
        case .favorites: settings.t("Favorites")
        case .similar: settings.t("Similar Photos")
        }
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
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }
}

private struct CleaningPreviewMosaic: View {
    let assets: [PHAsset]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                tile(at: 0)
                    .frame(width: proxy.size.width * 0.61)
                VStack(spacing: 0) {
                    tile(at: 1)
                    HStack(spacing: 0) {
                        tile(at: 2)
                        tile(at: 3)
                    }
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder private func tile(at index: Int) -> some View {
        if assets.indices.contains(index) {
            AssetMediaView(
                asset: assets[index],
                contentMode: .fill,
                showsVideoBadge: false
            )
        } else {
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)
                Image(systemName: index == 0 ? "photo.on.rectangle.angled" : "photo")
                    .font(index == 0 ? .largeTitle : .title3)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct HomePrimaryButtonStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

private extension PhotoFilter {
    var testIdentifier: String {
        switch self {
        case .all: "all"
        case .photos: "photos"
        case .screenshots: "screenshots"
        case .videos: "videos"
        case .largeVideos: "large-videos"
        case .livePhotos: "live-photos"
        case .selfies: "selfies"
        case .favorites: "favorites"
        case .similar: "similar"
        }
    }
}
