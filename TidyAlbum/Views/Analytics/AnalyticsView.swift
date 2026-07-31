import Charts
import SwiftUI

// MARK: - Analytics Dashboard

struct AnalyticsView: View {
    @ObservedObject var store: AnalyticsStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var manager: PhotoManager

    @State private var showsResetConfirmation = false

    private var stats: CleanupStatistics { store.statistics }

    var body: some View {
        NavigationStack {
            Group {
                if stats.reviewedCount == 0 && stats.cleanedCount == 0 {
                    analyticsEmptyState
                } else {
                    analyticsContent
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(settings.t("Analytics"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(
                            settings.t("Reset Statistics"),
                            systemImage: "arrow.counterclockwise",
                            role: .destructive
                        ) {
                            showsResetConfirmation = true
                        }
                        .disabled(stats.reviewedCount == 0 && stats.cleanedCount == 0)
                    } label: {
                        Image(systemName: "ellipsis")
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(settings.t("More"))
                }
            }
        }
        .confirmationDialog(
            settings.t("Reset Cleanup History?"),
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(settings.t("Reset Statistics"), role: .destructive) { store.reset() }
            Button(settings.t("Cancel"), role: .cancel) {}
        } message: {
            Text(settings.t("This removes cleanup statistics from this device."))
        }
    }

    // MARK: Empty State

    private var analyticsEmptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 96, height: 96)
                .background(.primary.opacity(0.06), in: Circle())
            VStack(spacing: 8) {
                Text(settings.t("No cleanup history yet"))
                    .font(.title3.weight(.semibold))
                Text(settings.t("Start a cleaning session to see your progress here."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Content

    private var analyticsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                overview
                activity
                mediaBreakdown
                cleanupResults
                productivity
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.subheadline.weight(.semibold))
                Text(settings.t("Space Reclaimed"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            Text(ByteCountFormatter.string(fromByteCount: stats.reclaimedBytes, countStyle: .file))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())

            Divider()

            HStack(spacing: 0) {
                overviewMetric(value: stats.cleanedCount, title: settings.t("Items Cleaned"))
                Divider().frame(height: 42)
                overviewMetric(value: stats.reviewedCount, title: settings.t("Items Reviewed"))
                Divider().frame(height: 42)
                overviewMetric(value: manager.trashBin.count, title: settings.t("Pending deletion"))
            }
        }
        .padding(22)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private func overviewMetric(value: Int, title: String) -> some View {
        VStack(spacing: 5) {
            Text("\(value)")
                .font(.title3.bold().monospacedDigit())
                .contentTransition(.numericText())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 30)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Recent Activity

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                settings.t("Last 7 Days"),
                trailing: "\(recentDays.reduce(0) { $0 + $1.count }) \(settings.t("Items"))"
            )

            Chart(recentDays) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Items", day.count)
                )
                .foregroundStyle(Color.primary.opacity(day.count == 0 ? 0.12 : 0.82))
                .cornerRadius(5)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                    AxisTick().foregroundStyle(.clear)
                    AxisGridLine().foregroundStyle(.clear)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisValueLabel()
                    AxisTick().foregroundStyle(.clear)
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                }
            }
            .frame(height: 170)
            .padding(.horizontal, 4)
            .padding(.top, 6)
        }
        .analyticsSurface()
    }

    private var recentDays: [CleanupDay] {
        var calendar = Calendar.current
        calendar.locale = settings.language.locale
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return CleanupDay(
                date: date,
                count: stats.events.lazy.filter { calendar.isDate($0.date, inSameDayAs: date) }.count
            )
        }
    }

    // MARK: Media Breakdown

    private var mediaBreakdown: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(settings.t("Space by Media"))
            mediaRow(.photo, symbol: "photo")
            mediaRow(.video, symbol: "video")
        }
        .analyticsSurface()
    }

    private func mediaRow(_ kind: CleanupMediaKind, symbol: String) -> some View {
        let bytes = stats.bytes(for: kind)
        let fraction = stats.reclaimedBytes == 0 ? 0 : Double(bytes) / Double(stats.reclaimedBytes)
        return VStack(spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text(settings.t(kind == .photo ? "Photos" : "Videos"))
                    .font(.subheadline)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.primary.opacity(0.72))
                            .frame(width: proxy.size.width * CGFloat(fraction))
                    }
            }
            .frame(height: 6)
        }
    }

    // MARK: Cleanup Results

    private var cleanupResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(settings.t("Cleaning Wins"))
                .padding(.bottom, 8)
            resultRow(settings.t("Screenshots Cleaned"), value: stats.count(for: .screenshot), symbol: "camera.viewfinder")
            Divider().padding(.leading, 34)
            resultRow(settings.t("Large Videos"), value: stats.count(for: .largeVideo), symbol: "video")
            Divider().padding(.leading, 34)
            resultRow(settings.t("Other Items"), value: stats.count(for: .other), symbol: "photo.on.rectangle")
        }
        .analyticsSurface()
    }

    private func resultRow(_ title: String, value: Int, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
        }
        .padding(.vertical, 12)
    }

    // MARK: Productivity

    private var productivity: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(.primary.opacity(0.06), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.t("Most Productive Time"))
                    .font(.subheadline.weight(.semibold))
                Text(productiveTime)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .analyticsSurface()
    }

    private var productiveTime: String {
        guard let hour = stats.mostProductiveHour else { return settings.t("No cleanup history yet") }
        return String(format: "%02d:00 - %02d:00", hour, (hour + 1) % 24)
    }

    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CleanupDay: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

private extension View {
    func analyticsSurface() -> some View {
        padding(20)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
    }
}
