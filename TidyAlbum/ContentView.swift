import SwiftUI
import Photos

struct ContentView: View {
    @StateObject var manager = PhotoManager()
    @State private var appState: AppState = .home
    @State private var showTrash = false
    
    enum AppState {
        case home
        case cleaning
        case summary
    }
    
    var body: some View {
        ZStack {
            // 全局背景
            Color.black.ignoresSafeArea()
            
            if manager.isAuthorized {
                switch appState {
                case .home:
                    HomeView(manager: manager, onStart: {
                        // 每次开始清理前，确保数据是最新的
                        manager.fetchPhotos()
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .cleaning
                        }
                    }, onShowTrash: {
                        showTrash = true
                    })
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    
                case .cleaning:
                    CleaningView(manager: manager, onFinish: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .summary
                        }
                    }, onBack: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .home
                        }
                    }, onShowTrash: {
                        showTrash = true
                    })
                    .transition(.move(edge: .trailing))
                    
                case .summary:
                    SummaryView(manager: manager, onHome: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            appState = .home
                        }
                    })
                    .transition(.move(edge: .bottom))
                }
            } else {
                PermissionView()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTrash) {
            TrashView(manager: manager)
        }
    }
}

// MARK: - Home View
struct HomeView: View {
    @ObservedObject var manager: PhotoManager
    var onStart: () -> Void
    var onShowTrash: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Good Day")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                    Text("TidyAlbum")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.white, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
                Spacer()
                
                Button(action: onShowTrash) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "trash").foregroundColor(.white))
                }
            }
            .padding(.top, 20)
            
            // Stats Card
            VStack(spacing: 20) {
                HStack {
                    StatItem(value: "\(manager.assets.count)", title: "Remaining", icon: "photo.on.rectangle")
                    Divider().background(Color.white.opacity(0.2))
                    StatItem(value: "\(manager.trashBin.count)", title: "In Trash", icon: "trash")
                }
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
            
            // Filter Selection
            VStack(alignment: .leading, spacing: 16) {
                Text("Start Cleaning")
                    .font(.headline)
                    .foregroundColor(.white)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(PhotoFilter.allCases) { filter in
                            FilterCard(filter: filter, isSelected: manager.currentFilter == filter) {
                                manager.setFilter(filter)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // Start Button
            Button(action: onStart) {
                HStack {
                    Text("Start Session")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(Color.white)
                .cornerRadius(32)
                .shadow(color: .white.opacity(0.2), radius: 20, x: 0, y: 10)
            }
        }
        .padding(24)
    }
}

struct StatItem: View {
    let value: String
    let title: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(height: 30)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FilterCard: View {
    let filter: PhotoFilter
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: filter.icon)
                    .font(.title)
                    .foregroundColor(isSelected ? .black : .white)
                
                Text(filter.rawValue)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(isSelected ? .black : .white)
            }
            .padding(20)
            .frame(width: 140, height: 140)
            .background(isSelected ? Color.white : Color.gray.opacity(0.2))
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

// MARK: - Cleaning View
struct CleaningView: View {
    @ObservedObject var manager: PhotoManager
    var onFinish: () -> Void
    var onBack: () -> Void
    var onShowTrash: () -> Void
    
    @State private var currentIndex = 0
    @State private var offset: CGSize = .zero
    @State private var isDragging = false
    
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    // 计算拖拽进度 (0.0 - 1.0)
    var dragProgress: Double {
        let maxDistance: CGFloat = 150
        let distance = sqrt(pow(offset.width, 2) + pow(offset.height, 2))
        return min(Double(distance / maxDistance), 1.0)
    }
    
    // 判断主导方向
    enum DragDirection {
        case none, left, right, up, down
    }
    
    var dominantDirection: DragDirection {
        if offset == .zero { return .none }
        
        if abs(offset.height) > abs(offset.width) {
            // Vertical
            return offset.height < 0 ? .up : .down
        } else {
            // Horizontal
            return offset.width < 0 ? .left : .right
        }
    }
    
    var body: some View {
        ZStack {
            // 模糊背景
            if currentIndex < manager.assets.count {
                AssetMediaView(asset: manager.assets[currentIndex])
                    .blur(radius: 50)
                    .opacity(0.5)
                    .ignoresSafeArea()
            }
            
            VStack {
                // Top Bar - 仅在有照片时显示
                if currentIndex < manager.assets.count {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        Text("\(currentIndex + 1) / \(manager.assets.count)")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        
                        Spacer()
                        
                        Button(action: onShowTrash) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                Text("\(manager.trashBin.count)")
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(manager.trashBin.isEmpty ? Color.gray.opacity(0.3) : Color.red)
                            .cornerRadius(20)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
                
                Spacer()
                
                // Card Stack
                ZStack {
                    if manager.assets.isEmpty {
                        VStack(spacing: 20) {
                            Text("No photos in this filter")
                                .foregroundColor(.white)
                            Button("Back to Home", action: onBack)
                                .padding()
                                .background(Color.white)
                                .foregroundColor(.black)
                                .cornerRadius(16)
                        }
                    } else if currentIndex >= manager.assets.count {
                        VStack(spacing: 20) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(LinearGradient(colors: [.green, .mint], startPoint: .top, endPoint: .bottom))
                            Text("All Caught Up!")
                                .font(.title2)
                                .foregroundColor(.white)
                            Button("Finish Review", action: onFinish)
                                .padding()
                                .background(Color.white)
                                .foregroundColor(.black)
                                .cornerRadius(16)
                        }
                    } else {
                        // Next Card (Preview)
                        if currentIndex + 1 < manager.assets.count {
                            CardView(asset: manager.assets[currentIndex + 1], manager: manager)
                                .scaleEffect(0.92 + (0.08 * dragProgress)) // 动态缩放
                                .offset(y: 30 * (1.0 - dragProgress)) // 动态位移
                                .opacity(0.6 + (0.4 * dragProgress)) // 动态透明度
                                .zIndex(0)
                                .id(manager.assets[currentIndex + 1].localIdentifier) // 关键：给下一张卡片也加上 ID，防止晋升为当前卡片时重绘
                        }
                        
                        // Current Card
                        CardView(asset: manager.assets[currentIndex], manager: manager)
                            .offset(offset)
                            .rotationEffect(.degrees(Double(offset.width / 15)))
                            .scaleEffect(isDragging ? 0.95 : 1.0)
                            .gesture(
                                DragGesture()
                                    .onChanged { gesture in
                                        isDragging = true
                                        offset = gesture.translation
                                        if abs(offset.height) > 100 || abs(offset.width) > 100 {
                                            // Haptic feedback logic could go here
                                        }
                                    }
                                    .onEnded { gesture in
                                        isDragging = false
                                        handleSwipe(translation: gesture.translation)
                                    }
                            )
                            .overlay(overlayIcons)
                            .zIndex(1)
                            .id(manager.assets[currentIndex].localIdentifier)
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: 600)
                
                Spacer()
                
                // Bottom Controls - 仅在有照片时显示
                if currentIndex < manager.assets.count {
                    HStack(spacing: 40) {
                        ControlBtn(icon: "arrow.uturn.backward", color: .yellow) {
                            if currentIndex > 0 {
                                withAnimation {
                                    currentIndex -= 1
                                    offset = .zero
                                }
                            }
                        }
                        .disabled(currentIndex == 0)
                        .opacity(currentIndex == 0 ? 0.3 : 1.0)
                        
                        ControlBtn(icon: "trash", color: .red) {
                            handleSwipe(translation: CGSize(width: 0, height: -200))
                        }
                        
                        ControlBtn(icon: "heart", color: .pink) {
                            handleSwipe(translation: CGSize(width: 0, height: 200))
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
        }
    }
    
    var overlayIcons: some View {
        let currentAsset = manager.assets[currentIndex]
        let isFavorite = currentAsset.isFavorite
        
        return ZStack {
            // 动态透明度，避免生硬出现
            // 仅当主导方向为 UP 时显示 DELETE
            IconOverlay(icon: "trash.fill", color: .red, text: "DELETE")
                .offset(y: 50)
                .opacity(dominantDirection == .up ? min(Double(-offset.height) / 150.0, 1.0) : 0)
            
            // 仅当主导方向为 DOWN 时显示 FAVORITE / UNFAVORITE
            IconOverlay(
                icon: isFavorite ? "heart.slash.fill" : "heart.fill",
                color: .pink,
                text: isFavorite ? "UNFAVORITE" : "FAVORITE"
            )
            .offset(y: -50)
            .opacity(dominantDirection == .down ? min(Double(offset.height) / 150.0, 1.0) : 0)
            
            // 仅当主导方向为 LEFT 或 RIGHT 时显示 SKIP
            IconOverlay(icon: "arrow.right", color: .blue, text: "SKIP")
                .opacity((dominantDirection == .left || dominantDirection == .right) ? min(Double(abs(offset.width)) / 150.0, 1.0) : 0)
        }
        .animation(.easeInOut(duration: 0.2), value: dominantDirection) // 平滑切换图标
    }
    
    func handleSwipe(translation: CGSize) {
        let threshold: CGFloat = 100
        let currentAsset = manager.assets[currentIndex]
        
        if translation.height < -threshold {
            // Delete (Up)
            impactFeedback.impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                offset = CGSize(width: 0, height: -1000)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                manager.addToTrash(asset: currentAsset)
                nextPhoto()
            }
        } else if translation.height > threshold {
            // Favorite / Unfavorite (Down)
            impactFeedback.impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                offset = CGSize(width: 0, height: 1000)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                manager.toggleFavorite(asset: currentAsset)
                nextPhoto()
            }
        } else if abs(translation.width) > threshold {
            // Skip (Left or Right)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                // 根据滑动方向飞出
                offset = CGSize(width: translation.width > 0 ? 1000 : -1000, height: 0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                nextPhoto()
            }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                offset = .zero
            }
        }
    }
    
    func nextPhoto() {
        currentIndex += 1
        offset = .zero
    }
}

struct ControlBtn: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 60, height: 60)
                .background(Color.white)
                .clipShape(Circle())
                .shadow(color: color.opacity(0.3), radius: 10, x: 0, y: 5)
        }
    }
}

struct IconOverlay: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.white)
            Text(text)
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding(30)
        .background(color.opacity(0.8))
        .clipShape(Circle())
        .shadow(radius: 10)
    }
}

// MARK: - Summary View
struct SummaryView: View {
    @ObservedObject var manager: PhotoManager
    var onHome: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 80))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding()
                .background(Circle().fill(.ultraThinMaterial).frame(width: 150, height: 150))
            
            VStack(spacing: 10) {
                Text("Session Complete")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("You've cleaned up your album!")
                    .font(.body)
                    .foregroundColor(.gray)
            }
            
            // 统计数据展示
            HStack(spacing: 40) {
                VStack {
                    Text("\(manager.sessionDeletedCount)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                    Text("Deleted")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                VStack {
                    Text("\(manager.trashBin.count)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("In Trash")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(30)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
            
            Spacer()
            
            Button(action: onHome) {
                Text("Back to Home")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white)
                    .cornerRadius(28)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

struct PermissionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            Text("Access Required")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text("TidyAlbum needs access to your photos to help you clean them up.")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal)
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }
}

// MARK: - Trash View
struct TrashView: View {
    @ObservedObject var manager: PhotoManager
    @Environment(\.dismiss) var dismiss
    
    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if manager.trashBin.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "trash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("Trash is Empty")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(manager.trashBin, id: \.localIdentifier) { asset in
                                ZStack(alignment: .bottomTrailing) {
                                    AssetMediaView(asset: asset)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipped()
                                    
                                    Button(action: {
                                        withAnimation {
                                            manager.restoreFromTrash(asset: asset)
                                        }
                                    }) {
                                        Image(systemName: "arrow.uturn.backward.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                            .padding(4)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trash Bin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !manager.trashBin.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                manager.emptyTrash()
                            } label: {
                                Label("Empty Trash", systemImage: "trash")
                            }
                            
                            Button {
                                manager.restoreAllFromTrash()
                            } label: {
                                Label("Restore All", systemImage: "arrow.uturn.backward")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
