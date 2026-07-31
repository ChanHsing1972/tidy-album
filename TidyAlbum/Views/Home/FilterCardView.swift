import SwiftUI

// MARK: - Library Collection Cell

struct FilterCardView: View {
    let filter: PhotoFilter
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var bounceTrigger = 0

    var body: some View {
        Button(action: action) {
            // 💡 1. 显式设为 .center 对齐，确保大图标与两行文字垂直居中同步
            HStack(alignment: .center, spacing: 12) {
                // 💡 2. 调大图标字号（如 .title2 / .title3），并移除了固定 frame(width:34, height:34)
                Image(systemName: filter.icon)
                    .font(.title.weight(.medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, options: .nonRepeating, value: bounceTrigger)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
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
        .onChange(of: isSelected) { _, selected in
            if selected { bounceTrigger += 1 }
        }
    }
}
