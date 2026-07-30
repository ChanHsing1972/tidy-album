import SwiftUI
import Photos

// MARK: - 清理界面视图 (Cleaning View)
/// 类 Tinder 卡片堆叠交互界面，支持上滑删除、下滑收藏、左右滑动跳过。
/// 是 App 的核心交互页面。
struct CleaningView: View {

    // MARK: 依赖

    @ObservedObject var manager: PhotoManager

    // MARK: 回调

    /// 完成所有照片清理后的回调
    var onFinish: () -> Void
    /// 返回首页的回调
    var onBack: () -> Void
    /// 打开垃圾桶的回调
    var onShowTrash: () -> Void

    // MARK: 状态

    @State private var currentIndex = 0
    @State private var offset: CGSize = .zero
    @State private var isDragging = false

    /// 触觉反馈生成器
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - 计算属性

    /// 拖拽进度 (0.0 ~ 1.0)，用于驱动叠加图标的透明度
    private var dragProgress: Double {
        let distance = sqrt(pow(offset.width, 2) + pow(offset.height, 2))
        return min(Double(distance / AnimationPresets.overlayMaxDistance), 1.0)
    }

    /// 当前拖拽的主导方向
    private var dominantDirection: DragDirection {
        if offset == .zero { return .none }
        if abs(offset.height) > abs(offset.width) {
            return offset.height < 0 ? .up : .down
        } else {
            return offset.width < 0 ? .left : .right
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundBlur
            VStack {
                topBar
                Spacer()
                cardStack
                Spacer()
                bottomControls
            }
        }
    }

    // MARK: - 背景模糊 (Background Blur)

    @ViewBuilder
    private var backgroundBlur: some View {
        if currentIndex < manager.assets.count {
            AssetMediaView(asset: manager.assets[currentIndex])
                .blur(radius: 50)
                .opacity(DesignTokens.Opacity.blurredBackground)
                .ignoresSafeArea()
        }
    }

    // MARK: - 顶部栏 (Top Bar)

    @ViewBuilder
    private var topBar: some View {
        if currentIndex < manager.assets.count {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "xmark")
                        .font(.system(size: DesignTokens.FontSize.button, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .padding(DesignTokens.Spacing.standard)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                Spacer()

                Text("\(currentIndex + 1) / \(manager.assets.count)")
                    .font(DesignTokens.Typography.monospacedFont(size: DesignTokens.FontSize.body))
                    .foregroundColor(DesignTokens.Colors.textMuted)
                    .padding(.horizontal, DesignTokens.Spacing.standard)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(DesignTokens.CornerRadius.small)

                Spacer()

                Button(action: onShowTrash) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("\(manager.trashBin.count)")
                    }
                    .font(.system(size: DesignTokens.FontSize.body, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .padding(.horizontal, DesignTokens.Spacing.standard)
                    .padding(.vertical, DesignTokens.Spacing.compact)
                    .background(
                        manager.trashBin.isEmpty
                            ? DesignTokens.Colors.textPrimary.opacity(DesignTokens.Opacity.materialBackground)
                            : DesignTokens.Colors.accentRed
                    )
                    .cornerRadius(DesignTokens.Spacing.large)
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
        }
    }

    // MARK: - 卡片堆叠 (Card Stack)

    private var cardStack: some View {
        ZStack {
            if manager.assets.isEmpty {
                emptyFilterView
            } else if currentIndex >= manager.assets.count {
                allCaughtUpView
            } else {
                nextCardPreview
                currentCard
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.relaxed)
        .frame(maxHeight: DesignTokens.Dimensions.cardStackMaxHeight)
    }

    // MARK: 空筛选视图

    private var emptyFilterView: some View {
        VStack(spacing: DesignTokens.Spacing.large) {
            Text("No photos in this filter")
                .foregroundColor(DesignTokens.Colors.textPrimary)
            Button("Back to Home", action: onBack)
                .padding()
                .background(DesignTokens.Colors.textPrimary)
                .foregroundColor(DesignTokens.Colors.textOnPrimary)
                .cornerRadius(DesignTokens.CornerRadius.medium)
        }
    }

    // MARK: 全部完成视图

    private var allCaughtUpView: some View {
        VStack(spacing: DesignTokens.Spacing.large) {
            Image(systemName: "checkmark.circle.fill")
                .font(DesignTokens.Typography.completeIcon)
                .foregroundStyle(DesignTokens.Colors.gradientComplete)

            Text("All Caught Up!")
                .font(.title2)
                .foregroundColor(DesignTokens.Colors.textPrimary)

            Button("Finish Review", action: onFinish)
                .padding()
                .background(DesignTokens.Colors.textPrimary)
                .foregroundColor(DesignTokens.Colors.textOnPrimary)
                .cornerRadius(DesignTokens.CornerRadius.medium)
        }
    }

    // MARK: 下一张卡片预览

    @ViewBuilder
    private var nextCardPreview: some View {
        if currentIndex + 1 < manager.assets.count {
            CardView(asset: manager.assets[currentIndex + 1], manager: manager)
                .scaleEffect(
                    AnimationPresets.nextCardBaseScale + (AnimationPresets.nextCardScaleRange * dragProgress)
                )
                .offset(y: AnimationPresets.nextCardBaseOffsetY * (1.0 - dragProgress))
                .opacity(
                    DesignTokens.Opacity.nextCardPreview + (DesignTokens.Opacity.gradientMid * dragProgress)
                )
                .zIndex(0)
                .id(manager.assets[currentIndex + 1].localIdentifier)
        }
    }

    // MARK: 当前卡片

    private var currentCard: some View {
        CardView(asset: manager.assets[currentIndex], manager: manager)
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width / AnimationPresets.cardRotationFactor)))
            .scaleEffect(isDragging ? AnimationPresets.draggingCardScale : 1.0)
            .gesture(dragGesture)
            .overlay(dragOverlayIcons)
            .zIndex(1)
            .id(manager.assets[currentIndex].localIdentifier)
    }

    // MARK: - 拖拽手势 (Drag Gesture)

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { gesture in
                isDragging = true
                offset = gesture.translation
            }
            .onEnded { gesture in
                isDragging = false
                handleSwipe(translation: gesture.translation)
            }
    }

    // MARK: - 拖拽叠加图标 (Drag Overlay Icons)

    private var dragOverlayIcons: some View {
        let currentAsset = manager.assets[currentIndex]
        let isFavorite = currentAsset.isFavorite

        return ZStack {
            // 上滑 → 删除
            IconOverlayView(icon: "trash.fill", color: DesignTokens.Colors.accentRed, text: "DELETE")
                .offset(y: 50)
                .opacity(
                    dominantDirection == .up
                        ? min(Double(-offset.height) / AnimationPresets.overlayMaxDistance, 1.0)
                        : 0
                )

            // 下滑 → 收藏/取消收藏
            IconOverlayView(
                icon: isFavorite ? "heart.slash.fill" : "heart.fill",
                color: DesignTokens.Colors.accentPink,
                text: isFavorite ? "UNFAVORITE" : "FAVORITE"
            )
            .offset(y: -50)
            .opacity(
                dominantDirection == .down
                    ? min(Double(offset.height) / AnimationPresets.overlayMaxDistance, 1.0)
                    : 0
            )

            // 左右滑 → 跳过
            IconOverlayView(icon: "arrow.right", color: DesignTokens.Colors.accentBlue, text: "SKIP")
                .opacity(
                    (dominantDirection == .left || dominantDirection == .right)
                        ? min(Double(abs(offset.width)) / AnimationPresets.overlayMaxDistance, 1.0)
                        : 0
                )
        }
        .animation(AnimationPresets.overlayIconSwitch, value: dominantDirection)
    }

    // MARK: - 底部控制栏 (Bottom Controls)

    @ViewBuilder
    private var bottomControls: some View {
        if currentIndex < manager.assets.count {
            HStack(spacing: DesignTokens.Spacing.extraLarge) {
                ControlButtonView(
                    icon: "arrow.uturn.backward",
                    color: DesignTokens.Colors.accentYellow,
                    action: undoCurrentPhoto,
                    isDisabled: currentIndex == 0
                )

                ControlButtonView(
                    icon: "trash",
                    color: DesignTokens.Colors.accentRed
                ) {
                    handleSwipe(translation: CGSize(width: 0, height: -AnimationPresets.flyOutDistance))
                }

                ControlButtonView(
                    icon: "heart",
                    color: DesignTokens.Colors.accentPink
                ) {
                    handleSwipe(translation: CGSize(width: 0, height: AnimationPresets.flyOutDistance))
                }
            }
            .padding(.bottom, DesignTokens.Dimensions.bottomControlPadding)
        }
    }

    // MARK: - 手势处理 (Swipe Handling)

    /// 根据拖拽位移判断操作类型并执行动画
    private func handleSwipe(translation: CGSize) {
        let threshold = AnimationPresets.swipeThreshold
        let currentAsset = manager.assets[currentIndex]

        if translation.height < -threshold {
            // 上滑 → 删除
            impactFeedback.impactOccurred()
            flyOutCard(direction: CGSize(width: 0, height: -AnimationPresets.flyOutDistance)) {
                manager.addToTrash(asset: currentAsset)
                advanceToNextPhoto()
            }
        } else if translation.height > threshold {
            // 下滑 → 收藏/取消收藏
            impactFeedback.impactOccurred()
            flyOutCard(direction: CGSize(width: 0, height: AnimationPresets.flyOutDistance)) {
                manager.toggleFavorite(asset: currentAsset)
                advanceToNextPhoto()
            }
        } else if abs(translation.width) > threshold {
            // 左右滑 → 跳过
            let xDirection: CGFloat = translation.width > 0
                ? AnimationPresets.flyOutDistance
                : -AnimationPresets.flyOutDistance
            flyOutCard(direction: CGSize(width: xDirection, height: 0)) {
                advanceToNextPhoto()
            }
        } else {
            // 回弹
            withAnimation(AnimationPresets.cardFlyOut) {
                offset = .zero
            }
        }
    }

    /// 回退到上一张照片
    private func undoCurrentPhoto() {
        guard currentIndex > 0 else { return }
        withAnimation {
            currentIndex -= 1
            offset = .zero
        }
    }

    /// 推进到下一张照片
    private func advanceToNextPhoto() {
        currentIndex += 1
        offset = .zero
    }

    /// 卡片飞出屏幕动画
    private func flyOutCard(direction: CGSize, completion: @escaping () -> Void) {
        withAnimation(AnimationPresets.cardFlyOut) {
            offset = direction
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + AnimationPresets.cardFlyOutDelay) {
            completion()
        }
    }
}

// MARK: - 拖拽方向枚举 (Drag Direction)

extension CleaningView {
    /// 表示卡片拖拽的主导方向
    enum DragDirection {
        case none
        case left
        case right
        case up
        case down
    }
}