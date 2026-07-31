import SwiftUI

// MARK: - Welcome Onboarding

struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.blue)
                    .frame(width: 88, height: 88)
                    .background(.blue.opacity(0.1), in: Circle())

                VStack(spacing: 8) {
                    Text("TidyAlbum")
                        .font(.largeTitle.weight(.bold))
                    Text("Make room for what matters.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                FeatureRow(
                    icon: "hand.draw",
                    title: "Swipe to Review",
                    description: "Swipe up to delete, down to favorite. Left and right to browse."
                )
                FeatureRow(
                    icon: "lock.shield",
                    title: "Private & Local",
                    description: "Everything stays on your device. No data is ever uploaded."
                )
                FeatureRow(
                    icon: "chart.bar.xaxis",
                    title: "Track Progress",
                    description: "See how much space you've reclaimed over time."
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(.primary.opacity(0.06), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}