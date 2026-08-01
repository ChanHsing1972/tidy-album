import SwiftUI
import Inject

// MARK: - Action Overlay

struct IconOverlayView: View {
    @ObserveInjection var inject
    let icon: String
    let color: Color
    let progress: CGFloat

    var body: some View {
        let _ = inject
        Image(systemName: icon)
            .font(.system(size: 42, weight: .semibold))
            .foregroundStyle(.white)
            .padding(22)
            .background(color, in: Circle())
            .scaleEffect(0.72 + progress * 0.38)
            .opacity(progress)
    }
}
