import CoreGraphics

struct CleaningDeletionGeometry: Equatable {
    let pageIndex: Int
    let entryEdge: CGFloat
}

enum CleaningMotionAxis {
    case undetermined
    case horizontal
    case vertical
}

struct CleaningPageMotion: Equatable {
    let translation: CGPoint
    let scale: CGFloat
    let zPosition: CGFloat
}

enum CleaningPinchIntent: Equatable {
    case undetermined
    case timeline
    case inspection
}

enum CleaningMotionGeometry {
    static func lockedVerticalComponent(_ value: CGFloat, intent: CGFloat) -> CGFloat {
        intent < 0 ? min(value, 0) : max(value, 0)
    }

    static func resolvedPinchIntent(
        current: CleaningPinchIntent,
        startingScale: CGFloat,
        gestureScale: CGFloat
    ) -> CleaningPinchIntent {
        if current != .undetermined { return current }
        if startingScale > 1.03 { return .inspection }
        if gestureScale < 0.97 { return .timeline }
        if gestureScale > 1.03 { return .inspection }
        return .undetermined
    }

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

    static func resistedVerticalOffset(_ value: CGFloat, threshold: CGFloat) -> CGFloat {
        let magnitude = abs(value)
        let resisted = magnitude <= threshold
            ? magnitude
            : threshold + (magnitude - threshold) * 0.58
        return value < 0 ? -resisted : resisted
    }

    static func pageMotion(
        pageIndex: Int,
        currentPageIndex: Int,
        pageWidth: CGFloat,
        axis: CleaningMotionAxis,
        translation: CGPoint,
        isDeleting: Bool,
        deletionTarget: CleaningDeletionGeometry?,
        deletionProgress: CGFloat,
        actionThreshold: CGFloat
    ) -> CleaningPageMotion {
        let relation = pageIndex - currentPageIndex
        let isCurrent = relation == 0
        var x = CGFloat(relation) * pageWidth
        var y: CGFloat = 0
        var scale: CGFloat = 1

        switch axis {
        case .horizontal:
            x += translation.x
        case .vertical:
            if isCurrent {
                y = isDeleting
                    ? translation.y
                    : resistedVerticalOffset(translation.y, threshold: actionThreshold)
                let progress = min(abs(translation.y) / actionThreshold, 1)
                scale = 1 - progress * 0.018
            } else if deletionTarget?.pageIndex == pageIndex, deletionProgress > 0 {
                x = incomingOffset(
                    entryEdge: deletionTarget?.entryEdge ?? 1,
                    pageWidth: pageWidth,
                    progress: deletionProgress
                )
            }
        case .undetermined:
            break
        }

        let zPosition: CGFloat
        if isCurrent {
            zPosition = 10
        } else if deletionTarget?.pageIndex == pageIndex, deletionProgress > 0 {
            zPosition = 9
        } else {
            zPosition = CGFloat(4 - abs(relation))
        }
        return CleaningPageMotion(
            translation: CGPoint(x: x, y: y),
            scale: scale,
            zPosition: zPosition
        )
    }
}
