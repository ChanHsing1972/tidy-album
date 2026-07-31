import SwiftUI

// MARK: - Library Collection Cell

struct FilterCardView: View {
    let filter: PhotoFilter
    let title: String
    let count: Int
    let isSelected: Bool
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: filter.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(.primary.opacity(0.06), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text("\(count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.04), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: isSelected)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}
