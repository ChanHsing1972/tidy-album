import SwiftUI

// MARK: - 统计项组件
/// 在首页展示单个统计数据项（如"剩余照片数"、"垃圾桶数量"）。
struct StatItemView: View {

    // MARK: 属性

    /// 统计数值
    let value: String
    /// 统计项标题
    let title: String
    /// SF Symbol 图标名称
    let icon: String

    // MARK: - Body

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.compact) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.statIcon)
                .foregroundColor(DesignTokens.Colors.accentBlue)
                .frame(height: 30)

            Text(value)
                .font(DesignTokens.Typography.title2)
                .foregroundColor(DesignTokens.Colors.textPrimary)

            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}