import Photos
import SwiftUI

struct PhotoCalendarView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore

    @State private var assets: [PHAsset] = []
    @State private var isLoading = true
    @State private var showsCleaning = false

    private let columns = [
        GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
              if years.isEmpty {
                    ContentUnavailableView(
                        settings.t("No Dated Photos"),
                        systemImage: "calendar.badge.exclamationmark"
                    )
                } else {
                    calendarContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(settings.t("Photo Calendar"))
            .accessibilityIdentifier("tidyalbum.calendar")
        }
        .task { await reload() }
        .fullScreenCover(isPresented: $showsCleaning, onDismiss: manager.endSession) {
            CleaningView(manager: manager, settings: settings)
        }
    }

    private var calendarContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                ForEach(years) { year in
                    VStack(alignment: .leading, spacing: 14) {
                        yearHeader(year)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(year.months) { month in
                                monthButton(month)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await reload() }
    }

    private func yearHeader(_ year: PhotoYear) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(year.year))
                    .font(.title.bold().monospacedDigit())
                Spacer()
                Text("\(year.count.formatted()) \(settings.t("Items"))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            PhotoYearDensityStrip(months: year.months)
                .frame(height: 18)
                .accessibilityHidden(true)
        }
    }

    private func monthButton(_ month: PhotoMonth) -> some View {
        Button {
            guard !month.assets.isEmpty else { return }
            manager.beginSession(with: month.assets)
            showsCleaning = true
        } label: {
            // 使用 ZStack 将文字悬浮在封面图片上方
            ZStack(alignment: .bottom) {
                // 1. 底层：封面照片（填满整个卡片高度）
                monthArtwork(month)
                    .frame(height: 120) // 可根据需要微调高度
                    .clipped()

                // 2. 上层底部：带半透明毛玻璃背景的月份和数量栏
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(month.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(month.assets.count.formatted())
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                // 毛玻璃核心设置：超薄材质 + 微调透明度，透出底图
                .background(.ultraThinMaterial)
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(month.assets.isEmpty ? 0.04 : 0.08), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(ApplePressButtonStyle())
        .disabled(month.assets.isEmpty)
        .accessibilityLabel("\(month.name), \(month.assets.count) \(settings.t("Items"))")
    }
    @ViewBuilder
    private func monthArtwork(_ month: PhotoMonth) -> some View {
        if let coverAsset = month.assets.first {
            AssetMediaView(
                asset: coverAsset,
                contentMode: .fill,
                showsVideoBadge: false
            )
        } else {
            ZStack {
                Color.primary.opacity(0.035)
                Text(String(format: "%02d", month.month))
                    .font(.title2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var years: [PhotoYear] {
        let calendar = Calendar.current
        let datedAssets = assets.compactMap { asset -> (Int, Int, PHAsset)? in
            guard let date = asset.creationDate else { return nil }
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else { return nil }
            return (year, month, asset)
        }
        let assetsByYear = Dictionary(grouping: datedAssets, by: { $0.0 })
        return assetsByYear.keys.sorted(by: >).map { year in
            let values = assetsByYear[year] ?? []
            let byMonth = Dictionary(grouping: values, by: { $0.1 })
            let months = (1...12).map { month in
                PhotoMonth(
                    year: year,
                    month: month,
                    name: monthName(month),
                    assets: (byMonth[month] ?? []).map { $0.2 }
                )
            }
            return PhotoYear(year: year, months: months)
        }
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = settings.language.locale
        return formatter.shortMonthSymbols[month - 1]
    }

    private func reload() async {
        isLoading = true
        assets = await manager.fetchCalendarAssets()
        isLoading = false
    }
}

private struct PhotoYearDensityStrip: View {
    let months: [PhotoMonth]

    var body: some View {
        GeometryReader { proxy in
            let maximum = max(months.map(\.assets.count).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(months) { month in
                    Capsule()
                        .fill(month.assets.isEmpty ? Color.primary.opacity(0.08) : Color.accentColor.opacity(0.72))
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 3,
                            maxHeight: max(3, proxy.size.height * CGFloat(month.assets.count) / CGFloat(maximum))
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct PhotoYear: Identifiable {
    let year: Int
    let months: [PhotoMonth]
    var id: Int { year }
    var count: Int { months.reduce(0) { $0 + $1.assets.count } }
}

private struct PhotoMonth: Identifiable {
    let year: Int
    let month: Int
    let name: String
    let assets: [PHAsset]
    var id: String { "\(year)-\(month)" }
}
