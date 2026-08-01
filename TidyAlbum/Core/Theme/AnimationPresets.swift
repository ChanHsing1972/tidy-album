import SwiftUI

// MARK: - 动画预设 (Animation Presets)
/// 统一管理应用中所有动画参数，确保交互体验一致。
/// 避免在视图中散落硬编码的动画数值。
enum AnimationPresets {

    // MARK: - 弹簧动画 (Spring Animations)

    /// 页面转场动画 — 响应稍慢，阻尼适中，适合页面级切换
    static let pageTransition: Animation = .spring(
        response: 0.4,
        dampingFraction: 1
    )

    /// 卡片飞出动画 — 响应快，阻尼低，视觉冲击力适合滑动手势
    static let cardFlyOut: Animation = .spring(
        response: 0.4,
        dampingFraction: 0.8
    )

    // MARK: - 缓动动画 (Ease Animations)

    /// 图片加载淡入动画
    static let imageFadeIn: Animation = .easeOut(duration: 0.2)

    /// 拖拽叠加图标切换动画
    static let overlayIconSwitch: Animation = .easeInOut(duration: 0.2)

    // MARK: - 转场效果 (Transitions)

    /// 页面出现转场 — 淡入 + 轻微缩放
    static let appearTransition: AnyTransition = .opacity
        .combined(with: .scale(scale: 0.9))

    /// 从右侧滑入转场
    static let slideFromTrailing: AnyTransition = .move(edge: .trailing)

    /// 从底部滑入转场
    static let slideFromBottom: AnyTransition = .move(edge: .bottom)

    // MARK: - 时间常量 (Timing Constants)

    /// 卡片飞出动画后的延迟，用于在动画完成后更新数据
    static let cardFlyOutDelay: TimeInterval = 0.2

    // MARK: - 拖拽阈值 (Drag Thresholds)

    /// 触发滑动手势的最小距离
    static let swipeThreshold: CGFloat = 100

    /// 拖拽叠加图标完全显示的最大距离
    static let overlayMaxDistance: CGFloat = 150

    /// 卡片飞出屏幕的距离
    static let flyOutDistance: CGFloat = 1000

    /// 触发触觉反馈的最小拖拽距离
    static let hapticThreshold: CGFloat = 100

    // MARK: - 卡片堆叠动态参数

    /// 下一张卡片的基础缩放比例
    static let nextCardBaseScale: CGFloat = 0.92

    /// 下一张卡片的最大缩放增量
    static let nextCardScaleRange: CGFloat = 0.08

    /// 下一张卡片的基础 Y 偏移
    static let nextCardBaseOffsetY: CGFloat = 30

    /// 当前卡片拖拽时的缩放比例
    static let draggingCardScale: CGFloat = 0.95

    /// 卡片旋转系数 (基于水平偏移量)
    static let cardRotationFactor: CGFloat = 15
}
