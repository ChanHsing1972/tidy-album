import SwiftUI

// MARK: - Session Summary

struct SummaryView: View {
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    var onHome: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsTrash = false
    @State private var isVisible = false

    private var summary: CleaningSessionSummary { manager.sessionSummary }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    completionHeader
                        .summaryReveal(isVisible, delay: 0, reduceMotion: reduceMotion)
                    selectedSpace
                        .summaryReveal(isVisible, delay: 0.08, reduceMotion: reduceMotion)
                    sessionMetrics
                        .summaryReveal(isVisible, delay: 0.14, reduceMotion: reduceMotion)
                    if !manager.trashBin.isEmpty {
                        pendingDeletionButton
                            .summaryReveal(isVisible, delay: 0.2, reduceMotion: reduceMotion)
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.top, 30)
                .padding(.bottom, 110)
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
        .onAppear { isVisible = true }
    }

    private var completionHeader: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 62, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.green)
                .shadow(color: .green.opacity(0.18), radius: 12, y: 5)
            VStack(spacing: 6) {
                Text(settings.t("Session Complete"))
                    .font(.title2.bold())
                Text(settings.t("You reviewed every item in this session."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedSpace: some View {
        VStack(spacing: 10) {
            Label(settings.t("Space Selected"), systemImage: "internaldrive")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(ByteCountFormatter.string(
                fromByteCount: summary.estimatedReclaimBytes,
                countStyle: .file
            ))
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
        .background(
            Color.accentColor.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 0.5)
        }
    }

    private var sessionMetrics: some View {
        HStack(spacing: 0) {
            metric(
                value: summary.reviewedCount,
                title: settings.t("Reviewed This Session"),
                icon: "eye"
            )
            Divider().frame(height: 64)
            metric(
                value: summary.markedForDeletionCount,
                title: settings.t("Marked for Deletion"),
                icon: "trash"
            )
        }
        .padding(.vertical, 4)
    }

    private func metric(value: Int, title: String, icon: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
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
                Image(systemName: "trash.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 40, height: 40)
                    .background(.red.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.t("Review Pending Items"))
                        .font(.subheadline.weight(.semibold))
                    Text("\(manager.trashBin.count) \(settings.t("Items"))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var doneBar: some View {
        Button(settings.t("Back to Library"), action: onHome)
            .font(.headline)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.bar)
    }
}

private extension View {
    func summaryReveal(
        _ isVisible: Bool,
        delay: Double,
        reduceMotion: Bool
    ) -> some View {
        opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 14)
            .animation(
                reduceMotion ? nil : .smooth(duration: 0.48).delay(delay),
                value: isVisible
            )
    }
}
