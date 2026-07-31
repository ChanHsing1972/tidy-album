import Photos
import SwiftUI

// MARK: - Review Card

struct CardView: View {
    let asset: PHAsset
    var isActive = false
    var isFavorite = false

    var body: some View {
        AssetMediaView(
            asset: asset,
            contentMode: .fit,
            allowsPlayback: true,
            isActive: isActive
        )
            .mask(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}
