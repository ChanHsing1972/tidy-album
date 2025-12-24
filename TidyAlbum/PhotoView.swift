import SwiftUI
import Photos
import AVKit

struct PhotoView: View {
    var body: some View {
        EmptyView()
    }
}

struct CardView: View {
    let asset: PHAsset
    @ObservedObject var manager: PhotoManager
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 媒体层 (图片或视频)
                AssetMediaView(asset: asset)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                
                // 渐变遮罩
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6), .black.opacity(0.9)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 200)
                
                // 信息层
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 12) {
                            Label("\(asset.pixelWidth) × \(asset.pixelHeight)", systemImage: "aspectratio")
                            if asset.mediaType == .video {
                                Label(formatDuration(asset.duration), systemImage: "play.circle.fill")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    if asset.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.title)
                            .foregroundColor(.pink)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(24)
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(32)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
}

struct AssetMediaView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @Environment(\.displayScale) var displayScale
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                
                if asset.mediaType == .video {
                    if let player = player {
                        VideoPlayer(player: player)
                            .disabled(true) // 禁用控件，仅预览
                            .onAppear {
                                player.play()
                                player.isMuted = true // 默认静音预览
                                // 循环播放
                                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                                    player.seek(to: .zero)
                                    player.play()
                                }
                            }
                            .onDisappear {
                                player.pause()
                            }
                    } else {
                        ProgressView()
                    }
                } else {
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .transition(.opacity.animation(.easeOut(duration: 0.2)))
                    } else {
                        ProgressView()
                    }
                }
            }
            .onAppear {
                loadMedia(targetSize: geometry.size)
            }
            .onChange(of: asset.localIdentifier) { _, _ in
                // 仅当 asset 真正改变时才重置
                // 防止不必要的重绘
                self.image = nil
                self.player = nil
                loadMedia(targetSize: geometry.size)
            }
        }
    }
    
    func loadMedia(targetSize: CGSize) {
        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                if let item = item {
                    DispatchQueue.main.async {
                        self.player = AVPlayer(playerItem: item)
                    }
                }
            }
        } else {
            let manager = PHImageManager.default()
            let option = PHImageRequestOptions()
            option.isSynchronous = false
            option.deliveryMode = .highQualityFormat
            option.isNetworkAccessAllowed = true
            
            let size = CGSize(width: targetSize.width * displayScale, height: targetSize.height * displayScale)
            
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: option) { result, info in
                if let result = result {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.image = result
                    }
                }
            }
        }
    }
}
