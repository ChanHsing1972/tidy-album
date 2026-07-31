import Photos
import SwiftUI

// MARK: - Review Card

struct CardView: View {
    let asset: PHAsset

    var body: some View {
        AssetMediaView(asset: asset, contentMode: .fit)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if asset.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundStyle(.pink)
                        .padding(14)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(12)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
    }
}