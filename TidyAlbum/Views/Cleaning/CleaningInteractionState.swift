import Observation
import SwiftUI

@MainActor
@Observable
final class CleaningInteractionState {
    private(set) var backdropTransition = BackdropTransition.idle

    func setBackdropTransition(_ transition: BackdropTransition) {
        guard backdropTransition != transition else { return }
        backdropTransition = transition
    }

    func resetBackdropTransition() {
        setBackdropTransition(.idle)
    }
}

struct BackdropTransition: Equatable {
    var sourceID: String?
    var targetID: String?
    var progress: CGFloat

    static let idle = BackdropTransition(sourceID: nil, targetID: nil, progress: 0)
}

struct CleaningDeletionGeometry: Equatable {
    let pageIndex: Int
    let entryEdge: CGFloat
}

enum CleaningMotionGeometry {
    static func deletionTarget(currentIndex: Int, assetCount: Int) -> CleaningDeletionGeometry? {
        guard assetCount > 0, (0..<assetCount).contains(currentIndex) else { return nil }
        if currentIndex + 1 < assetCount {
            return CleaningDeletionGeometry(pageIndex: currentIndex + 1, entryEdge: 1)
        }
        if currentIndex > 0 {
            return CleaningDeletionGeometry(pageIndex: currentIndex - 1, entryEdge: -1)
        }
        return CleaningDeletionGeometry(pageIndex: assetCount, entryEdge: -1)
    }

    static func deletionProgress(verticalTranslation: CGFloat, revealDistance: CGFloat) -> CGFloat {
        guard verticalTranslation < 0, revealDistance > 0 else { return 0 }
        return min(-verticalTranslation / revealDistance, 1)
    }

    static func incomingOffset(entryEdge: CGFloat, pageWidth: CGFloat, progress: CGFloat) -> CGFloat {
        entryEdge * pageWidth * (1 - min(max(progress, 0), 1))
    }
}
