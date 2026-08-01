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
                    ? .easeOut(duration: 0.18)
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

    func appleSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(AppleSurface(cornerRadius: cornerRadius))
    }
}

struct ApplePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.08)
                    : .spring(response: 0.22, dampingFraction: 1),
                value: configuration.isPressed
            )
    }
}

private struct AppleSurface: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var fillStyle: AnyShapeStyle {
        if reduceTransparency {
            AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
        } else {
            AnyShapeStyle(Material.regular)
        }
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillStyle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        Color.primary.opacity(contrast == .increased ? 0.32 : 0.08),
                        lineWidth: contrast == .increased ? 1 : 0.5
                    )
            }
    }
}
