import AVFoundation
import AVKit
import Photos
import PhotosUI
import UIKit

@MainActor
final class CleaningCardPageView: UIView {
    private let shadowView = UIView()
    private let clippingView = UIView()
    private let mediaView = CleaningAssetMediaView()
    private let borderLayer = CAShapeLayer()
    private let actionView = CleaningActionIndicatorView()
    private var asset: PHAsset?
    private var isFavorite = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false
        isAccessibilityElement = true

        shadowView.backgroundColor = .clear
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = 0.2
        shadowView.layer.shadowRadius = 8
        shadowView.layer.shadowOffset = CGSize(width: 0, height: 4)
        addSubview(shadowView)

        clippingView.backgroundColor = .clear
        clippingView.layer.cornerRadius = 16
        clippingView.layer.cornerCurve = .continuous
        clippingView.clipsToBounds = true
        shadowView.addSubview(clippingView)
        clippingView.addSubview(mediaView)

        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.white.withAlphaComponent(0.16).cgColor
        borderLayer.lineWidth = 0.5
        clippingView.layer.addSublayer(borderLayer)

        actionView.isUserInteractionEnabled = false
        addSubview(actionView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let asset else { return }
        let mediaSize = fittedSize(for: asset, inside: bounds.size)
        let cardFrame = CGRect(
            x: (bounds.width - mediaSize.width) * 0.5,
            y: (bounds.height - mediaSize.height) * 0.5 - 28,
            width: mediaSize.width,
            height: mediaSize.height
        ).integral
        shadowView.frame = cardFrame
        clippingView.frame = shadowView.bounds
        mediaView.frame = clippingView.bounds
        borderLayer.frame = clippingView.bounds
        borderLayer.path = UIBezierPath(
            roundedRect: clippingView.bounds,
            cornerRadius: 16
        ).cgPath
        shadowView.layer.shadowPath = UIBezierPath(
            roundedRect: shadowView.bounds,
            cornerRadius: 16
        ).cgPath
        actionView.bounds = CGRect(x: 0, y: 0, width: 86, height: 86)
        actionView.center = CGPoint(x: shadowView.frame.midX, y: shadowView.frame.midY)
    }

    func configure(
        asset: PHAsset,
        isFavorite: Bool,
        autoPlayLivePhotos: Bool,
        host: UIViewController
    ) {
        let assetChanged = self.asset?.localIdentifier != asset.localIdentifier
        self.asset = asset
        self.isFavorite = isFavorite
        accessibilityLabel = asset.creationDate.map {
            DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short)
        }
        mediaView.configure(asset: asset, autoPlayLivePhotos: autoPlayLivePhotos)
        if assetChanged { setNeedsLayout() }
    }

    func setActive(_ active: Bool, host: UIViewController) {
        mediaView.setActive(active, host: host)
    }

    func setAutoPlayLivePhotos(_ enabled: Bool, host: UIViewController) {
        mediaView.setAutoPlayLivePhotos(enabled, host: host)
    }

    func setFavorite(_ isFavorite: Bool) {
        self.isFavorite = isFavorite
    }

    func setActionProgress(translation: CGFloat, isFavorite: Bool) {
        guard translation != 0 else {
            actionView.setProgress(0, kind: .delete)
            return
        }
        let progress = min(abs(translation) / 92, 1)
        actionView.setProgress(
            progress,
            kind: translation < 0 ? .delete : (isFavorite ? .unfavorite : .favorite)
        )
    }

    func tearDown() {
        mediaView.tearDown()
    }

    private func fittedSize(for asset: PHAsset, inside bounds: CGSize) -> CGSize {
        let aspectRatio = asset.pixelHeight > 0
            ? CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
            : 1
        let maximum = CGSize(width: max(bounds.width - 24, 1), height: max(bounds.height - 24, 1))
        let containerAspect = maximum.width / maximum.height
        if aspectRatio > containerAspect {
            return CGSize(width: maximum.width, height: maximum.width / aspectRatio)
        }
        return CGSize(width: maximum.height * aspectRatio, height: maximum.height)
    }
}

@MainActor
private final class CleaningActionIndicatorView: UIView {
    enum Kind { case delete, favorite, unfavorite }

    private let imageView = UIImageView()
    private var kind = Kind.delete

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        imageView.tintColor = .white
        imageView.contentMode = .center
        addSubview(imageView)
        alpha = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width * 0.5
        imageView.frame = bounds
    }

    func setProgress(_ progress: CGFloat, kind: Kind) {
        if self.kind != kind || imageView.image == nil {
            self.kind = kind
            let symbolName: String
            switch kind {
            case .delete: symbolName = "trash.fill"
            case .favorite: symbolName = "heart.fill"
            case .unfavorite: symbolName = "heart.slash.fill"
            }
            let configuration = UIImage.SymbolConfiguration(pointSize: 42, weight: .semibold)
            imageView.image = UIImage(systemName: symbolName, withConfiguration: configuration)
            backgroundColor = kind == .delete ? .systemRed : .systemPink
        }
        alpha = progress
        let scale = 0.72 + progress * 0.38
        transform = CGAffineTransform(scaleX: scale, y: scale)
    }
}

@MainActor
private final class CleaningAssetMediaView: UIView, PHLivePhotoViewDelegate {
    private let imageView = UIImageView()
    private let videoBadge = CleaningVideoBadgeView()
    private let livePhotoBadge = CleaningLivePhotoBadgeView()
    private var asset: PHAsset?
    private var assetIdentifier = ""
    private var imageRequestID: PHImageRequestID?
    private var requestedImageKey = ""
    private var isActive = false
    private weak var hostController: UIViewController?
    private var videoRequestID: PHImageRequestID?
    private var playerController: AVPlayerViewController?
    private var player: AVPlayer?
    private var playerReadinessObservation: NSKeyValueObservation?
    private var livePhotoRequestID: PHImageRequestID?
    private var livePhotoView: PHLivePhotoView?
    private var hasFinalLivePhoto = false
    private var isLivePhotoPlaying = false
    private var autoPlayLivePhotos = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        addSubview(videoBadge)
        addSubview(livePhotoBadge)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        playerController?.view.frame = bounds
        livePhotoView?.frame = bounds
        videoBadge.bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
        videoBadge.center = CGPoint(x: bounds.midX, y: bounds.midY)
        livePhotoBadge.frame = CGRect(x: 10, y: 10, width: 66, height: 26)
        requestPosterIfNeeded()
    }

    func configure(asset: PHAsset, autoPlayLivePhotos: Bool) {
        let optionChanged = self.autoPlayLivePhotos != autoPlayLivePhotos
        self.autoPlayLivePhotos = autoPlayLivePhotos
        guard assetIdentifier != asset.localIdentifier else {
            if optionChanged { updateLivePhotoPlayback() }
            return
        }
        tearDownAsset()
        self.asset = asset
        assetIdentifier = asset.localIdentifier
        imageView.image = nil
        imageView.alpha = 1
        requestedImageKey = ""
        updateBadge()
        setNeedsLayout()
    }

    func setAutoPlayLivePhotos(_ enabled: Bool, host: UIViewController) {
        hostController = host
        guard autoPlayLivePhotos != enabled else { return }
        autoPlayLivePhotos = enabled
        updateLivePhotoPlayback()
    }

    func setActive(_ active: Bool, host: UIViewController) {
        hostController = host
        guard isActive != active else { return }
        isActive = active
        updateBadge()
        if active {
            startPlaybackIfNeeded()
        } else {
            tearDownPlayback()
        }
    }

    func tearDown() {
        tearDownAsset()
        asset = nil
        assetIdentifier = ""
        imageView.image = nil
    }

    private func requestPosterIfNeeded() {
        guard let asset, bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let key = "\(asset.localIdentifier)-\(Int(targetSize.width))x\(Int(targetSize.height))"
        guard requestedImageKey != key else { return }
        requestedImageKey = key
        AssetImagePipeline.shared.cancel(imageRequestID)
        imageRequestID = nil
        if let cached = AssetImagePipeline.shared.cachedImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill
        ) {
            imageView.image = cached
            return
        }
        let requestedIdentifier = asset.localIdentifier
        let shouldFadeIn = imageView.image == nil
        imageRequestID = AssetImagePipeline.shared.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill
        ) { [weak self] image, isFinal in
            guard let self,
                  self.assetIdentifier == requestedIdentifier,
                  self.requestedImageKey == key else { return }
            if isFinal { self.imageRequestID = nil }
            if shouldFadeIn, self.imageView.image == nil {
                self.imageView.alpha = 0
                self.imageView.image = image
                UIView.animate(
                    withDuration: 0.16,
                    delay: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                    animations: { self.imageView.alpha = self.isLivePhotoPlaying ? 0 : 1 }
                )
            } else {
                self.imageView.image = image
                self.imageView.alpha = self.isLivePhotoPlaying ? 0 : 1
            }
        }
    }

    private func startPlaybackIfNeeded() {
        guard let asset else { return }
        if asset.mediaType == .video {
            startVideo(asset)
        } else if asset.mediaSubtypes.contains(.photoLive) {
            startLivePhoto(asset)
        }
    }

    private func startVideo(_ asset: PHAsset) {
        guard playerController == nil, let hostController else { return }
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.speeds = [
            AVPlaybackSpeed(rate: 0.5, localizedName: "0.5x"),
            AVPlaybackSpeed(rate: 1, localizedName: "1x"),
            AVPlaybackSpeed(rate: 1.5, localizedName: "1.5x"),
            AVPlaybackSpeed(rate: 2, localizedName: "2x")
        ]
        controller.view.backgroundColor = .clear
        controller.view.alpha = 0
        hostController.addChild(controller)
        insertSubview(controller.view, aboveSubview: imageView)
        controller.view.frame = bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.didMove(toParent: hostController)
        playerController = controller
        playerReadinessObservation = controller.observe(
            \.isReadyForDisplay,
            options: [.initial, .new]
        ) { [weak self, weak controller] _, change in
            guard change.newValue == true, let controller else { return }
            DispatchQueue.main.async {
                guard let self,
                      self.isActive,
                      self.playerController === controller else { return }
                UIView.animate(
                    withDuration: 0.14,
                    delay: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                    animations: { controller.view.alpha = 1 }
                )
            }
        }

        let requestedIdentifier = asset.localIdentifier
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        videoRequestID = PHImageManager.default().requestPlayerItem(
            forVideo: asset,
            options: options
        ) { [weak self] item, _ in
            guard let item else { return }
            DispatchQueue.main.async {
                guard let self,
                      self.isActive,
                      self.assetIdentifier == requestedIdentifier,
                      let controller = self.playerController else { return }
                let player = AVPlayer(playerItem: item)
                player.actionAtItemEnd = .pause
                self.player = player
                controller.player = player
                player.play()
            }
        }
    }

    private func startLivePhoto(_ asset: PHAsset) {
        guard livePhotoView == nil else {
            if hasFinalLivePhoto, autoPlayLivePhotos {
                livePhotoView?.startPlayback(with: .full)
            }
            return
        }
        let liveView = PHLivePhotoView(frame: bounds)
        liveView.contentMode = .scaleAspectFill
        liveView.isMuted = true
        liveView.delegate = self
        insertSubview(liveView, aboveSubview: imageView)
        insertSubview(imageView, aboveSubview: liveView)
        livePhotoView = liveView
        let requestedIdentifier = asset.localIdentifier
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        livePhotoRequestID = PHImageManager.default().requestLivePhoto(
            for: asset,
            targetSize: CGSize(width: bounds.width * scale, height: bounds.height * scale),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] livePhoto, info in
            guard let livePhoto else { return }
            DispatchQueue.main.async {
                guard let self,
                      self.isActive,
                      self.assetIdentifier == requestedIdentifier else { return }
                self.livePhotoView?.livePhoto = livePhoto
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                self.hasFinalLivePhoto = !degraded
                if !degraded, self.autoPlayLivePhotos {
                    self.livePhotoView?.startPlayback(with: .full)
                }
            }
        }
    }

    func livePhotoView(
        _ livePhotoView: PHLivePhotoView,
        willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle
    ) {
        guard isActive, self.livePhotoView === livePhotoView else { return }
        isLivePhotoPlaying = true
        UIView.animate(
            withDuration: 0.1,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
            animations: { self.imageView.alpha = 0 }
        )
    }

    func livePhotoView(
        _ livePhotoView: PHLivePhotoView,
        didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle
    ) {
        guard isActive, self.livePhotoView === livePhotoView else { return }
        guard autoPlayLivePhotos else {
            isLivePhotoPlaying = false
            UIView.animate(
                withDuration: 0.12,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                animations: { self.imageView.alpha = 1 }
            )
            return
        }
        DispatchQueue.main.async { [weak self, weak livePhotoView] in
            guard let self, self.isActive, self.autoPlayLivePhotos else { return }
            livePhotoView?.startPlayback(with: .full)
        }
    }

    private func updateBadge() {
        videoBadge.isHidden = asset?.mediaType != .video || isActive
        livePhotoBadge.isHidden = asset?.mediaSubtypes.contains(.photoLive) != true
    }

    private func updateLivePhotoPlayback() {
        guard isActive, asset?.mediaSubtypes.contains(.photoLive) == true else { return }
        if autoPlayLivePhotos {
            if hasFinalLivePhoto {
                livePhotoView?.startPlayback(with: .full)
            } else if let asset {
                startLivePhoto(asset)
            }
        } else {
            isLivePhotoPlaying = false
            livePhotoView?.stopPlayback()
            imageView.alpha = 1
        }
    }

    private func tearDownAsset() {
        AssetImagePipeline.shared.cancel(imageRequestID)
        imageRequestID = nil
        requestedImageKey = ""
        tearDownPlayback()
    }

    private func tearDownPlayback() {
        if let videoRequestID { PHImageManager.default().cancelImageRequest(videoRequestID) }
        videoRequestID = nil
        playerReadinessObservation?.invalidate()
        playerReadinessObservation = nil
        player?.pause()
        playerController?.player = nil
        player = nil
        if let controller = playerController {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        playerController = nil
        tearDownLivePhoto()
    }

    private func tearDownLivePhoto() {
        if let livePhotoRequestID { PHImageManager.default().cancelImageRequest(livePhotoRequestID) }
        livePhotoRequestID = nil
        livePhotoView?.stopPlayback()
        livePhotoView?.delegate = nil
        livePhotoView?.removeFromSuperview()
        livePhotoView = nil
        hasFinalLivePhoto = false
        isLivePhotoPlaying = false
        imageView.alpha = 1
    }
}

@MainActor
private final class CleaningLivePhotoBadgeView: UIVisualEffectView {
    private let iconView = UIImageView()
    private let label = UILabel()

    init() {
        super.init(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        clipsToBounds = true
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        isUserInteractionEnabled = false

        iconView.image = UIImage(
            systemName: "livephoto",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        contentView.addSubview(iconView)

        label.text = "LIVE"
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        contentView.addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = 6
        iconView.frame = CGRect(x: 7, y: 6, width: 14, height: 14)
        label.frame = CGRect(x: 25, y: 0, width: bounds.width - 30, height: bounds.height)
    }
}

@MainActor
private final class CleaningVideoBadgeView: UIVisualEffectView {
    private let imageView = UIImageView()

    init() {
        super.init(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        clipsToBounds = true
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        imageView.image = UIImage(systemName: "play.fill", withConfiguration: configuration)
        imageView.tintColor = .white
        imageView.contentMode = .center
        contentView.addSubview(imageView)
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width * 0.5
        imageView.frame = bounds
    }
}
