import Photos
import SwiftUI

// MARK: - Cached Asset Media View

struct AssetMediaView: View {
    let asset: PHAsset
    var contentMode: ContentMode = .fit
    var showsVideoBadge = true

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(uiColor: .secondarySystemBackground)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: asset.mediaType == .video ? "video.fill" : "photo.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                        .symbolEffect(.pulse, options: .repeating.speed(0.35))
                }

                if showsVideoBadge && asset.mediaType == .video {
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.thinMaterial, in: Circle())
                }
            }
            .clipped()
            .task(id: requestKey(size: proxy.size)) {
                load(size: proxy.size)
            }
            .onDisappear {
                AssetImagePipeline.shared.cancel(requestID)
            }
        }
    }

    // MARK: Image Loading

    private func requestKey(size: CGSize) -> String {
        "\(asset.localIdentifier)-\(Int(size.width))-\(Int(size.height))"
    }

    private func load(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let targetSize = CGSize(width: size.width * displayScale, height: size.height * displayScale)
        if let cached = AssetImagePipeline.shared.cachedImage(for: asset, targetSize: targetSize) {
            image = cached
            return
        }

        requestID = AssetImagePipeline.shared.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode == .fill ? .aspectFill : .aspectFit
        ) { loadedImage in
            image = loadedImage
        }
    }
}
