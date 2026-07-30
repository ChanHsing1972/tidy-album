import SwiftUI

// MARK: - 首页视图 (Home View)
/// 展示照片统计概览、筛选条件选择和开始清理入口。
struct HomeView: View {

    // MARK: 依赖

    @ObservedObject var manager: PhotoManager

    // MARK: 回调

    /// 点击"开始清理"后的回调
    var onStart: () -> Void
    /// 点击垃圾桶按钮的回调
    var onShowTrash: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.section) {
            headerSection
            statsSection
            filterSection
            Spacer()
            startButton
        }
        .padding(DesignTokens.Spacing.large)
    }

    // MARK: - 头部区域 (Header)

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Good Day")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(DesignTokens.Colors.textSecondary)

                Text("TidyAlbum")
                    .font(DesignTokens.Typography.hero)
                    .foregroundStyle(DesignTokens.Colors.gradientTitle)
            }
            Spacer()

            Button(action: onShowTrash) {
                Circle()
                    .fill(DesignTokens.Colors.textPrimary.opacity(DesignTokens.Opacity.materialBackground))
                    .frame(
                        width: DesignTokens.Dimensions.trashButtonSize,
                        height: DesignTokens.Dimensions.trashButtonSize
                    )
                    .overlay {
                        Image(systemName: "trash")
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                    }
            }
        }
        .padding(.top, DesignTokens.Spacing.large)
    }

    // MARK: - 统计区域 (Stats)

    private var statsSection: some View {
        VStack(spacing: DesignTokens.Spacing.large) {
            HStack {
                StatItemView(
                    value: "\(manager.assets.count)",
                    title: "Remaining",
                    icon: "photo.on.rectangle"
                )
                Divider()
                    .background(DesignTokens.Colors.divider)
                StatItemView(
                    value: "\(manager.trashBin.count)",
                    title: "In Trash",
                    icon: "trash"
                )
            }
        }
        .padding(DesignTokens.Spacing.large)
        .background(.ultraThinMaterial)
        .cornerRadius(DesignTokens.CornerRadius.large)
    }

    // MARK: - 筛选区域 (Filter)

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.relaxed) {
            Text("Start Cleaning")
                .font(.headline)
                .foregroundColor(DesignTokens.Colors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.relaxed) {
                    ForEach(PhotoFilter.allCases) { filter in
                        FilterCardView(
                            filter: filter,
                            isSelected: manager.currentFilter == filter
                        ) {
                            manager.setFilter(filter)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 开始按钮 (Start Button)

    private var startButton: some View {
        Button(action: onStart) {
            HStack {
                Text("Start Session")
                    .font(DesignTokens.Typography.title3)
                Image(systemName: "arrow.right")
            }
            .foregroundColor(DesignTokens.Colors.textOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: DesignTokens.Dimensions.primaryButtonHeight)
            .background(DesignTokens.Colors.textPrimary)
            .cornerRadius(DesignTokens.CornerRadius.full)
            .shadow(
                color: DesignTokens.Shadow.glowButton.color,
                radius: DesignTokens.Shadow.glowButton.radius,
                x: DesignTokens.Shadow.glowButton.x,
                y: DesignTokens.Shadow.glowButton.y
            )
        }
    }
}