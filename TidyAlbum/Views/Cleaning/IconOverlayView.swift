import SwiftUI

// MARK: - 拖拽叠加图标组件
/// 在卡片拖拽时显示的操作提示图标（删除、收藏、跳过）。
/// 透明度随拖拽距离动态变化。
struct IconOverlayView: View {

    // MARK: 属性

    /// SF Symbol 图标名称
    let icon: String
    /// 叠加层主题色
    let color: Color
    /// 操作文字标签
    let text: String

    // MARK: - Body

    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(DesignTokens.Typography.overlayIcon)
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Text(text)
                .font(.headline)
                .foregroundColor(DesignTokens.Colors.textPrimary)
        }
        .padding(DesignTokens.Spacing.section)
        .background(color.opacity(DesignTokens.Opacity.overlayBackground))
        .clipShape(Circle())
        .shadow(radius: 10)
    }
}