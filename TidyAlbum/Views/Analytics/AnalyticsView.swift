import Charts
import SwiftUI

// MARK: - Analytics Dashboard

struct AnalyticsView: View {
    @ObservedObject var store: AnalyticsStore
    @ObservedObject var settings: SettingsStore

    private var stats: CleanupStatistics { store.statistics }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    metrics
                    spaceChart
                    wins
                    productivity
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(settings.t("Analytics"))
        }
    }

    // MARK: Metrics

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metric(settings.t("Space Reclaimed"), value: ByteCountFormatter.string(fromByteCount: stats.reclaimedBytes, countStyle: .file), symbol: "externaldrive.fill", color: .blue)
            metric(settings.t("Items Cleaned"), value: "\(stats.cleanedCount)", symbol: "checkmark.circle.fill", color: .green)
            metric(settings.t("Items Reviewed"), value: "\(stats.reviewedCount)", symbol: "eye.fill", color: .orange)
            metric(settings.t("Pending deletion"), value: "—", symbol: "trash.fill", color: .red)
        }
    }

    private func metric(_ title: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.title3)
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Space Chart

    private var spaceChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(settings.t("Space by Media"))
                .font(.headline)
            Chart(CleanupMediaKind.allCases) { kind in
                BarMark(
                    x: .value("Type", mediaTitle(kind)),
                    y: .value("Bytes", Double(stats.bytes(for: kind)))
                )
                .foregroundStyle(by: .value("Type", mediaTitle(kind)))
                .cornerRadius(6)
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let bytes = value.as(Double.self) {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                        }
                    }
                }
            }
            .frame(height: 190)
            if stats.cleanedCount == 0 {
                Text(settings.t("Start a cleaning session to see your progress here."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func mediaTitle(_ kind: CleanupMediaKind) -> String {
        settings.t(kind == .photo ? "Photos" : "Videos")
    }

    // MARK: Wins

    private var wins: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(settings.t("Cleaning Wins"))
                .font(.headline)
            winRow(settings.t("Screenshots Cleaned"), value: stats.count(for: .screenshot), symbol: "camera.viewfinder", color: .purple)
            winRow(settings.t("Large Videos"), value: stats.count(for: .largeVideo), symbol: "video.fill", color: .orange)
            winRow(settings.t("Other Items"), value: stats.count(for: .other), symbol: "photo", color: .blue)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func winRow(_ title: String, value: Int, symbol: String, color: Color) -> some View {
        HStack {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 26)
            Text(title)
            Spacer()
            Text("\(value)")
                .font(.headline.monospacedDigit())
        }
        .padding(.vertical, 7)
    }

    // MARK: Productivity

    private var productivity: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.t("Most Productive Time"))
                    .font(.subheadline.weight(.semibold))
                Text(productiveTime)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var productiveTime: String {
        guard let hour = stats.mostProductiveHour else { return settings.t("No cleanup history yet") }
        return String(format: "%02d:00", hour)
    }
}
