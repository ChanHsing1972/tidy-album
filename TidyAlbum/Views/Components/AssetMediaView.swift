import AVKit
import Photos
import SwiftUI

// MARK: - Cached Asset Media View

struct AssetMediaView: View {
    let asset: PHAsset
    var contentMode: ContentMode = .fit
    var showsVideoBadge = true
    var allowsPlayback = false
    var isActive = false

    @State private var image: UIImage?
    @State private var imageRequestID: PHImageRequestID?
    @State private var videoRequestID: PHImageRequestID?
    @State private var player: AVPlayer?
    @State private var requestedImageKey = ""
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                imageLayer
                if asset.mediaType == .video, allowsPlayback, isActive, let player {
                    VideoPlayer(player: player)
                        .transition(.opacity)
                } else if showsVideoBadge && asset.mediaType == .video {
                    videoBadge
                }
            }
            .clipped()
            .task(id: imageKey(size: proxy.size)) {
                loadImage(size: proxy.size)
            }
            .task(id: videoKey) {
                configureVideoPlaybackIfNeeded()
            }
            .onDisappear { cancelRequests() }
        }
    }

    // MARK: Presentation

    @ViewBuilder private var imageLayer: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
    }

    private var videoBadge: some View {
        Image(systemName: "play.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(.ultraThinMaterial, in: Circle())
            .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 0.5) }
    }

    // MARK: Image Loading

    private func imageKey(size: CGSize) -> String {
        "\(asset.localIdentifier)-\(Int(size.width))-\(Int(size.height))-\(contentMode == .fill)"
    }

    private func loadImage(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let key = imageKey(size: size)
        guard key != requestedImageKey else { return }
        requestedImageKey = key
        AssetImagePipeline.shared.cancel(imageRequestID)
        let targetSize = CGSize(width: size.width * displayScale, height: size.height * displayScale)
        let photoKitMode: PHImageContentMode = contentMode == .fill ? .aspectFill : .aspectFit
        if let cached = AssetImagePipeline.shared.cachedImage(
            for: asset,
            targetSize: targetSize,
            contentMode: photoKitMode
        ) {
            image = cached
            return
        }
        let requestedAssetID = asset.localIdentifier
        imageRequestID = AssetImagePipeline.shared.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: photoKitMode
        ) { loadedImage in
            guard requestedAssetID == asset.localIdentifier else { return }
            image = loadedImage
        }
    }

    // MARK: Video Playback

    private var videoKey: String {
        "\(asset.localIdentifier)-\(allowsPlayback)-\(isActive)"
    }

    private func configureVideoPlaybackIfNeeded() {
        player?.pause()
        player = nil
        if let videoRequestID {
            PHImageManager.default().cancelImageRequest(videoRequestID)
            self.videoRequestID = nil
        }
        guard asset.mediaType == .video, allowsPlayback, isActive else { return }
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        let requestedAssetID = asset.localIdentifier
        videoRequestID = PHImageManager.default().requestPlayerItem(
            forVideo: asset,
            options: options
        ) { item, _ in
            guard let item else { return }
            Task { @MainActor in
                guard requestedAssetID == asset.localIdentifier, isActive else { return }
                player = AVPlayer(playerItem: item)
            }
        }
    }

    private func cancelRequests() {
        AssetImagePipeline.shared.cancel(imageRequestID)
        if let videoRequestID { PHImageManager.default().cancelImageRequest(videoRequestID) }
        player?.pause()
        player = nil
    }
}
