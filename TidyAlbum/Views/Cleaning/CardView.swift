import Photos
import SwiftUI

// MARK: - Review Card

struct CardView: View {
    let asset: PHAsset

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AssetMediaView(asset: asset, contentMode: .fit)
            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            details
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                        .font(.headline)
                    Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer()
                if asset.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .font(.title3)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
    }
}
