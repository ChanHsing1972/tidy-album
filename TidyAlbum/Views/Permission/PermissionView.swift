import Photos
import SwiftUI
import Inject

// MARK: - Photo Access Prompt

struct PermissionView: View {
    @ObserveInjection var inject
    @ObservedObject var settings: SettingsStore

    var body: some View {
        let _ = inject
        ContentUnavailableView {
            Label(settings.t("Photo Access Required"), systemImage: "lock.shield")
        } description: {
            Text(settings.t("TidyAlbum needs access to help you review and clean your library."))
        } actions: {
            Button(settings.t("Open Settings"), systemImage: "gearshape") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
