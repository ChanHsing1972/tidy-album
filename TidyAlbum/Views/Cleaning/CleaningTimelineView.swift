import Photos
import SwiftUI

struct CleaningTimelineView: View {
    let assets: [PHAsset]
    let selectedAssetID: String
    @ObservedObject var settings: SettingsStore
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(sections) { section in
                        Section {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(section.assets, id: \.localIdentifier) { asset in
                                    assetButton(asset)
                                }
                            }
                        } header: {
                            Text(section.title)
                                .font(.title3.bold())
                                .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(settings.t("Photos by Date"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(settings.t("Close"))
                }
            }
            .accessibilityIdentifier("tidyalbum.cleaning-timeline")
        }
    }

    private func assetButton(_ asset: PHAsset) -> some View {
        Button { onSelect(asset.localIdentifier) } label: {
            AssetMediaView(asset: asset, contentMode: .fill, showsVideoBadge: false)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if asset.localIdentifier == selectedAssetID {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
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
                assets: assets.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
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
}

private struct TimelineSection: Identifiable {
    let id: String
    let date: Date?
    let title: String
    let assets: [PHAsset]
}
