import SwiftUI
import Photos
import AVKit

// MARK: - 媒体资源展示组件
/// 通用的照片/视频预览组件，支持异步加载和自动播放。
/// 可被卡片视图、网格视图、垃圾桶视图等多处复用。
struct AssetMediaView: View {

    // MARK: 属性

    /// 待展示的照片资源
    let asset: PHAsset

    // MARK: 状态

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @Environment(\.displayScale) private var displayScale

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DesignTokens.Colors.cardBackground

                if asset.mediaType == .video {
                    videoContent
                } else {
                    imageContent(in: geometry)
                }
            }
            .onAppear {
                loadMedia(targetSize: geometry.size)
            }
            .onChange(of: asset.localIdentifier) { _, _ in
                resetAndReload(targetSize: geometry.size)
            }
        }
    }

    // MARK: - 视频内容 (Video Content)

    @ViewBuilder
    private var videoContent: some View {
        if let player {
            VideoPlayer(player: player)
                .disabled(true)
                .onAppear {
                    player.play()
                    player.isMuted = true
                    setupVideoLoop(for: player)
                }
                .onDisappear {
                    player.pause()
                }
        } else {
            ProgressView()
        }
    }

    // MARK: - 图片内容 (Image Content)

    @ViewBuilder
    private func imageContent(in geometry: GeometryProxy) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .transition(.opacity.animation(AnimationPresets.imageFadeIn))
        } else {
            ProgressView()
        }
    }

    // MARK: - 媒体加载 (Media Loading)

    /// 重置状态并重新加载媒体
    private func resetAndReload(targetSize: CGSize) {
        image = nil
        player = nil
        loadMedia(targetSize: targetSize)
    }

    /// 根据资源类型异步加载图片或视频
    private func loadMedia(targetSize: CGSize) {
        if asset.mediaType == .video {
            loadVideo()
        } else {
            loadImage(targetSize: targetSize)
        }
    }

    private func loadVideo() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            guard let item else { return }
            DispatchQueue.main.async {
                self.player = AVPlayer(playerItem: item)
            }
        }
    }

    private func loadImage(targetSize: CGSize) {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        let scaledSize = CGSize(
            width: targetSize.width * displayScale,
            height: targetSize.height * displayScale
        )

        manager.requestImage(
            for: asset,
            targetSize: scaledSize,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            guard let result else { return }
            withAnimation(AnimationPresets.imageFadeIn) {
                self.image = result
            }
        }
    }

    // MARK: - 视频循环 (Video Loop)

    /// 设置视频循环播放
    private func setupVideoLoop(for player: AVPlayer) {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
    }
}