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

    private var previewIdentity: String {
        manager.assets.prefix(4).map(\.localIdentifier).joined(separator: "|")
    }

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
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SimilarPhotosView(manager: manager, settings: settings)
                } label: {
                    Label(settings.t("Similar Photos"), systemImage: "square.on.square")
                }
                .accessibilityLabel(settings.t("Similar Photos"))
            }
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
            VStack(alignment: .leading, spacing: 16) {
                if manager.isLimited { limitedAccessBanner }
                reviewStage
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
        .task(id: showsCleaning) {
            guard !showsCleaning else {
                manager.pauseSimilarityScan()
                return
            }
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
            ZStack {
                CleaningPreviewMosaic(assets: Array(manager.assets.prefix(4)))
                    .id(previewIdentity)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.32), value: previewIdentity)
            .frame(height: 224)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizedTitle(for: manager.currentFilter))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(reviewStageSubtitle)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(action: beginCleaning) {
                    Label(
                        settings.t("Start Cleaning"),
                        systemImage: "play.fill"
                    )
                        .font(.subheadline.weight(.semibold))
                }
                .modifier(HomePrimaryButtonStyle())
                .buttonBorderShape(.capsule)
                .accessibilityValue(reviewStageSubtitle)
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

    // MARK: Collections

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(PhotoFilter.allCases.filter { $0 != .similar }) { filter in
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
        manager.pauseSimilarityScan()
        manager.beginSession()
        showsCleaning = true
    }

    private var reviewStageSubtitle: String {
        if manager.currentFilter == .similar {
            return String(
                format: settings.t("X Groups Y Photos"),
                manager.similarityGroups.count,
                manager.assets.count
            )
        }
        return "\(manager.cleaningCandidateCount.formatted()) \(settings.t("Items"))"
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
            HStack(spacing: 0) {
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

struct SimilarGroupRow: View {
    let group: SimilarPhotoGroup
    @ObservedObject var settings: SettingsStore

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(Array(group.assets.prefix(4)), id: \.localIdentifier) { asset in
                    AssetMediaView(asset: asset, contentMode: .fill, showsVideoBadge: false)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: settings.t("X Similar Photos"), group.assets.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let date = group.assets.first?.creationDate {
                    Text(settings.fullDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(settings.t("Tap to Compare"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tint)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SimilarGroupComparisonView: View {
    let group: SimilarPhotoGroup
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var markedIDs: Set<String> = []

    private var suggestedKeeper: PHAsset? {
        group.assets.max { lhs, rhs in
            let leftPixels = lhs.pixelWidth * lhs.pixelHeight
            let rightPixels = rhs.pixelWidth * rhs.pixelHeight
            if leftPixels != rightPixels { return leftPixels < rightPixels }
            return (lhs.creationDate ?? .distantPast) < (rhs.creationDate ?? .distantPast)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.t("Compare Photos"))
                        .font(.title2.bold())
                    Text(String(format: settings.t("X Similar Photos"), group.assets.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(group.assets, id: \.localIdentifier) { asset in
                            comparisonCard(asset)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                HStack(spacing: 10) {
                    Button(settings.t("Select Suggested")) {
                        markedIDs = Set(group.assets.compactMap { asset in
                            asset.localIdentifier == suggestedKeeper?.localIdentifier ? nil : asset.localIdentifier
                        })
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    Spacer(minLength: 0)
                    Text(String(format: settings.t("Selected X"), markedIDs.count))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Button {
                    let targets = group.assets.filter { markedIDs.contains($0.localIdentifier) }
                    manager.queueSimilarPhotosForDeletion(targets)
                    dismiss()
                } label: {
                    Label(
                        String(format: settings.t("Move X to Pending Deletion"), markedIDs.count),
                        systemImage: "trash"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(markedIDs.isEmpty)
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(settings.t("Similar Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(settings.t("Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func comparisonCard(_ asset: PHAsset) -> some View {
        let isMarked = markedIDs.contains(asset.localIdentifier)
        let isSuggested = suggestedKeeper?.localIdentifier == asset.localIdentifier
        return Button {
            if isMarked {
                markedIDs.remove(asset.localIdentifier)
            } else {
                markedIDs.insert(asset.localIdentifier)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    AssetMediaView(asset: asset, contentMode: .fit, showsVideoBadge: true)
                        .frame(width: 250, height: 300)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Image(systemName: isMarked ? "trash.circle.fill" : "circle")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isMarked ? .white : .secondary, isMarked ? .red : .white)
                        .padding(10)
                }
                Text(isSuggested ? settings.t("Suggested Best") : settings.t("Keep or Mark"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isMarked ? Color.red : (isSuggested ? Color.accentColor : Color.primary))
                if let date = asset.creationDate {
                    Text(settings.fullDate(date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 250, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMarked ? settings.t("Marked for Deletion") : settings.t("Keep"))
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
