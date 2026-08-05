import Photos
import SwiftUI

enum CleaningTimelineLayout {
    static let columnCount = 3
    static let spacing: CGFloat = 2

    static func targetColumn(in assets: [PHAsset], selectedAssetID: String) -> Int {
        guard let selected = assets.first(where: { $0.localIdentifier == selectedAssetID }) else {
            return 1
        }
        let calendar = Calendar.current
        let selectedComponents = selected.creationDate.map {
            calendar.dateComponents([.year, .month], from: $0)
        } ?? DateComponents()
        let sectionAssets = assets.filter { asset in
            let components = asset.creationDate.map {
                calendar.dateComponents([.year, .month], from: $0)
            } ?? DateComponents()
            return components.year == selectedComponents.year
                && components.month == selectedComponents.month
        }.sorted {
            ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
        }
        let index = sectionAssets.firstIndex {
            $0.localIdentifier == selectedAssetID
        } ?? 1
        return index % columnCount
    }
}

struct CleaningTimelineView: View {
    let assets: [PHAsset]
    let selectedAssetID: String
    @ObservedObject var settings: SettingsStore
    let onSelect: (PHAsset) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: CleaningTimelineLayout.spacing),
        count: CleaningTimelineLayout.columnCount
    )

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(sections) { section in
                        Section {
                            LazyVGrid(columns: columns, spacing: CleaningTimelineLayout.spacing) {
                                ForEach(section.assets, id: \.localIdentifier) { asset in
                                    assetButton(asset)
                                        .id(asset.localIdentifier)
                                }
                            }
                        } header: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(section.title)
                                    .font(.title3.bold())
                                Spacer()
                                Text(section.assets.count.formatted())
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 80)
            }
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemBackground))
            .accessibilityIdentifier("tidyalbum.cleaning-timeline")
            .onAppear { scrollToSelection(using: proxy, animated: false) }
            .onChange(of: selectedAssetID) { _, _ in
                scrollToSelection(using: proxy, animated: true)
            }
        }
    }

    private func assetButton(_ asset: PHAsset) -> some View {
        Button { onSelect(asset) } label: {
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                AssetMediaView(asset: asset, contentMode: .fill, showsVideoBadge: false)
            }
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .overlay {
                    if asset.localIdentifier == selectedAssetID {
                        Rectangle()
                            .stroke(.white, lineWidth: 3)
                            .padding(2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if asset.localIdentifier == selectedAssetID {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(7)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: asset))
        .accessibilityAddTraits(asset.localIdentifier == selectedAssetID ? .isSelected : [])
    }

    private var sections: [TimelineSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: assets) { asset -> DateComponents in
            guard let date = asset.creationDate else { return DateComponents() }
            return calendar.dateComponents([.year, .month], from: date)
        }
        return grouped.map { components, assets in
            let date = calendar.date(from: components)
            return TimelineSection(
                id: "\(components.year ?? 0)-\(components.month ?? 0)",
                date: date,
                title: sectionTitle(for: date),
                assets: assets.sorted {
                    ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
                }
            )
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func sectionTitle(for date: Date?) -> String {
        guard let date else { return settings.t("Unknown Date") }
        let formatter = DateFormatter()
        formatter.locale = settings.language.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: date)
    }

    private func accessibilityLabel(for asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return settings.t("Unknown Date") }
        return settings.fullDate(date)
    }

    private func scrollToSelection(using proxy: ScrollViewProxy, animated: Bool) {
        guard assets.contains(where: { $0.localIdentifier == selectedAssetID }) else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(selectedAssetID, anchor: .center)
                }
            } else {
                proxy.scrollTo(selectedAssetID, anchor: .center)
            }
        }
    }
}

private struct TimelineSection: Identifiable {
    let id: String
    let date: Date?
    let title: String
    let assets: [PHAsset]
}
