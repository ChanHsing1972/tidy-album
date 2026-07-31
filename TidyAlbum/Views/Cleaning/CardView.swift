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
            
            // 💡 确保内容在 GeometryReader 内完美水平垂直居中
            ZStack {
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
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center) // 👈 显式指定 .center 居中
        }
    }

    private func fittedSize(aspectRatio: CGFloat, inside bounds: CGSize) -> CGSize {
        // 💡 将上下留出的安全 Margin 从 42 适当增加（如 64），保证长图上下永远留有优雅的空隙
        let maximum = CGSize(width: max(bounds.width - 24, 1), height: max(bounds.height - 64, 1))
        let containerAspect = maximum.width / maximum.height
        if aspectRatio > containerAspect {
            return CGSize(width: maximum.width, height: maximum.width / aspectRatio)
        }
        return CGSize(width: maximum.height * aspectRatio, height: maximum.height)
    }
}
