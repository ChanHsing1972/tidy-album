import SwiftUI

// MARK: - Session Summary

struct SummaryView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    var onHome: () -> Void

    @State private var showsTrash = false

    private var summary: CleaningSessionSummary { manager.sessionSummary }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    completionHeader
                    selectedSpace
                    sessionMetrics
                    if !manager.trashBin.isEmpty { pendingDeletionButton }
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(settings.t("Cleanup Summary"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) { doneBar }
        }
        .sheet(isPresented: $showsTrash) {
            TrashView(manager: manager, settings: settings)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var completionHeader: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .frame(width: 72, height: 72)
                .background(.primary.opacity(0.08), in: Circle())
            Text(settings.t("Session Complete"))
                .font(.title2.bold())
            Text(settings.t("You reviewed every item in this session."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedSpace: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(settings.t("Space Selected"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(ByteCountFormatter.string(fromByteCount: summary.estimatedReclaimBytes, countStyle: .file))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private var sessionMetrics: some View {
        HStack(spacing: 0) {
            metric(value: summary.reviewedCount, title: settings.t("Reviewed This Session"))
            Divider().frame(height: 52)
            metric(value: summary.markedForDeletionCount, title: settings.t("Marked for Deletion"))
        }
        .padding(.vertical, 20)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private func metric(value: Int, title: String) -> some View {
        VStack(spacing: 7) {
            Text("\(value)")
                .font(.title.bold().monospacedDigit())
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 32)
        }
        .frame(maxWidth: .infinity)
    }

    private var pendingDeletionButton: some View {
        Button { showsTrash = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "trash")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)
                    .background(.primary.opacity(0.06), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.t("Review Pending Items"))
                        .font(.subheadline.weight(.semibold))
                    Text("\(manager.trashBin.count) \(settings.t("Items"))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var doneBar: some View {
        Button(settings.t("Back to Library"), action: onHome)
            .font(.headline)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
    }
}
