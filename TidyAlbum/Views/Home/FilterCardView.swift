import SwiftUI

// MARK: - 筛选卡片组件
/// 展示单个筛选条件（全部、截屏、自拍、收藏）的可点击卡片。
/// 选中状态有高亮样式反馈。
struct FilterCardView: View {

    // MARK: 属性

    /// 筛选条件
    let filter: PhotoFilter
    /// 是否为当前选中状态
    let isSelected: Bool
    /// 点击回调
    let action: () -> Void

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.standard) {
                Image(systemName: filter.icon)
                    .font(DesignTokens.Typography.cardIcon)
                    .foregroundColor(isSelected ? DesignTokens.Colors.textOnPrimary : DesignTokens.Colors.textPrimary)

                Text(filter.rawValue)
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(isSelected ? DesignTokens.Colors.textOnPrimary : DesignTokens.Colors.textPrimary)
            }
            .padding(DesignTokens.Spacing.large)
            .frame(
                width: DesignTokens.Dimensions.filterCardWidth,
                height: DesignTokens.Dimensions.filterCardHeight
            )
            .background(
                isSelected
                    ? DesignTokens.Colors.textPrimary
                    : DesignTokens.Colors.textPrimary.opacity(DesignTokens.Opacity.divider)
            )
            .cornerRadius(DesignTokens.CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.large)
                    .stroke(
                        DesignTokens.Colors.textPrimary.opacity(DesignTokens.Opacity.cardBorder),
                        lineWidth: 1
                    )
            )
        }
    }
}