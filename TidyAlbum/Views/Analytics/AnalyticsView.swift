import Charts
import SwiftUI
import Inject

// MARK: - Analytics Dashboard

struct AnalyticsView: View {
    @ObserveInjection var inject
    @ObservedObject var store: AnalyticsStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var manager: PhotoManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var heroNumberSize = 54.0
    @State private var showsResetConfirmation = false
    @State private var isVisible = false

    private var stats: CleanupStatistics { store.statistics }

    var body: some View {
        let _ = inject
        NavigationStack {
            Group {
                if stats.reviewedCount == 0 && stats.cleanedCount == 0 {
                    analyticsEmptyState
                } else {
                    analyticsContent
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(settings.t("Analytics"))
            .toolbar { analyticsToolbar }
        }
        .confirmationDialog(
            settings.t("Reset Cleanup History?"),
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(settings.t("Reset Statistics"), role: .destructive) { store.reset() }
                .tint(.red)
            Button(settings.t("Cancel"), role: .cancel) {}
        } message: {
            Text(settings.t("This removes cleanup statistics from this device."))
        }
    }

    @ToolbarContentBuilder private var analyticsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(role: .destructive) {
                    showsResetConfirmation = true
                } label: {
                    Label{
                        Text(settings.t("Reset Statistics"))
                    } icon: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
                .tint(.red)
                .disabled(stats.reviewedCount == 0 && stats.cleanedCount == 0)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .accessibilityLabel(settings.t("More"))
        }
    }

    private var analyticsEmptyState: some View {
        ContentUnavailableView {
            Label(settings.t("No cleanup history yet"), systemImage: "chart.bar.xaxis")
        } description: {
            Text(settings.t("Start a cleaning session to see your progress here."))
        }
        .symbolRenderingMode(.hierarchical)
        .padding()
    }

    private var analyticsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                overview
                    .padding(.bottom, 30)
                    .staggeredReveal(
                        isVisible: isVisible,
                        duration: DesignTokens.Spring.entrance.response
                    )
                sectionDivider
                cleanupResults
                    .sectionSpacing()
                    .staggeredReveal(
                        isVisible: isVisible,
                        delay: 0,
                        duration: DesignTokens.Spring.default.response
                    )
                sectionDivider
                mediaBreakdown
                    .sectionSpacing()
                    .staggeredReveal(
                        isVisible: isVisible,
                        delay: 0,
                        duration: DesignTokens.Spring.default.response
                    )
                sectionDivider
                activity
                    .sectionSpacing()
                    .staggeredReveal(
                        isVisible: isVisible,
                        delay: 0,
                        duration: DesignTokens.Spring.default.response
                    )

//                sectionDivider
//                productivity
//                    .padding(.top, 30)
//                    .staggeredReveal(
//                        isVisible: isVisible,
//                        delay: 0.21,
//                        duration: DesignTokens.Spring.default.response
//                    )
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .task {
            isVisible = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            isVisible = true
        }
        .onDisappear { isVisible = false }
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label(settings.t("Space Reclaimed"), systemImage: "internaldrive.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(
                    fromByteCount: stats.reclaimedBytes,
                    countStyle: .file
                ))
                    .font(.system(
                        size: min(heroNumberSize, 76),
                        weight: .bold,
                    ))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
            overviewMetrics
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var overviewMetrics: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                overviewMetricRow(value: stats.cleanedCount, title: settings.t("Items Cleaned"))
                Divider()
                overviewMetricRow(value: stats.reviewedCount, title: settings.t("Items Reviewed"))
                Divider()
                overviewMetricRow(value: manager.trashBin.count, title: settings.t("Pending deletion"))
            }
        } else {
            HStack(alignment: .top, spacing: 5) {
                overviewMetric(value: stats.cleanedCount, title: settings.t("Items Cleaned"))
                Divider().frame(height: 50)
                overviewMetric(value: stats.reviewedCount, title: settings.t("Items Reviewed"))
                Divider().frame(height: 50)
                overviewMetric(value: manager.trashBin.count, title: settings.t("Pending deletion"))
            }
        }
    }

    private func overviewMetric(value: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)")
                .font(.title2.bold().monospacedDigit())
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

    private func overviewMetricRow(value: Int, title: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.body)
            Spacer(minLength: 16)
            Text("\(value)")
                .font(.title2.bold().monospacedDigit())
                .contentTransition(.numericText())
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Recent Activity

    private var activity: some View {
        let days = recentDays
        let total = days.reduce(0) { $0 + $1.count }
        let upperBound = max(1, days.map(\.count).max() ?? 0)
        return VStack(alignment: .leading, spacing: 30) {
            sectionHeader(
                settings.t("Last 7 Days"),
                trailing: "\(total) \(settings.t("Items"))"
            )
            Chart(days) { day in
                BarMark(
                    x: .value(settings.t("Date"), day.date, unit: .day),
                    y: .value(settings.t("Items"), isVisible ? day.count : 0),
                    width: .ratio(0.58)
                )
                .foregroundStyle(
                    day.count == 0
                        ? Color.secondary.opacity(0.14)
                        : Color.accentColor
                )
                .cornerRadius(5)
            }
            .chartYScale(domain: 0...upperBound)
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
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.13))
                }
            }
            .frame(height: 188)
            .animation(chartAnimation, value: isVisible)
            .accessibilityLabel(settings.t("Last 7 Days"))
            .accessibilityValue("\(total) \(settings.t("Items"))")
        }
    }

    private var recentDays: [CleanupDay] {
        var calendar = Calendar.current
        calendar.locale = settings.language.locale
        let today = calendar.startOfDay(for: .now)
        let eventCounts = Dictionary(grouping: stats.events) {
            calendar.startOfDay(for: $0.date)
        }.mapValues(\.count)
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return CleanupDay(date: date, count: eventCounts[date, default: 0])
        }
    }

    // MARK: Media Breakdown

    private var mediaBreakdown: some View {
        let slices = mediaSlices
        return VStack(alignment: .leading, spacing: 20) {
            sectionHeader(settings.t("Space by Media"))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 28) {
                    mediaChart(slices)
                    mediaLegend(slices)
                }
                VStack(spacing: 22) {
                    mediaChart(slices)
                    mediaLegend(slices)
                }
            }
        }
    }

    private func mediaChart(_ slices: [MediaSlice]) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: 24)
                .padding(12)
                .accessibilityHidden(true)
            Chart(slices) { slice in
                SectorMark(
                    angle: .value(settings.t("Space Reclaimed"), slice.bytes),
                    innerRadius: .ratio(0.7),
                    angularInset: 2
                )
                .cornerRadius(4)
                .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(reduceMotion || isVisible ? 1 : 0.88)
            .animation(chartAnimation, value: isVisible)

            VStack(spacing: 1) {
                Text("\(stats.cleanedCount)")
                    .font(.title2.bold().monospacedDigit())
                    .contentTransition(.numericText())
                Text(settings.t("Items"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 158, height: 158)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settings.t("Space by Media"))
        .accessibilityValue(mediaAccessibilityValue)
    }

    private func mediaLegend(_ slices: [MediaSlice]) -> some View {
        VStack(spacing: 14) {
            ForEach(slices) { slice in
                HStack(spacing: 10) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.t(slice.kind == .photo ? "Photos" : "Videos"))
                            .font(.subheadline.weight(.semibold))
                        Text(ByteCountFormatter.string(
                            fromByteCount: Int64(slice.bytes),
                            countStyle: .file
                        ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    Text(slice.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var mediaSlices: [MediaSlice] {
        let total = max(Double(stats.reclaimedBytes), 1)
        return CleanupMediaKind.allCases.map { kind in
            let bytes = Double(stats.bytes(for: kind))
            return MediaSlice(
                kind: kind,
                bytes: bytes,
                fraction: bytes / total,
                color: kind == .photo ? .blue : .purple
            )
        }
    }

    private var mediaAccessibilityValue: String {
        mediaSlices.map { slice in
            let title = settings.t(slice.kind == .photo ? "Photos" : "Videos")
            let bytes = ByteCountFormatter.string(
                fromByteCount: Int64(slice.bytes),
                countStyle: .file
            )
            return "\(title) \(bytes)"
        }.joined(separator: ", ")
    }

    // MARK: Cleanup Results

    private var cleanupResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(settings.t("Cleaning Wins"))
                .padding(.bottom, 12)
            resultRow(
                settings.t("Screenshots Cleaned"),
                value: stats.count(for: .screenshot),
                symbol: "camera.viewfinder",
                color: .primary
            )
            resultRow(
                settings.t("Large Videos"),
                value: stats.count(for: .largeVideo),
                symbol: "video.fill",
                color: .primary
            )
            resultRow(
                settings.t("Other Items"),
                value: stats.count(for: .other),
                symbol: "photo.on.rectangle",
                color: .primary
            )
        }
    }

    private func resultRow(
        _ title: String,
        value: Int,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 34)
                .accessibilityHidden(true)
            Text(title)
                .font(.body)
            Spacer(minLength: 16)
            Text("\(value)")
                .font(.title3.bold().monospacedDigit())
                .contentTransition(.numericText())
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: Productivity

    private var productivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(settings.t("Most Productive Time"), systemImage: "clock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(productiveTime)
                .font(.title2.bold().monospacedDigit())
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private var productiveTime: String {
        guard let hour = stats.mostProductiveHour else {
            return settings.t("No cleanup history yet")
        }
        return String(format: "%02d:00 – %02d:00", hour, (hour + 1) % 24)
    }

    private var sectionDivider: some View {
        Divider()
    }

    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.bold())
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chartAnimation: Animation? {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(
                response: DesignTokens.Spring.entrance.response,
                dampingFraction: DesignTokens.Spring.entrance.damping
            )
    }
}

private struct CleanupDay: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

private struct MediaSlice: Identifiable {
    let kind: CleanupMediaKind
    let bytes: Double
    let fraction: Double
    let color: Color
    var id: CleanupMediaKind { kind }
}

private extension View {
    func sectionSpacing() -> some View {
        padding(.vertical, 30)
    }
}
