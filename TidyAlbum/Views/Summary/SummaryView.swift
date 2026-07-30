import SwiftUI

// MARK: - 摘要视图 (Summary View)
/// 清理会话结束后的总结页面，展示本次会话的统计数据。
struct SummaryView: View {

    // MARK: 依赖

    @ObservedObject var manager: PhotoManager
    @ObservedObject var settings: SettingsStore

    // MARK: 回调

    /// 返回首页的回调
    var onHome: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.section) {
            Spacer()

            completionIcon
            completionTitle
            statsSection

            Spacer()

            homeButton
        }
    }

    // MARK: - 完成图标 (Completion Icon)

    private var completionIcon: some View {
        Image(systemName: "sparkles")
            .font(DesignTokens.Typography.completeIcon)
            .foregroundStyle(DesignTokens.Colors.gradientSparkle)
            .padding()
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(
                        width: DesignTokens.Dimensions.summaryIconCircleSize,
                        height: DesignTokens.Dimensions.summaryIconCircleSize
                    )
            )
    }

    // MARK: - 完成标题 (Completion Title)

    private var completionTitle: some View {
        VStack(spacing: 10) {
            Text(settings.t("Session Complete"))
                .font(DesignTokens.Typography.largeTitle)
                .foregroundColor(DesignTokens.Colors.textPrimary)

            Text(settings.t("You've cleaned up your album!"))
                .font(.body)
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
    }

    // MARK: - 统计区域 (Stats)

    private var statsSection: some View {
        HStack(spacing: DesignTokens.Spacing.extraLarge) {
            VStack {
                Text("\(manager.analytics.statistics.cleanedCount)")
                    .font(DesignTokens.Typography.displayNumber)
                    .foregroundColor(DesignTokens.Colors.accentRed)
                Text(settings.t("Deleted"))
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }

            VStack {
                Text("\(manager.trashBin.count)")
                    .font(DesignTokens.Typography.displayNumber)
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Text(settings.t("In Trash"))
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(DesignTokens.Spacing.section)
        .background(.ultraThinMaterial)
        .cornerRadius(DesignTokens.CornerRadius.large)
    }

    // MARK: - 返回首页按钮 (Home Button)

    private var homeButton: some View {
        Button(action: onHome) {
            Text(settings.t("Back to Home"))
                .font(.headline)
                .foregroundColor(DesignTokens.Colors.textOnPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: DesignTokens.Dimensions.secondaryButtonHeight)
                .background(DesignTokens.Colors.textPrimary)
                .cornerRadius(DesignTokens.CornerRadius.xLarge)
        }
        .padding(.horizontal, DesignTokens.Spacing.extraLarge)
        .padding(.bottom, DesignTokens.Spacing.extraLarge)
    }
}
