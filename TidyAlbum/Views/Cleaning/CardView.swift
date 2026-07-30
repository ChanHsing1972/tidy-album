import SwiftUI
import Photos

// MARK: - 照片卡片组件 (Card View)
/// 展示单张照片/视频的卡片视图，包含媒体预览、渐变遮罩和元信息。
/// 用作清理界面中卡片堆叠的核心视觉单元。
struct CardView: View {

    // MARK: 属性

    /// 照片资源
    let asset: PHAsset
    /// 照片管理器（用于获取资产状态）
    @ObservedObject var manager: PhotoManager

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 媒体层
                AssetMediaView(asset: asset)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                // 渐变遮罩
                LinearGradient(
                    colors: [
                        .clear,
                        DesignTokens.Colors.appBackground.opacity(DesignTokens.Opacity.gradientMid),
                        DesignTokens.Colors.appBackground.opacity(DesignTokens.Opacity.gradientBottom)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: DesignTokens.Dimensions.gradientMaskHeight)

                // 信息层
                infoOverlay
            }
            .background(DesignTokens.Colors.cardBackground)
            .cornerRadius(DesignTokens.CornerRadius.full)
            .shadow(
                color: DesignTokens.Shadow.card.color,
                radius: DesignTokens.Shadow.card.radius,
                x: DesignTokens.Shadow.card.x,
                y: DesignTokens.Shadow.card.y
            )
        }
    }

    // MARK: - 信息叠加层 (Info Overlay)

    private var infoOverlay: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                Text(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
                    .font(DesignTokens.Typography.title3)
                    .foregroundColor(DesignTokens.Colors.textPrimary)

                HStack(spacing: DesignTokens.Spacing.standard) {
                    Label("\(asset.pixelWidth) × \(asset.pixelHeight)", systemImage: "aspectratio")

                    if asset.mediaType == .video {
                        Label(formatDuration(asset.duration), systemImage: "play.circle.fill")
                    }
                }
                .font(DesignTokens.Typography.caption)
                .foregroundColor(DesignTokens.Colors.textMuted)
            }

            Spacer()

            if asset.isFavorite {
                Image(systemName: "heart.fill")
                    .font(DesignTokens.Typography.cardIcon)
                    .foregroundColor(DesignTokens.Colors.accentPink)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .padding(DesignTokens.Spacing.large)
        .padding(.bottom, DesignTokens.Dimensions.cardBottomPadding)
    }

    // MARK: - 辅助方法 (Helpers)

    /// 将视频时长格式化为 `分:秒` 格式
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
}