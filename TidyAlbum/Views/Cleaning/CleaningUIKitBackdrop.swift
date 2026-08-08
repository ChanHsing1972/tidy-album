import Photos
import SwiftUI
import UIKit

@MainActor
final class CleaningUIKitSession {
    private weak var backdropView: CleaningBackdropRenderView?
    private var transitionSourceID: String?
    private var transitionTargetID: String?
    private var transitionProgress: CGFloat = 0

    func attach(_ backdropView: CleaningBackdropRenderView) {
        self.backdropView = backdropView
        backdropView.setTransition(
            sourceID: transitionSourceID,
            targetID: transitionTargetID,
            progress: transitionProgress
        )
    }

    func detach(_ backdropView: CleaningBackdropRenderView) {
        guard self.backdropView === backdropView else { return }
        self.backdropView = nil
    }

    func beginTransition(sourceID: String, targetID: String) {
        transitionSourceID = sourceID
        transitionTargetID = targetID
        transitionProgress = 0
        backdropView?.setTransition(sourceID: sourceID, targetID: targetID, progress: 0)
    }

    func setTransitionProgress(_ progress: CGFloat) {
        let clamped = min(max(progress, 0), 1)
        guard abs(transitionProgress - clamped) > 0.0005 else { return }
        transitionProgress = clamped
        backdropView?.setTransition(
            sourceID: transitionSourceID,
            targetID: transitionTargetID,
            progress: transitionProgress
        )
    }

    func commitSelection(_ identifier: String) {
        transitionSourceID = nil
        transitionTargetID = nil
        transitionProgress = 0
        backdropView?.commitSelection(identifier)
    }

    func cancelTransition() {
        transitionSourceID = nil
        transitionTargetID = nil
        transitionProgress = 0
        backdropView?.setTransition(sourceID: nil, targetID: nil, progress: 0)
    }
}

struct CleaningUIKitBackdrop: UIViewRepresentable {
    let session: CleaningUIKitSession
    let assets: [PHAsset]
    let selectedAssetID: String
    let sessionGroupNumber: Int

    func makeUIView(context: Context) -> CleaningBackdropRenderView {
        let view = CleaningBackdropRenderView()
        session.attach(view)
        return view
    }

    func updateUIView(_ view: CleaningBackdropRenderView, context: Context) {
        session.attach(view)
        view.configure(
            assets: assets,
            selectedAssetID: selectedAssetID,
            sessionGroupNumber: sessionGroupNumber
        )
    }

    static func dismantleUIView(_ view: CleaningBackdropRenderView, coordinator: Void) {
        view.tearDown()
    }
}

@MainActor
final class CleaningBackdropRenderView: UIView {
    private let baseImageView = UIImageView()
    private let targetImageView = UIImageView()
    private let completionOverlay = UIView()
    private let contrastOverlay = UIView()

    private var assets: [PHAsset] = []
    private var assetByIdentifier: [String: PHAsset] = [:]
    private var selectedAssetID = ""
    private var sessionGroupNumber = -1
    private var transitionSourceID: String?
    private var transitionTargetID: String?
    private var transitionProgress: CGFloat = 0
    private var canvasSize = CGSize.zero
    private var fallbackImage: UIImage?
    private var sourceImages: [String: UIImage] = [:]
    private var renderedImages: [String: UIImage] = [:]
    private var requestIDs: [String: PHImageRequestID] = [:]
    private var renderTasks: [String: Task<Void, Never>] = [:]
    private var renderTokens: [String: UUID] = [:]
    private var generation = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        clipsToBounds = true
        [baseImageView, targetImageView].forEach { imageView in
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            addSubview(imageView)
        }
        completionOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        contrastOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        addSubview(completionOverlay)
        addSubview(contrastOverlay)
        targetImageView.alpha = 0
        completionOverlay.alpha = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let imageFrame = bounds.insetBy(dx: -bounds.width * 0.09, dy: -bounds.height * 0.09)
        baseImageView.frame = imageFrame
        targetImageView.frame = imageFrame
        completionOverlay.frame = bounds
        contrastOverlay.frame = bounds
        guard bounds.size.width > 0, bounds.size.height > 0, canvasSize != bounds.size else { return }
        canvasSize = bounds.size
        renderedImages.removeAll(keepingCapacity: true)
        cancelRenderTasks()
        synchronizeImages()
        refreshLayers()
    }

    func configure(assets: [PHAsset], selectedAssetID: String, sessionGroupNumber: Int) {
        if self.sessionGroupNumber != sessionGroupNumber {
            resetForNewGroup()
            self.sessionGroupNumber = sessionGroupNumber
        }
        self.assets = assets
        assetByIdentifier = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        if self.selectedAssetID != selectedAssetID {
            fallbackImage = renderedImages[self.selectedAssetID] ?? fallbackImage
            self.selectedAssetID = selectedAssetID
            transitionSourceID = nil
            transitionTargetID = nil
            transitionProgress = 0
        }
        synchronizeImages()
        refreshLayers()
    }

    func setTransition(sourceID: String?, targetID: String?, progress: CGFloat) {
        let targetChanged = transitionTargetID != targetID
        transitionSourceID = sourceID
        transitionTargetID = targetID
        transitionProgress = min(max(progress, 0), 1)
        if targetChanged, let targetID, let asset = assetByIdentifier[targetID] {
            requestImage(for: asset)
        }
        refreshLayers()
    }

    func commitSelection(_ identifier: String) {
        fallbackImage = renderedImages[selectedAssetID] ?? fallbackImage
        selectedAssetID = identifier
        transitionSourceID = nil
        transitionTargetID = nil
        transitionProgress = 0
        synchronizeImages()
        refreshLayers()
    }

    func tearDown() {
        generation += 1
        cancelRequests()
        cancelRenderTasks()
    }

    private func synchronizeImages() {
        guard canvasSize.width > 0, canvasSize.height > 0,
              let currentIndex = assets.firstIndex(where: {
                  $0.localIdentifier == selectedAssetID
              }) else { return }
        let indices = (currentIndex - 3...currentIndex + 3).filter(assets.indices.contains)
        let nearbyAssets = indices.map { assets[$0] }
        nearbyAssets.forEach(requestImage)
        retainImages(identifiers: Set(nearbyAssets.map(\.localIdentifier)))
    }

    private func requestImage(for asset: PHAsset) {
        let identifier = asset.localIdentifier
        if let sourceImage = sourceImages[identifier] {
            if renderedImages[identifier] == nil, renderTasks[identifier] == nil {
                render(sourceImage, identifier: identifier)
            }
            return
        }
        guard requestIDs[identifier] == nil else { return }
        let targetSize = CGSize(width: 256, height: 256)
        if let cached = AssetImagePipeline.shared.cachedImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill
        ) {
            sourceImages[identifier] = cached
            render(cached, identifier: identifier)
            return
        }
        let requestGeneration = generation
        requestIDs[identifier] = AssetImagePipeline.shared.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            deliveryMode: .opportunistic
        ) { [weak self] image, isFinal in
            guard let self, requestGeneration == self.generation else { return }
            self.sourceImages[identifier] = image
            self.render(image, identifier: identifier)
            if isFinal { self.requestIDs[identifier] = nil }
        }
    }

    private func render(_ image: UIImage, identifier: String) {
        guard canvasSize.width > 0, canvasSize.height > 0,
              let inputImage = CIImage(image: image, options: [.applyOrientationProperty: true]) else { return }
        renderTasks[identifier]?.cancel()
        let token = UUID()
        let expectedCanvasSize = canvasSize
        renderTokens[identifier] = token
        renderTasks[identifier] = Task(priority: .utility) { [weak self] in
            let output = await CleaningBackdropRenderer.shared.renderedImage(
                from: inputImage,
                assetIdentifier: identifier,
                canvasSize: expectedCanvasSize
            )
            guard let self, !Task.isCancelled,
                  self.renderTokens[identifier] == token,
                  self.canvasSize == expectedCanvasSize,
                  let output else { return }
            self.renderTokens[identifier] = nil
            self.renderTasks[identifier] = nil
            self.renderedImages[identifier] = UIImage(cgImage: output)
            self.refreshLayers()
        }
    }

    private func refreshLayers() {
        let sourceID = transitionSourceID ?? selectedAssetID
        let baseImage = renderedImages[sourceID]
            ?? renderedImages[selectedAssetID]
            ?? fallbackImage
        if baseImageView.image !== baseImage { baseImageView.image = baseImage }
        if let targetID = transitionTargetID,
           targetID != CleaningPageID.groupCompletion {
            let targetImage = renderedImages[targetID]
            if targetImageView.image !== targetImage { targetImageView.image = targetImage }
            targetImageView.alpha = transitionProgress
        } else {
            if targetImageView.image != nil { targetImageView.image = nil }
            targetImageView.alpha = 0
        }
        if transitionSourceID == CleaningPageID.groupCompletion,
           transitionTargetID != nil,
           transitionTargetID != CleaningPageID.groupCompletion {
            completionOverlay.alpha = 1 - transitionProgress
        } else if selectedAssetID == CleaningPageID.groupCompletion {
            completionOverlay.alpha = 1
        } else if transitionTargetID == CleaningPageID.groupCompletion {
            completionOverlay.alpha = transitionProgress
        } else {
            completionOverlay.alpha = 0
        }
    }

    private func retainImages(identifiers: Set<String>) {
        var retained = identifiers
        retained.insert(selectedAssetID)
        if let transitionSourceID { retained.insert(transitionSourceID) }
        if let transitionTargetID { retained.insert(transitionTargetID) }
        sourceImages = sourceImages.filter { retained.contains($0.key) }
        renderedImages = renderedImages.filter { retained.contains($0.key) }
        for identifier in requestIDs.keys.filter({ !retained.contains($0) }) {
            AssetImagePipeline.shared.cancel(requestIDs.removeValue(forKey: identifier))
        }
        for identifier in renderTasks.keys.filter({ !retained.contains($0) }) {
            renderTasks.removeValue(forKey: identifier)?.cancel()
            renderTokens[identifier] = nil
        }
    }

    private func resetForNewGroup() {
        generation += 1
        cancelRequests()
        cancelRenderTasks()
        sourceImages.removeAll(keepingCapacity: true)
        renderedImages.removeAll(keepingCapacity: true)
        assetByIdentifier.removeAll(keepingCapacity: true)
        fallbackImage = nil
        selectedAssetID = ""
        transitionSourceID = nil
        transitionTargetID = nil
        transitionProgress = 0
    }

    private func cancelRequests() {
        requestIDs.values.forEach(AssetImagePipeline.shared.cancel)
        requestIDs.removeAll()
    }

    private func cancelRenderTasks() {
        renderTasks.values.forEach { $0.cancel() }
        renderTasks.removeAll()
        renderTokens.removeAll()
    }
}
