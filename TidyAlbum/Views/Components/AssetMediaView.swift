import AVKit
import Photos
import PhotosUI
import SwiftUI
import Inject

struct AssetMediaView: View {
    @ObserveInjection var inject
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
        let _ = inject
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
                .transition(.opacity)
        }
    }

    @ViewBuilder private func playbackLayer(size: CGSize) -> some View {
        if allowsPlayback, isActive, asset.mediaType == .video {
            AssetVideoPlayerView(asset: asset, contentMode: contentMode, isActive: isActive)
        } else if allowsPlayback, isActive, asset.mediaSubtypes.contains(.photoLive) {
            AssetLivePhotoView(asset: asset, targetSize: pixelSize(for: size), isActive: isActive)
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
        let shouldFadeIn = image == nil
        imageRequestID = AssetImagePipeline.shared.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: photoKitMode
        ) { loadedImage, isFinal in
            guard requestedAssetID == asset.localIdentifier, requestedImageKey == key else { return }
            if isFinal { imageRequestID = nil }
            if shouldFadeIn, image == nil {
                withAnimation(.easeOut(duration: 0.16)) { image = loadedImage }
            } else {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) { image = loadedImage }
            }
        }
    }

    private func cancelImageRequest() {
        AssetImagePipeline.shared.cancel(imageRequestID)
        imageRequestID = nil
        requestedImageKey = ""
    }
}

private struct AssetVideoPlayerView: UIViewControllerRepresentable {
    let asset: PHAsset
    let contentMode: ContentMode
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.speeds = [
            AVPlaybackSpeed(rate: 0.5, localizedName: "0.5×"),
            AVPlaybackSpeed(rate: 1, localizedName: "1×"),
            AVPlaybackSpeed(rate: 1.5, localizedName: "1.5×"),
            AVPlaybackSpeed(rate: 2, localizedName: "2×")
        ]
        controller.view.backgroundColor = .clear
        context.coordinator.attach(to: controller)
        context.coordinator.update(asset: asset, contentMode: contentMode, isActive: isActive)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.attach(to: controller)
        context.coordinator.update(asset: asset, contentMode: contentMode, isActive: isActive)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    final class Coordinator {
        private weak var controller: AVPlayerViewController?
        private var assetIdentifier = ""
        private var requestID: PHImageRequestID?
        private var player: AVPlayer?
        private var isActive = false

        func attach(to controller: AVPlayerViewController) {
            self.controller = controller
        }

        func update(asset: PHAsset, contentMode: ContentMode, isActive: Bool) {
            controller?.videoGravity = contentMode == .fill ? .resizeAspectFill : .resizeAspect
            let becameActive = isActive && !self.isActive
            self.isActive = isActive
            if assetIdentifier != asset.localIdentifier {
                requestPlayer(for: asset)
            } else if becameActive {
                player?.play()
            } else {
                if !isActive { player?.pause() }
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
                    let player = AVPlayer(playerItem: item)
                    player.isMuted = false
                    player.actionAtItemEnd = .pause
                    self.player = player
                    self.controller?.player = player
                    if self.isActive { player.play() }
                }
            }
        }

        private func tearDownPlayer() {
            if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
            requestID = nil
            player?.pause()
            controller?.player = nil
            player = nil
        }

        func tearDown() {
            tearDownPlayer()
            assetIdentifier = ""
        }
    }
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
