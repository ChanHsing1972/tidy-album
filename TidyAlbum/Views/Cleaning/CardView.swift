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
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundStyle(.pink)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(14)
                }
            }
    }
}