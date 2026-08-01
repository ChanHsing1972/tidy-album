import SwiftUI

// MARK: - 设计令牌 (Design Tokens)
/// 全局设计令牌，统一管理应用中所有视觉常量。
/// 包含颜色、排版、布局、材质等设计决策。
enum DesignTokens {

    // MARK: - 间距 (Spacing)

    /// 标准间距常量，按设计系统 4pt 网格递增
    enum Spacing {
        /// 紧凑间距 (8pt)
        static let compact: CGFloat = 8
        /// 标准间距 (12pt)
        static let standard: CGFloat = 12
        /// 宽松间距 (16pt)
        static let relaxed: CGFloat = 16
        /// 大间距 (20pt)
        static let large: CGFloat = 20
        /// 区块间距 (30pt)
        static let section: CGFloat = 30
        /// 超大间距 (40pt)
        static let extraLarge: CGFloat = 40
    }

    // MARK: - 圆角 (Corner Radius)

    enum CornerRadius {
        /// 小圆角 (12pt) — 用于标签、小按钮
        static let small: CGFloat = 12
        /// 中等圆角 (16pt) — 用于次级卡片
        static let medium: CGFloat = 16
        /// 大圆角 (24pt) — 用于主卡片
        static let large: CGFloat = 24
        /// 超大圆角 (28pt) — 用于底部按钮
        static let xLarge: CGFloat = 28
        /// 全圆角 (32pt) — 用于主操作按钮
        static let full: CGFloat = 32
    }

    // MARK: - 尺寸 (Dimensions)

    enum Dimensions {
        /// 筛选卡片宽度
        static let filterCardWidth: CGFloat = 140
        /// 筛选卡片高度
        static let filterCardHeight: CGFloat = 140
        /// 主操作按钮高度
        static let primaryButtonHeight: CGFloat = 64
        /// 次要操作按钮高度
        static let secondaryButtonHeight: CGFloat = 56
        /// 圆形控制按钮尺寸
        static let controlButtonSize: CGFloat = 60
        /// 垃圾桶按钮尺寸
        static let trashButtonSize: CGFloat = 44
        /// 摘要图标圆形背景尺寸
        static let summaryIconCircleSize: CGFloat = 150
        /// 卡片堆叠最大高度
        static let cardStackMaxHeight: CGFloat = 600
        /// 卡片底部渐变遮罩高度
        static let gradientMaskHeight: CGFloat = 200
        /// 卡片底部内边距
        static let cardBottomPadding: CGFloat = 40
        /// 底部控制栏内边距
        static let bottomControlPadding: CGFloat = 30
        /// 网格最小列宽
        static let gridMinimumColumnWidth: CGFloat = 100
    }

    // MARK: - 阴影 (Shadow)

    enum Shadow {
        /// 卡片阴影
        static let card: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) =
            (.black.opacity(0.2), 20, 0, 10)
        /// 发光按钮阴影
        static let glowButton: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) =
            (.white.opacity(0.2), 20, 0, 10)
        /// 控制按钮阴影
        static let controlButton: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) =
            (.pink.opacity(0.3), 10, 0, 5)
    }

    // MARK: - 透明度 (Opacity)

    enum Opacity {
        /// 模糊背景
        static let blurredBackground: CGFloat = 0.5
        /// 下一张卡片预览
        static let nextCardPreview: CGFloat = 0.6
        /// 渐变遮罩中层
        static let gradientMid: CGFloat = 0.6
        /// 渐变遮罩底层
        static let gradientBottom: CGFloat = 0.9
        /// 分隔线
        static let divider: CGFloat = 0.2
        /// 禁用状态
        static let disabled: CGFloat = 0.3
        /// 叠加图标背景
        static let overlayBackground: CGFloat = 0.8
        /// 次要文字
        static let textSecondary: CGFloat = 0.8
        /// 材质背景
        static let materialBackground: CGFloat = 0.3
        /// 卡片边框
        static let cardBorder: CGFloat = 0.1
        /// 标题渐变中
        static let titleGradientMid: CGFloat = 0.8
    }

    // MARK: - 字体大小 (Font Sizes)

    enum FontSize {
        /// 标注文字 (12pt)
        static let caption: CGFloat = 12
        /// 正文 (14pt)
        static let body: CGFloat = 14
        /// 副标题 (16pt)
        static let subheadline: CGFloat = 16
        /// 按钮文字 (18pt)
        static let button: CGFloat = 18
        /// 标题三 (20pt)
        static let title3: CGFloat = 20
        /// 标题二 (24pt)
        static let title2: CGFloat = 24
        /// 大标题 (32pt)
        static let largeTitle: CGFloat = 32
        /// 超大标题 (34pt)
        static let hero: CGFloat = 34
        /// 展示数字 (40pt)
        static let display: CGFloat = 40
        /// 覆盖图标 (50pt)
        static let overlayIcon: CGFloat = 50
        /// 锁屏图标 (60pt)
        static let lockIcon: CGFloat = 60
        /// 完成图标 (80pt)
        static let completeIcon: CGFloat = 80
    }

    // MARK: - 字体设计

    /// 应用中统一使用的字体设计风格
    static let fontDesign: Font.Design = .rounded

    // MARK: - 弹簧参数 (Apple Design 规范)

    /// 弹簧动画参数，遵循 Apple "Designing Fluid Interfaces" 规范。
    /// 使用 damping ratio + response 替代 mass/stiffness/damping 三元组。
    enum Spring {
        /// 默认 UI 弹簧 — critically damped (damping 1.0)，无 overshoot。
        /// 用于大多数 UI 元素：按钮、卡片、文字入场。
        /// 对应 Apple 的 Move/Reposition 参数。
        static let `default`: (damping: Double, response: Double) = (1.0, 0.35)

        /// 动量交互弹簧 — 轻微 bounce (damping 0.8)。
        /// 仅用于手势驱动或动量来源的过渡：图标弹入、弹性缩放。
        /// 对应 Apple 的 Drawer/Sheet 参数。
        static let momentum: (damping: Double, response: Double) = (0.8, 0.35)

        /// 入场弹簧 — critically damped，稍慢 (response 0.45)。
        /// 用于页面级元素首次出现，营造沉稳的开场感。
        static let entrance: (damping: Double, response: Double) = (1.0, 0.45)
    }

    // MARK: - 排版追踪 (Apple Design 规范 — size-specific tracking)

    /// 字号相关的 letter-spacing 参数。
    /// 大字号需要负追踪（字母间距视觉上过大），小字号需要正追踪（提升可读性）。
    enum Tracking {
        /// 大标题负追踪 — 字号 ≥ 28pt 的 display 文字
        static let display: CGFloat = -0.02
        /// 中标题微负追踪 — 字号 20–27pt 的标题文字
        static let title: CGFloat = -0.01
        /// 正文标准追踪 — 字号 13–19pt
        static let body: CGFloat = 0
        /// 小字正追踪 — 字号 ≤ 12pt 的辅助文字
        static let caption: CGFloat = 0.01
    }
}

// MARK: - 颜色扩展 (Color Palette)

extension DesignTokens {
    /// 应用中使用的颜色语义映射
    enum Colors {
        // 背景
        static let appBackground = Color.black
        static let cardBackground = Color(uiColor: .secondarySystemBackground)

        // 文本
        static let textPrimary = Color.white
        static let textSecondary = Color.gray
        static let textMuted = Color.white.opacity(Opacity.textSecondary)
        static let textOnPrimary = Color.black

        // 强调色
        static let accentBlue = Color.blue
        static let accentPink = Color.pink
        static let accentRed = Color.red
        static let accentYellow = Color.yellow
        static let accentGreen = Color.green
        static let accentMint = Color.mint
        static let accentOrange = Color.orange

        // 标题渐变
        static let gradientTitle = LinearGradient(
            colors: [.white, .blue.opacity(Opacity.titleGradientMid)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // 完成图标渐变
        static let gradientComplete = LinearGradient(
            colors: [.green, .mint],
            startPoint: .top,
            endPoint: .bottom
        )

        // 闪亮图标渐变
        static let gradientSparkle = LinearGradient(
            colors: [.yellow, .orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // 分隔线
        static let divider = Color.white.opacity(Opacity.divider)
    }
}

// MARK: - 排版辅助方法 (Typography Helpers)

extension DesignTokens {
    /// 提供标准化的字体创建方法，确保全应用排版一致性
    enum Typography {
        /// 创建圆角设计的系统字体
        static func roundedFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: fontDesign)
        }

        /// 等宽字体 (用于进度指示器)
        static func monospacedFont(size: CGFloat) -> Font {
            .system(.subheadline, design: .monospaced)
        }

        // MARK: 预设样式

        static let hero = roundedFont(size: FontSize.hero, weight: .bold)
        static let largeTitle = roundedFont(size: FontSize.largeTitle, weight: .bold)
        static let title2 = roundedFont(size: FontSize.title2, weight: .bold)
        static let title3 = roundedFont(size: FontSize.title3, weight: .bold)
        static let headline = roundedFont(size: FontSize.button, weight: .bold)
        static let body = roundedFont(size: FontSize.subheadline, weight: .medium)
        static let caption = roundedFont(size: FontSize.caption)
        static let displayNumber = roundedFont(size: FontSize.display, weight: .bold)
        static let heroNumber: Font = .system(size: 52, weight: .bold, design: .rounded)
        static let controlIcon: Font = .title2
        static let statIcon: Font = .title2
        static let cardIcon: Font = .title
        static let overlayIcon: Font = .system(size: FontSize.overlayIcon)
        static let lockIcon: Font = .system(size: FontSize.lockIcon)
        static let completeIcon: Font = .system(size: FontSize.completeIcon)
        static let trashIcon: Font = .system(size: FontSize.lockIcon)
    }
}