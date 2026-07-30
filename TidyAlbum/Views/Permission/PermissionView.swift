import SwiftUI

// MARK: - 权限请求视图 (Permission View)
/// 当用户未授权照片库访问权限时显示的引导页面。
/// 提供跳转至系统设置的入口。
struct PermissionView: View {

    // MARK: - Body

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.large) {
            Image(systemName: "lock.shield.fill")
                .font(DesignTokens.Typography.lockIcon)
                .foregroundColor(DesignTokens.Colors.accentBlue)

            Text("Access Required")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(DesignTokens.Colors.textPrimary)

            Text("TidyAlbum needs access to your photos to help you clean them up.")
                .multilineTextAlignment(.center)
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .padding(.horizontal)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .padding()
            .background(DesignTokens.Colors.accentBlue)
            .foregroundColor(DesignTokens.Colors.textPrimary)
            .cornerRadius(DesignTokens.CornerRadius.small)
        }
    }
}