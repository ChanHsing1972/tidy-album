import Charts
import SwiftUI

// MARK: - Analytics Dashboard

struct AnalyticsView: View {
    @ObservedObject var store: AnalyticsStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var manager: PhotoManager

    private var stats: CleanupStatistics { store.statistics }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    metrics
                    recentTrend
                    spaceDistribution
                    categoryResults
                    productivity
                }
                .padding(16)
                .padding(.bottom, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(settings.t("Analytics"))
        }
    }

    // MARK: Key Metrics

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metric(
                settings.t("Space Reclaimed"),
                value: ByteCountFormatter.string(fromByteCount: stats.reclaimedBytes, countStyle: .file),
                symbol: "internaldrive.fill",
                color: .blue
            )
            metric(settings.t("Items Cleaned"), value: "\(stats.cleanedCount)", symbol: "checkmark.circle.fill", color: .green)
            metric(settings.t("Items Reviewed"), value: "\(stats.reviewedCount)", symbol: "eye.fill", color: .orange)
            metric(settings.t("Pending deletion"), value: "\(manager.trashBin.count)", symbol: "trash.fill", color: .red)
        }
    }

    private func metric(_ title: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.title3.weight(.semibold))
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Seven-Day Trend

    private var recentTrend: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(settings.t("Last 7 Days"))
                    .font(.headline)
                Spacer()
                Text("\(recentDays.reduce(0) { $0 + $1.count }) \(settings.t("Items"))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Chart(recentDays) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Items", day.count)
                )
                .foregroundStyle(.blue)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                    AxisTick().foregroundStyle(.clear)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 148)
        }
        .analyticsGroup()
    }

    private var recentDays: [CleanupDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return CleanupDay(
                date: date,
                count: stats.events.lazy.filter { calendar.isDate($0.date, inSameDayAs: date) }.count
            )
        }
    }

    // MARK: Storage Distribution

    private var spaceDistribution: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(settings.t("Space by Media"))
                .font(.headline)
            if stats.reclaimedBytes == 0 {
                ContentUnavailableView(
                    settings.t("No cleanup history yet"),
                    systemImage: "chart.pie",
                    description: Text(settings.t("Start a cleaning session to see your progress here."))
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                HStack(spacing: 20) {
                    Chart(CleanupMediaKind.allCases) { kind in
                        SectorMark(
                            angle: .value("Bytes", stats.bytes(for: kind)),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .cornerRadius(4)
                        .foregroundStyle(kind == .photo ? Color.blue : Color.green)
                    }
                    .chartBackground { _ in
                        VStack(spacing: 1) {
                            Text(ByteCountFormatter.string(fromByteCount: stats.reclaimedBytes, countStyle: .file))
                                .font(.caption.bold())
                                .minimumScaleFactor(0.7)
                            Text(settings.t("Total"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 150, height: 150)

                    VStack(alignment: .leading, spacing: 18) {
                        mediaLegend(.photo, color: .blue)
                        mediaLegend(.video, color: .green)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .analyticsGroup()
    }

    private func mediaLegend(_ kind: CleanupMediaKind, color: Color) -> some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.t(kind == .photo ? "Photos" : "Videos"))
                    .font(.subheadline.weight(.medium))
                Text(ByteCountFormatter.string(fromByteCount: stats.bytes(for: kind), countStyle: .file))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Category Results

    private var categoryResults: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(settings.t("Cleaning Wins"))
                .font(.headline)
                .padding(.bottom, 6)
            resultRow(settings.t("Screenshots Cleaned"), value: stats.count(for: .screenshot), symbol: "camera.viewfinder", color: .pink)
            Divider()
            resultRow(settings.t("Large Videos"), value: stats.count(for: .largeVideo), symbol: "video.fill", color: .orange)
            Divider()
            resultRow(settings.t("Other Items"), value: stats.count(for: .other), symbol: "photo", color: .blue)
        }
        .analyticsGroup()
    }

    private func resultRow(_ title: String, value: Int, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
        }
        .padding(.vertical, 8)
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
        .analyticsGroup()
    }

    private var productiveTime: String {
        guard let hour = stats.mostProductiveHour else { return settings.t("No cleanup history yet") }
        return String(format: "%02d:00 – %02d:00", hour, (hour + 1) % 24)
    }
}

private struct CleanupDay: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

private extension View {
    func analyticsGroup() -> some View {
        padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
