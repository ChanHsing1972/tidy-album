import SwiftUI

// MARK: - Session Summary

/// 按照 Apple Design 规范重新设计的会话总结页。
/// 核心原则：数字展示作为视觉焦点、弹簧动画入场、材质层级传达深度。
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
                VStack(spacing: 32) {
                    completionHeader
                        .staggeredReveal(isVisible: isVisible, delay: 0, duration: DesignTokens.Spring.entrance.response)

                    spaceReclaimedCard
                        .staggeredReveal(isVisible: isVisible, delay: 0.08, duration: DesignTokens.Spring.default.response)

                    sessionMetricsRow
                        .staggeredReveal(isVisible: isVisible, delay: 0.14, duration: DesignTokens.Spring.default.response)

                    if !manager.trashBin.isEmpty {
                        pendingDeletionButton
                            .staggeredReveal(isVisible: isVisible, delay: 0.20, duration: DesignTokens.Spring.default.response)
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

    // MARK: - Completion Header

    private var completionHeader: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.green)
                .shadow(color: .green.opacity(0.22), radius: 16, y: 6)
            VStack(spacing: 6) {
                Text(settings.t("Session Complete"))
                    .font(.title2.bold())
                    .tracking(DesignTokens.Tracking.title)
                Text(settings.t("You reviewed every item in this session."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .tracking(DesignTokens.Tracking.body)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Space Reclaimed Card

    private var spaceReclaimedCard: some View {
        VStack(spacing: 12) {
            Label(settings.t("Space Selected"), systemImage: "internaldrive")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(DesignTokens.Tracking.body)

            Text(ByteCountFormatter.string(
                fromByteCount: summary.estimatedReclaimBytes,
                countStyle: .file
            ))
                .font(DesignTokens.Typography.heroNumber)
                .tracking(DesignTokens.Tracking.display)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .background(
            Color.accentColor.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.accentColor.opacity(0.16), lineWidth: 0.5)
        }
    }

    // MARK: - Session Metrics

    private var sessionMetricsRow: some View {
        HStack(spacing: 0) {
            metricView(
                value: summary.reviewedCount,
                title: settings.t("Reviewed This Session"),
                icon: "eye"
            )
            Divider().frame(height: 56)
            metricView(
                value: summary.markedForDeletionCount,
                title: settings.t("Marked for Deletion"),
                icon: "trash"
            )
        }
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metricView(value: Int, title: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title.bold().monospacedDigit())
                .tracking(DesignTokens.Tracking.title)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 32)
                .tracking(DesignTokens.Tracking.caption)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pending Deletion

    private var pendingDeletionButton: some View {
        Button { showsTrash = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "trash.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 40, height: 40)
                    .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.t("Review Pending Items"))
                        .font(.subheadline.weight(.semibold))
                        .tracking(DesignTokens.Tracking.body)
                    Text("\(manager.trashBin.count) \(settings.t("Items"))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .tracking(DesignTokens.Tracking.caption)
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
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Bar

    private var doneBar: some View {
        Button(settings.t("Back to Library"), action: onHome)
            .font(.headline)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
    }
}
