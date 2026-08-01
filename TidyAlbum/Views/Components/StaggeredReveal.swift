import SwiftUI

// MARK: - Staggered Reveal ViewModifier

/// 基于 Apple Design 规范的延迟揭示修饰符。
/// 使用 critically damped 弹簧（damping 1.0, response 0.4）实现无 overshoot 的平滑入场，
/// 在减小动效模式下自动退化为纯 opacity 淡入（无位移）。
struct StaggeredReveal: ViewModifier {
    let isVisible: Bool
    let delay: Double
    let duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isVisible: Bool, delay: Double = 0, duration: Double = 0.4) {
        self.isVisible = isVisible
        self.delay = delay
        self.duration = duration
    }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 12)
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: duration, dampingFraction: 1.0).delay(delay),
                value: isVisible
            )
    }
}

extension View {
    /// 应用延迟揭示动画：critically damped 弹簧 + 轻微 Y 位移。
    /// 在减小动效模式下仅做 opacity 淡入，无位移。
    func staggeredReveal(
        isVisible: Bool,
        delay: Double = 0,
        duration: Double = 0.4
    ) -> some View {
        modifier(StaggeredReveal(isVisible: isVisible, delay: delay, duration: duration))
    }
}