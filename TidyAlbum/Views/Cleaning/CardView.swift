import Photos
import SwiftUI

struct CardView: View {
    let asset: PHAsset
    var isActive = false
    var isFavorite = false

    private var assetAspectRatio: CGFloat {
        guard asset.pixelHeight > 0 else { return 1 }
        return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }

    var body: some View {
        GeometryReader { proxy in
            let mediaSize = fittedSize(aspectRatio: assetAspectRatio, inside: proxy.size)
            AssetMediaView(
                asset: asset,
                contentMode: .fill,
                allowsPlayback: true,
                isActive: isActive
            )
            .frame(width: mediaSize.width, height: mediaSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fittedSize(aspectRatio: CGFloat, inside bounds: CGSize) -> CGSize {
        let maximum = CGSize(width: max(bounds.width - 12, 1), height: max(bounds.height - 42, 1))
        let containerAspect = maximum.width / maximum.height
        if aspectRatio > containerAspect {
            return CGSize(width: maximum.width, height: maximum.width / aspectRatio)
        }
        return CGSize(width: maximum.height * aspectRatio, height: maximum.height)
    }
}
