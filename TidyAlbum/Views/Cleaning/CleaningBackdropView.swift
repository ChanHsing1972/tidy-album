import Photos
import SwiftUI
import UIKit

struct CleaningBackdropView: View {
    let assets: [PHAsset]
    let selectedAssetID: String
    let sessionGroupNumber: Int
    let interaction: CleaningInteractionState

    @State private var sourceImages: [String: UIImage] = [:]
    @State private var renderedImages: [String: UIImage] = [:]
    @State private var requestIDs: [String: PHImageRequestID] = [:]
    @State private var renderTasks: [String: Task<Void, Never>] = [:]
    @State private var renderTokens: [String: UUID] = [:]
    @State private var fallbackSourceImage: UIImage?
    @State private var fallbackRenderedImage: UIImage?
    @State private var renderedCanvasSize = CGSize.zero
    @State private var loadedGroupNumber = -1
    @State private var requestGeneration = 0

    private var currentIndex: Int? {
        assets.firstIndex { $0.localIdentifier == selectedAssetID }
    }

    var body: some View {
        GeometryReader { proxy in
            let transition = interaction.backdropTransition
            ZStack {
                Color.black

                if let image = baseRenderedImage(for: transition) {
                    RenderedBackdropImageLayer(image: image, size: proxy.size)
                } else if let image = baseSourceImage(for: transition) {
                    RealtimeBackdropImageLayer(image: image, size: proxy.size)
                }

                if selectedAssetID == CleaningPageID.groupCompletion {
                    Color.black.opacity(0.48)
                }

                if let targetID = transition.targetID {
                    if targetID == CleaningPageID.groupCompletion {
                        Color.black.opacity(0.48 * transition.progress)
                    } else if let targetImage = renderedImages[targetID] {
                        RenderedBackdropImageLayer(image: targetImage, size: proxy.size)
                            .opacity(transition.progress)
                    } else if let targetImage = sourceImages[targetID] {
                        RealtimeBackdropImageLayer(image: targetImage, size: proxy.size)
                            .opacity(transition.progress)
                    }
                }

                Color.black.opacity(0.34)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task(id: BackdropLoadKey(
                groupNumber: sessionGroupNumber,
                selectedAssetID: selectedAssetID,
                width: Int(proxy.size.width.rounded(.up)),
                height: Int(proxy.size.height.rounded(.up))
            )) {
                synchronizeImages(canvasSize: proxy.size)
            }
            .onChange(of: interaction.backdropTransition.targetID) { _, targetID in
                guard let targetID,
                      let asset = assets.first(where: { $0.localIdentifier == targetID }) else { return }
                requestImage(for: asset)
                renderSourceImageIfAvailable(identifier: targetID, canvasSize: proxy.size)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: selectedAssetID) { previousIdentifier, _ in
            fallbackSourceImage = sourceImages[previousIdentifier] ?? fallbackSourceImage
            fallbackRenderedImage = renderedImages[previousIdentifier] ?? fallbackRenderedImage
        }
        .onDisappear { cancelWork() }
    }

    private func baseRenderedImage(for transition: BackdropTransition) -> UIImage? {
        renderedImages[selectedAssetID]
            ?? transition.sourceID.flatMap { renderedImages[$0] }
            ?? fallbackRenderedImage
    }

    private func baseSourceImage(for transition: BackdropTransition) -> UIImage? {
        sourceImages[selectedAssetID]
            ?? transition.sourceID.flatMap { sourceImages[$0] }
            ?? fallbackSourceImage
    }

    private func synchronizeImages(canvasSize: CGSize) {
        if loadedGroupNumber != sessionGroupNumber {
            resetForNewGroup()
            loadedGroupNumber = sessionGroupNumber
        }
        if renderedCanvasSize != canvasSize {
            cancelRenderTasks()
            renderedImages.removeAll(keepingCapacity: true)
            fallbackRenderedImage = nil
            renderedCanvasSize = canvasSize
        }
        guard let currentIndex else { return }
        let nearbyIndices = [currentIndex, currentIndex - 1, currentIndex + 1]
            .filter(assets.indices.contains)
        let nearbyAssets = nearbyIndices.map { assets[$0] }
        for asset in nearbyAssets {
            requestImage(for: asset)
            renderSourceImageIfAvailable(identifier: asset.localIdentifier, canvasSize: canvasSize)
        }
        retainNearbyImages(Set(nearbyAssets.map(\.localIdentifier)))
    }

    private func requestImage(for asset: PHAsset) {
        let identifier = asset.localIdentifier
        guard sourceImages[identifier] == nil, requestIDs[identifier] == nil else { return }
        let targetSize = CGSize(width: 160, height: 160)
        if let cached = AssetImagePipeline.shared.cachedImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill
        ) {
            sourceImages[identifier] = cached
            renderSourceImageIfAvailable(identifier: identifier, canvasSize: renderedCanvasSize)
            return
        }
        let generation = requestGeneration
        requestIDs[identifier] = AssetImagePipeline.shared.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            deliveryMode: .highQualityFormat
        ) { image, isFinal in
            guard generation == requestGeneration else { return }
            sourceImages[identifier] = image
            renderSourceImageIfAvailable(identifier: identifier, canvasSize: renderedCanvasSize)
            if isFinal { requestIDs[identifier] = nil }
        }
    }

    private func renderSourceImageIfAvailable(identifier: String, canvasSize: CGSize) {
        guard canvasSize.width > 0,
              canvasSize.height > 0,
              renderedImages[identifier] == nil,
              renderTasks[identifier] == nil,
              let sourceImage = sourceImages[identifier],
              let inputImage = CIImage(
                image: sourceImage,
                options: [.applyOrientationProperty: true]
              ) else { return }
        let expectedSize = canvasSize
        let token = UUID()
        renderTokens[identifier] = token
        renderTasks[identifier] = Task(priority: .utility) {
            let output = await CleaningBackdropRenderer.shared.renderedImage(
                from: inputImage,
                assetIdentifier: identifier,
                canvasSize: expectedSize
            )
            guard renderTokens[identifier] == token else { return }
            renderTokens[identifier] = nil
            renderTasks[identifier] = nil
            guard !Task.isCancelled,
                  renderedCanvasSize == expectedSize,
                  let output else { return }
            renderedImages[identifier] = UIImage(cgImage: output, scale: 1, orientation: .up)
        }
    }

    private func retainNearbyImages(_ nearbyIDs: Set<String>) {
        var retainedIDs = nearbyIDs
        retainedIDs.insert(selectedAssetID)
        if let sourceID = interaction.backdropTransition.sourceID { retainedIDs.insert(sourceID) }
        if let targetID = interaction.backdropTransition.targetID { retainedIDs.insert(targetID) }
        sourceImages = sourceImages.filter { retainedIDs.contains($0.key) }
        renderedImages = renderedImages.filter { retainedIDs.contains($0.key) }
        let obsoleteRequestIDs = requestIDs.keys.filter { !retainedIDs.contains($0) }
        for identifier in obsoleteRequestIDs {
            AssetImagePipeline.shared.cancel(requestIDs.removeValue(forKey: identifier))
        }
        let obsoleteRenderIDs = renderTasks.keys.filter { !retainedIDs.contains($0) }
        for identifier in obsoleteRenderIDs {
            renderTasks.removeValue(forKey: identifier)?.cancel()
            renderTokens[identifier] = nil
        }
    }

    private func resetForNewGroup() {
        requestGeneration += 1
        cancelWork()
        sourceImages.removeAll(keepingCapacity: true)
        renderedImages.removeAll(keepingCapacity: true)
        fallbackSourceImage = nil
        fallbackRenderedImage = nil
        interaction.resetBackdropTransition()
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

    private func cancelWork() {
        cancelRequests()
        cancelRenderTasks()
    }
}

private struct BackdropLoadKey: Hashable {
    let groupNumber: Int
    let selectedAssetID: String
    let width: Int
    let height: Int
}

private struct RenderedBackdropImageLayer: View {
    let image: UIImage
    let size: CGSize

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .scaleEffect(1.18)
    }
}

private struct RealtimeBackdropImageLayer: View {
    let image: UIImage
    let size: CGSize

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .scaleEffect(1.18)
            .blur(radius: 54, opaque: true)
            .drawingGroup(opaque: true, colorMode: .nonLinear)
    }
}
