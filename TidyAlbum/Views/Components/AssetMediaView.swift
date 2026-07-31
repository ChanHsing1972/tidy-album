import AVFoundation
import Photos
import PhotosUI
import SwiftUI

struct AssetMediaView: View {
    let asset: PHAsset
    var contentMode: ContentMode = .fit
    var showsVideoBadge = true
    var allowsPlayback = false
    var isActive = false

    @State private var image: UIImage?
    @State private var imageRequestID: PHImageRequestID?
    @State private var requestedImageKey = ""
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                imageLayer
                playbackLayer(size: proxy.size)
                if showsVideoBadge, asset.mediaType == .video, !(allowsPlayback && isActive) {
                    videoBadge
                }
            }
            .clipped()
            .task(id: imageKey(size: proxy.size)) { loadImage(size: proxy.size) }
            .onDisappear { cancelImageRequest() }
        }
    }

    @ViewBuilder private var imageLayer: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.animation(.easeOut(duration: 0.18)))
        }
    }

    @ViewBuilder private func playbackLayer(size: CGSize) -> some View {
        if allowsPlayback, asset.mediaType == .video {
            LoopingAssetVideoView(asset: asset, isActive: isActive)
                .opacity(isActive ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isActive)
        } else if allowsPlayback, asset.mediaSubtypes.contains(.photoLive) {
            AssetLivePhotoView(asset: asset, targetSize: pixelSize(for: size), isActive: isActive)
                .opacity(isActive ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isActive)
        }
    }

    private var videoBadge: some View {
        Image(systemName: "play.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(.ultraThinMaterial, in: Circle())
            .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 0.5) }
            .allowsHitTesting(false)
    }

    private func imageKey(size: CGSize) -> String {
        "\(asset.localIdentifier)-\(Int(size.width))x\(Int(size.height))-\(contentMode == .fill)"
    }

    private func pixelSize(for size: CGSize) -> CGSize {
        CGSize(width: max(size.width * displayScale, 1), height: max(size.height * displayScale, 1))
    }

    private func loadImage(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let key = imageKey(size: size)
        guard key != requestedImageKey else { return }
        requestedImageKey = key
        AssetImagePipeline.shared.cancel(imageRequestID)
        imageRequestID = nil
        let targetSize = pixelSize(for: size)
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
            withAnimation(.easeOut(duration: 0.18)) { image = loadedImage }
        }
    }

    private func cancelImageRequest() {
        AssetImagePipeline.shared.cancel(imageRequestID)
        imageRequestID = nil
    }
}

private struct LoopingAssetVideoView: UIViewRepresentable {
    let asset: PHAsset
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        context.coordinator.attach(to: view)
        context.coordinator.update(asset: asset, isActive: isActive)
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        context.coordinator.attach(to: uiView)
        context.coordinator.update(asset: asset, isActive: isActive)
    }

    static func dismantleUIView(_ uiView: PlayerSurfaceView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    final class Coordinator {
        private weak var surface: PlayerSurfaceView?
        private var assetIdentifier = ""
        private var requestID: PHImageRequestID?
        private var queuePlayer: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var isActive = false

        func attach(to surface: PlayerSurfaceView) {
            self.surface = surface
            surface.playerLayer.videoGravity = .resizeAspectFill
        }

        func update(asset: PHAsset, isActive: Bool) {
            self.isActive = isActive
            if assetIdentifier != asset.localIdentifier {
                requestPlayer(for: asset)
            } else {
                updatePlayback()
            }
        }

        private func requestPlayer(for asset: PHAsset) {
            tearDownPlayer()
            assetIdentifier = asset.localIdentifier
            let requestedIdentifier = asset.localIdentifier
            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true
            requestID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
                guard let item else { return }
                DispatchQueue.main.async {
                    guard let self, self.assetIdentifier == requestedIdentifier else { return }
                    let player = AVQueuePlayer()
                    player.isMuted = true
                    player.actionAtItemEnd = .none
                    self.queuePlayer = player
                    self.looper = AVPlayerLooper(player: player, templateItem: item)
                    self.surface?.playerLayer.player = player
                    self.updatePlayback()
                }
            }
        }

        private func updatePlayback() {
            if isActive { queuePlayer?.play() }
            else { queuePlayer?.pause() }
        }

        private func tearDownPlayer() {
            if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
            requestID = nil
            queuePlayer?.pause()
            surface?.playerLayer.player = nil
            looper = nil
            queuePlayer = nil
        }

        func tearDown() {
            tearDownPlayer()
            assetIdentifier = ""
        }
    }
}

private final class PlayerSurfaceView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct AssetLivePhotoView: UIViewRepresentable {
    let asset: PHAsset
    let targetSize: CGSize
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFill
        view.isMuted = true
        view.delegate = context.coordinator
        context.coordinator.attach(to: view)
        context.coordinator.update(asset: asset, targetSize: targetSize, isActive: isActive)
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        context.coordinator.attach(to: uiView)
        context.coordinator.update(asset: asset, targetSize: targetSize, isActive: isActive)
    }

    static func dismantleUIView(_ uiView: PHLivePhotoView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        private weak var view: PHLivePhotoView?
        private var assetIdentifier = ""
        private var requestID: PHImageRequestID?
        private var isActive = false
        private var hasLivePhoto = false

        func attach(to view: PHLivePhotoView) {
            self.view = view
            view.delegate = self
        }

        func update(asset: PHAsset, targetSize: CGSize, isActive: Bool) {
            let wasActive = self.isActive
            self.isActive = isActive
            if assetIdentifier != asset.localIdentifier {
                request(asset: asset, targetSize: targetSize)
            } else if isActive, !wasActive, hasLivePhoto {
                view?.startPlayback(with: .full)
            } else if !isActive, wasActive {
                view?.stopPlayback()
            }
        }

        private func request(asset: PHAsset, targetSize: CGSize) {
            tearDownRequest()
            assetIdentifier = asset.localIdentifier
            hasLivePhoto = false
            let requestedIdentifier = asset.localIdentifier
            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            requestID = PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { [weak self] livePhoto, info in
                guard let livePhoto else { return }
                DispatchQueue.main.async {
                    guard let self, self.assetIdentifier == requestedIdentifier else { return }
                    self.view?.livePhoto = livePhoto
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    self.hasLivePhoto = !degraded
                    if self.isActive { self.view?.startPlayback(with: .full) }
                }
            }
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            guard isActive else { return }
            DispatchQueue.main.async { [weak self, weak livePhotoView] in
                guard let self, self.isActive else { return }
                livePhotoView?.startPlayback(with: .full)
            }
        }

        private func tearDownRequest() {
            if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
            requestID = nil
        }

        func tearDown() {
            tearDownRequest()
            view?.stopPlayback()
            view?.livePhoto = nil
            assetIdentifier = ""
            hasLivePhoto = false
        }
    }
}
