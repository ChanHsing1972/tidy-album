import SwiftUI

// MARK: - 筛选卡片组件
/// 展示单个筛选条件（全部、截屏、自拍、收藏）的可点击卡片。
/// 选中状态有高亮样式反馈。
struct FilterCardView: View {

    // MARK: 属性

    /// 筛选条件
    let filter: PhotoFilter
    let title: String
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
                    .foregroundColor(isSelected ? Color.accentColor : .primary)

                Text(title)
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.primary)
            }
            .padding(DesignTokens.Spacing.large)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground)
            )
            .cornerRadius(DesignTokens.CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.large)
                    .stroke(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
    }
}
