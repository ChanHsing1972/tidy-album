import SwiftUI
import Inject

// MARK: - Welcome Onboarding (Apple Native Style)

/// 符合 Apple HIG 原生 iOS 欢迎页规范的引导页。
/// 结构：极简 Headline → 纵向 Feature List → 底部胶囊/大圆角主操作按钮。
/// 动效：Damping 1.0 / Response 0.4 Spring 弹簧动画 + 阶梯式 Staggered Reveal。
struct WelcomeView: View {
    @ObserveInjection var inject
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    // MARK: 阶梯式入场延迟 (Staggered Reveal)
    private let delayHeader     = 0.0
    private let delayFeatures   = 0.24
    private let delayButton     = 0.48

    var body: some View {
        let _ = inject
        ZStack(alignment: .bottom) {
            // 背景：系统默认背景色
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            // MARK: - Main Scroll Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    // 1. 顶部 Header (标题 + 核心标语)
                    welcomeHeader
                        .staggeredReveal(isVisible: isVisible, delay: delayHeader, reduceMotion: reduceMotion)

                    // 2. 核心功能列表
                    featureList
                        .staggeredReveal(isVisible: isVisible, delay: delayFeatures, reduceMotion: reduceMotion)
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, 32)
                .padding(.top, 56)
                .padding(.bottom, 120) // 为底部固定按钮留出空间
                .frame(maxWidth: .infinity)
            }

            // 3. 底部固定按钮及渐变蒙版
            bottomBar
                .staggeredReveal(isVisible: isVisible, delay: delayButton, reduceMotion: reduceMotion)
        }
        .onAppear {
            isVisible = true
        }
    }

    // MARK: - Header

    private var welcomeHeader: some View {
        VStack(spacing: 20) {
//            // 1. 应用图标 (Apple HIG 规范：64x64 圆角矩形 + 柔和阴影)
//            Image("tidy-album.icon") // 如果你的 AppIcon 在 Assets 中，或者换成 Image(systemName: "photo.stack.fill") 占位
//                .resizable()
//                .scaledToFit()
//                .frame(width: 64, height: 64)
//                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
//                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)

            // 2. 居中大标题
            Text(settings.t("Welcome to\nTidyAlbum"))
                .font(.system(size: 34, weight: .bold, design: .default))
                .tracking(-0.5) // Optical sizing: negative tracking for large titles
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 48)
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 32) {
            WelcomeFeatureRow(
                icon: "hand.draw.fill",
                color: .blue,
                title: settings.t("Swipe to Review"),
                description: settings.t("Swipe up to delete, down to favorite. Left and right to browse.")
            )

            WelcomeFeatureRow(
                icon: "lock.shield.fill",
                color: .green,
                title: settings.t("Private & Local"),
                description: settings.t("Everything stays on your device. No data is ever uploaded.")
            )

            WelcomeFeatureRow(
                icon: "shuffle",
                color: .indigo,
                title: settings.t("Random Review"),
                description: settings.t("Shuffle your library for a fresh, effortless review every time.")
            )

            WelcomeFeatureRow(
                icon: "chart.bar.xaxis",
                color: .orange,
                title: settings.t("Track Progress"),
                description: settings.t("See how much space you've reclaimed over time.")
            )
        }
        .padding(.leading, 10)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // 渐变过渡遮罩：让内容向下滚动时优雅淡出，不遮挡按钮
            LinearGradient(
                colors: [
                    Color(uiColor: .systemGroupedBackground).opacity(0),
                    Color(uiColor: .systemGroupedBackground).opacity(0.85),
                    Color(uiColor: .systemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)

            VStack {
                Button(action: { dismiss() }) {
                    Text(settings.t("Continue"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}

// MARK: - Feature Row Component

private struct WelcomeFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // 左侧 SF Symbol Icon (已增大到 46x46)
            Image(systemName: icon)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 46 , height: 46)
            
            // 右侧文本 Stack
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Helper Modifiers & Motion Styles

private extension View {
    func staggeredReveal(
        isVisible: Bool,
        delay: Double,
        reduceMotion: Bool
    ) -> some View {
        opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 16)
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.4, dampingFraction: 1.0).delay(delay),
                value: isVisible
            )
    }
}

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
