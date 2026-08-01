import SwiftUI
import Inject

// MARK: - Session Summary

struct SummaryView: View {
    @ObserveInjection var inject
    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore
    var onHome: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var successSymbolSize = 62.0
    @ScaledMetric(relativeTo: .largeTitle) private var resultNumberSize = 52.0
    @State private var showsTrash = false
    @State private var isVisible = false

    private var summary: CleaningSessionSummary { manager.sessionSummary }

    var body: some View {
        let _ = inject
        ScrollView {
            VStack(spacing: 34) {
                completionHeader
                    .staggeredReveal(
                        isVisible: isVisible,
                        duration: DesignTokens.Spring.entrance.response
                    )
                primaryResult
                    .staggeredReveal(
                        isVisible: isVisible,
                        delay: 0.07,
                        duration: DesignTokens.Spring.entrance.response
                    )
                if !manager.trashBin.isEmpty {
                    pendingDeletionAction
                        .staggeredReveal(
                            isVisible: isVisible,
                            delay: 0.13,
                            duration: DesignTokens.Spring.default.response
                        )
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 112)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { doneBar }
        .sheet(isPresented: $showsTrash) {
            TrashView(manager: manager, settings: settings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .presentationDragIndicator(.visible)
        .task {
            isVisible = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            isVisible = true
        }
        .onDisappear { isVisible = false }
    }

    private var completionHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(
                    size: min(successSymbolSize, 82),
                    weight: .semibold
                ))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .scaleEffect(reduceMotion || isVisible ? 1 : 0.82)
                .animation(completionAnimation, value: isVisible)
                .accessibilityHidden(true)
            Text(settings.t("Session Complete"))
                .font(.title2.bold())
            Text(settings.t("You reviewed every item in this session."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var primaryResult: some View {
        VStack(spacing: 7) {
            Text(primaryResultTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(primaryResultValue)
                .font(.system(
                    size: min(resultNumberSize, 68),
                    weight: .bold,
                    design: .rounded
                ))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .contentTransition(.numericText())
            Text(primaryResultCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var pendingDeletionAction: some View {
        Button { showsTrash = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "trash.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.t("Review Pending Items"))
                        .font(.body.weight(.semibold))
                    Text(pendingDeletionDetail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .padding(16)
            .background(
                Color.red.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.red.opacity(0.12), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(ApplePressButtonStyle())
        .accessibilityHint(settings.t("Open Pending Deletion"))
    }

    private var primaryResultTitle: String {
        settings.t(summary.markedForDeletionCount > 0 ? "Space Selected" : "Reviewed This Session")
    }

    private var primaryResultValue: String {
        guard summary.markedForDeletionCount > 0 else {
            return "\(summary.reviewedCount)"
        }
        return formattedBytes(summary.estimatedReclaimBytes)
    }

    private var primaryResultCaption: String {
        guard summary.markedForDeletionCount > 0 else {
            return settings.t("No items added to Pending Deletion")
        }
        return String(
            format: settings.t("Items ready in Pending Deletion"),
            summary.markedForDeletionCount
        )
    }

    private var pendingDeletionDetail: String {
        "\(manager.trashBin.count) \(settings.t("Items")) · \(formattedBytes(manager.pendingDeletionBytes))"
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var doneBar: some View {
        Button(action: onHome) {
            Text(settings.t("Back to Library"))
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var completionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(
                response: DesignTokens.Spring.entrance.response,
                dampingFraction: DesignTokens.Spring.entrance.damping
            )
    }
}
