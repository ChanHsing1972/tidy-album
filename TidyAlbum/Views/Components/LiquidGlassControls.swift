import SwiftUI

// MARK: - Liquid Glass Controls

struct GlassIconLabel: View {
    let systemName: String
    var isBusy = false
    var badgeCount = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemName)
                        .font(.body.weight(.semibold))
                }
            }
            .frame(width: 46, height: 46)
            .contentShape(Circle())
            .liquidGlassCircle()

            if badgeCount > 0 {
                Text("\(min(badgeCount, 99))")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, badgeCount > 9 ? 5 : 0)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(.red, in: Capsule())
                    .offset(x: 3, y: -3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: badgeCount)
    }
}

extension View {
    @ViewBuilder
    func liquidGlassCircle() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Circle())
        } else {
            background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.16), lineWidth: 0.5) }
        }
    }

    @ViewBuilder
    func liquidGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.16), lineWidth: 0.5) }
        }
    }
}
