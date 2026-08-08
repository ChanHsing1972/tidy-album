import Photos
import SwiftUI

struct SimilarPhotosView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
//                    summaryCard

                    if let progress = manager.similarityProgress {
                        scanCard(progress: progress)
                    }

                    if !manager.similarityGroups.isEmpty {
                        groupsSection
                    } else if manager.similarityProgress == nil {
                        emptyCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .accessibilityIdentifier("tidyalbum.similar")
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(settings.t("Similar Photos"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        manager.refreshSimilarityScan()
                    } label: {
                        Label(settings.t("Scan Again"), systemImage: "arrow.clockwise")
                    }
                    .tint(.primary)
                    .disabled(manager.similarityProgress != nil)
                }
            }
            .task { manager.prepareSimilarityScan() }
            .onDisappear { manager.pauseSimilarityScan() }
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
    }

    // 顶部统计信息卡片
    private var summaryCard: some View {
        HStack {
            Text(settings.t("Sets Ready"))
                .font(.body)
            Spacer()
            Text(manager.similarityGroups.count.formatted())
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // 扫描进度卡片
    private func scanCard(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                Text(settings.t("Finding Similar Photos"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
            Text(settings.t("Similarity Scan Background Detail"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // 独立卡片渲染组
    private var groupsSection: some View {
        VStack(spacing: 16) {
            ForEach(manager.similarityGroups) { group in
                SimilarGroupCardView(group: group, manager: manager, settings: settings)
            }
        }
    }

    // 空状态卡片
    private var emptyCard: some View {
        ContentUnavailableView(
            settings.t("No Similar Groups"),
            systemImage: "checkmark.circle",
            description: Text(settings.t("No Similar Groups Detail"))
        )
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 独立的相似照片组卡片组件
struct SimilarGroupCardView: View {
    let group: SimilarPhotoGroup
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        NavigationLink {
            SimilarGroupComparisonView(group: group, manager: manager, settings: settings)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // 组头部信息：显示照片数量与创建日期
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: settings.t("X Similar Photos"), group.assets.count))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let date = group.assets.first?.creationDate {
                            Text(settings.calendarDate(date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }

                // 展示组内所有照片（横向可滚动）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(group.assets, id: \.localIdentifier) { asset in
                            AssetMediaView(asset: asset, contentMode: .fill, showsVideoBadge: false)
                                .frame(width: 90, height: 90)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SimilarGroupComparisonView: View {
    let group: SimilarPhotoGroup
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var keeperID: String
    @State private var markedIDs: Set<String>
    @State private var showsConfirmation = false

    init(group: SimilarPhotoGroup, manager: PhotoManager, settings: SettingsStore) {
        self.group = group
        self.manager = manager
        self.settings = settings
        _keeperID = State(initialValue: group.recommendedKeeper?.localIdentifier ?? group.assets.first?.localIdentifier ?? "")
        _markedIDs = State(initialValue: Set(group.suggestedDeletionAssets.map(\.localIdentifier)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                keeperSection
                candidatesSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(settings.t("Choose What to Keep"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: resetSuggestions) {
                    Label(settings.t("Reset Suggestions"), systemImage: "arrow.counterclockwise")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button(actionTitle, role: .destructive, action: commitRemoval)
            Button(settings.t("Cancel"), role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    @ViewBuilder private var keeperSection: some View {
        if let keeper {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(settings.t("Recommended Keeper"), systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Spacer(minLength: 8)
                    if keeper.isFavorite {
                        Label(settings.t("Favorite"), systemImage: "heart.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.pink)
                    }
                }

                ZStack {
                    Color(uiColor: .secondarySystemBackground)
                    AssetMediaView(asset: keeper, contentMode: .fit, showsVideoBadge: true)
                }
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 8) {
                    Label("\(keeper.pixelWidth) × \(keeper.pixelHeight)", systemImage: "rectangle.expand.vertical")
                    Spacer(minLength: 4)
                    if let date = keeper.creationDate {
                        Text(settings.calendarDate(date))
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(settings.t("Other Similar Photos"))
                    .font(.headline)
                Spacer(minLength: 8)
                Text(String(format: settings.t("Selected X"), markedIDs.count))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130, maximum: 220), spacing: 12)],
                spacing: 18
            ) {
                ForEach(candidateAssets, id: \.localIdentifier) { asset in
                    candidateTile(asset)
                }
            }
        }
    }

    private func candidateTile(_ asset: PHAsset) -> some View {
        let isMarked = markedIDs.contains(asset.localIdentifier)
        return VStack(alignment: .leading, spacing: 7) {
            Button {
                toggleRemoval(asset)
            } label: {
                ZStack(alignment: .topTrailing) {
                    AssetMediaView(asset: asset, contentMode: .fill, showsVideoBadge: true)
                        .aspectRatio(1, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    Image(systemName: isMarked ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isMarked ? .red : .black.opacity(0.28))
                        .shadow(radius: 2)
                        .padding(8)
                }
                .aspectRatio(1, contentMode: .fit)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isMarked ? Color.red : .clear, lineWidth: 2)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Label(
                    statusTitle(for: asset, isMarked: isMarked),
                    systemImage: statusSymbol(for: asset, isMarked: isMarked)
                )
                .lineLimit(1)
                Spacer(minLength: 2)
                Button {
                    makeKeeper(asset)
                } label: {
                    Image(systemName: "checkmark.seal")
                }
                .accessibilityLabel(settings.t("Keep This Photo"))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isMarked ? Color.red : Color.secondary)

            Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .contain)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: settings.t("Selected X"), markedIDs.count))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(settings.t("Favorites Stay Protected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                showsConfirmation = true
            } label: {
                if manager.isDeleting {
                    ProgressView()
                } else {
                    Label(settings.t("Review Removal"), systemImage: "trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .disabled(markedIDs.isEmpty || manager.isDeleting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var keeper: PHAsset? {
        group.assets.first { $0.localIdentifier == keeperID }
    }

    private var candidateAssets: [PHAsset] {
        group.assets.filter { $0.localIdentifier != keeperID }
    }

    private var actionTitle: String {
        if settings.deletionMode == .systemTrash {
            return String(format: settings.t("Delete X from Photos"), markedIDs.count)
        }
        return String(format: settings.t("Move X to Pending Deletion"), markedIDs.count)
    }

    private var confirmationTitle: String {
        settings.t(settings.deletionMode == .systemTrash ? "Delete from Photos?" : "Move Similar Photos?")
    }

    private var confirmationMessage: String {
        settings.t(
            settings.deletionMode == .systemTrash
                ? "System Similar Photos Deletion Detail"
                : "Similar Photos Deletion Detail"
        )
    }

    private func statusTitle(for asset: PHAsset, isMarked: Bool) -> String {
        if isMarked { return settings.t("Marked for Deletion") }
        return settings.t(asset.isFavorite ? "Protected Favorite" : "Keep")
    }

    private func statusSymbol(for asset: PHAsset, isMarked: Bool) -> String {
        if isMarked { return "xmark" }
        return asset.isFavorite ? "heart.fill" : "checkmark"
    }

    private func toggleRemoval(_ asset: PHAsset) {
        if markedIDs.contains(asset.localIdentifier) {
            markedIDs.remove(asset.localIdentifier)
        } else {
            markedIDs.insert(asset.localIdentifier)
        }
    }

    private func makeKeeper(_ asset: PHAsset) {
        guard asset.localIdentifier != keeperID else { return }
        if let keeper, !keeper.isFavorite {
            markedIDs.insert(keeper.localIdentifier)
        }
        keeperID = asset.localIdentifier
        markedIDs.remove(asset.localIdentifier)
    }

    private func resetSuggestions() {
        keeperID = group.recommendedKeeper?.localIdentifier ?? group.assets.first?.localIdentifier ?? ""
        markedIDs = Set(group.suggestedDeletionAssets.map(\.localIdentifier))
    }

    private func commitRemoval() {
        let targets = group.assets.filter { markedIDs.contains($0.localIdentifier) }
        guard !targets.isEmpty else { return }
        manager.queueSimilarPhotosForDeletion(targets)
        dismiss()
    }
}
