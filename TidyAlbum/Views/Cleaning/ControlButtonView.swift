import SwiftUI

// MARK: - 控制按钮组件
/// 清理界面底部圆形操作按钮（撤销、删除、收藏）。
struct ControlButtonView: View {

    // MARK: 属性

    /// SF Symbol 图标名称
    let icon: String
    /// 按钮主题色
    let color: Color
    /// 点击回调
    let action: () -> Void

    /// 是否禁用
    var isDisabled: Bool = false

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.controlIcon)
                .foregroundColor(color)
                .frame(
                    width: DesignTokens.Dimensions.controlButtonSize,
                    height: DesignTokens.Dimensions.controlButtonSize
                )
                .background(DesignTokens.Colors.textPrimary)
                .clipShape(Circle())
                .shadow(
                    color: color.opacity(DesignTokens.Opacity.materialBackground),
                    radius: DesignTokens.Shadow.controlButton.radius,
                    x: DesignTokens.Shadow.controlButton.x,
                    y: DesignTokens.Shadow.controlButton.y
                )
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? DesignTokens.Opacity.materialBackground : 1.0)
    }
}