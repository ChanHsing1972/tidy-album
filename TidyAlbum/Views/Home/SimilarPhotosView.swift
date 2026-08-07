import Photos
import SwiftUI

struct SimilarPhotosView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let progress = manager.similarityProgress {
                    scanProgress(progress)
                } else if manager.similarityGroups.isEmpty {
                    ContentUnavailableView(
                        settings.t("No Similar Groups"),
                        systemImage: "square.on.square.intersection.dashed",
                        description: Text(settings.t("No Similar Groups Detail"))
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    groups
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(settings.t("Similar Photos"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    manager.prepareSimilarityScan()
                } label: {
                    Label(settings.t("Scan on Device"), systemImage: "arrow.clockwise")
                }
                .disabled(manager.similarityProgress != nil)
            }
        }
        .task {
            manager.prepareSimilarityScan()
        }
        .onDisappear {
            manager.pauseSimilarityScan()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(settings.t("Compare Photos"), systemImage: "square.on.square")
                .font(.title2.weight(.bold))
            Text(settings.t("Similarity Scan Background Detail"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !manager.similarityGroups.isEmpty {
                Text(String(format: settings.t("X Groups Y Photos"), manager.similarityGroups.count, manager.similarityGroups.reduce(0) { $0 + $1.assets.count }))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
    }

    private func scanProgress(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(settings.t("Finding Similar Photos"), systemImage: "sparkle.magnifyingglass")
                    .font(.headline)
                Spacer()
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var groups: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(manager.similarityGroups) { group in
                NavigationLink {
                    SimilarGroupComparisonView(group: group, manager: manager, settings: settings)
                } label: {
                    SimilarGroupRow(group: group, settings: settings)
                }
                .buttonStyle(ApplePressButtonStyle())
            }
        }
    }
}
