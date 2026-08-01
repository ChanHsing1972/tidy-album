import SwiftUI

// MARK: - Welcome Onboarding

struct WelcomeView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        ScrollView {
            VStack(spacing: 36) {
                welcomeHeader
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible || reduceMotion ? 0 : 12)
                    .animation(revealAnimation(delay: 0), value: isVisible)
                VStack(spacing: 0) {
                    WelcomeFeatureRow(
                        icon: "hand.draw.fill",
                        color: .blue,
                        title: settings.t("Swipe to Review"),
                        description: settings.t("Swipe up to delete, down to favorite. Left and right to browse.")
                    )
                    Divider().padding(.leading, 58)
                    WelcomeFeatureRow(
                        icon: "lock.shield.fill",
                        color: .green,
                        title: settings.t("Private & Local"),
                        description: settings.t("Everything stays on your device. No data is ever uploaded.")
                    )
                    Divider().padding(.leading, 58)
                    WelcomeFeatureRow(
                        icon: "chart.bar.xaxis",
                        color: .orange,
                        title: settings.t("Track Progress"),
                        description: settings.t("See how much space you've reclaimed over time.")
                    )
                }
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible || reduceMotion ? 0 : 16)
                .animation(revealAnimation(delay: 0.1), value: isVisible)
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 24)
            .padding(.top, 44)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                dismiss()
            } label: {
                Text(settings.t("Get Started"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
            .opacity(isVisible ? 1 : 0)
            .animation(revealAnimation(delay: 0.18), value: isVisible)
        }
        .onAppear { isVisible = true }
    }

    private var welcomeHeader: some View {
        VStack(spacing: 20) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 86, height: 86)
                    .shadow(color: Color.accentColor.opacity(0.24), radius: 18, y: 8)
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 86, height: 86)
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.yellow)
                    .padding(8)
                    .background(.black.opacity(0.62), in: Circle())
                    .offset(x: 9, y: -9)
            }
            VStack(spacing: 8) {
                Text("TidyAlbum")
                    .font(.largeTitle.bold())
                Text(settings.t("Make room for what matters."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func revealAnimation(delay: Double) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.5).delay(delay)
    }
}

private struct WelcomeFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.11), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
    }
}
