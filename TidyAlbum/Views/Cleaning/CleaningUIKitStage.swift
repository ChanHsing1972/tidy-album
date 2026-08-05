import Photos
import SwiftUI
import UIKit

enum CleaningPageID {
    static let groupCompletion = "tidyalbum.group-completion"
}

struct CleaningSelectionAnimationRequest: Equatable {
    enum Style: Equatable {
        case deletionRestore
        case reviewReveal
    }

    let token: UUID
    let assetIdentifier: String
    let style: Style
}

struct CleaningUIKitCardStage: UIViewControllerRepresentable {
    let session: CleaningUIKitSession
    let assets: [PHAsset]
    @Binding var selectedAssetID: String
    let selectionAnimationRequest: CleaningSelectionAnimationRequest?
    let settings: SettingsStore
    let hapticsEnabled: Bool
    let hasNextGroup: Bool
    let groupNumber: Int
    let groupCount: Int
    let isFavorite: (PHAsset) -> Bool
    let onDelete: (PHAsset, Int) -> Void
    let onToggleFavorite: (PHAsset, Int) -> Void
    let onAddToAlbum: (PHAsset) -> Void
    let timelineTargetColumn: Int
    let onTimelinePreviewChange: (Bool) -> Void
    let onShowTimeline: () -> Void
    let onImmersiveChange: (Bool) -> Void
    let onCompletionControlsHiddenChange: (Bool) -> Void
    let onSelectionAnimationFinished: (UUID) -> Void
    let onNextGroup: () -> Void
    let onEnd: () -> Void

    func makeUIViewController(context: Context) -> CleaningCardStageController {
        CleaningCardStageController(session: session)
    }

    func updateUIViewController(_ controller: CleaningCardStageController, context: Context) {
        let completion = CleaningCompletionContent(
            hasNextGroup: hasNextGroup,
            groupNumber: groupNumber,
            groupCount: groupCount,
            title: settings.t(hasNextGroup ? "Group Complete" : "All Done"),
            progressText: groupCount > 1
                ? String(format: settings.t("Group X of Y"), groupNumber, groupCount)
                : nil,
            primaryTitle: settings.t(hasNextGroup ? "Clean Next Group" : "Finish"),
            secondaryTitle: hasNextGroup ? settings.t("Finish Session") : nil
        )
        controller.configure(
            assets: assets,
            selectedAssetID: selectedAssetID,
            selectionAnimationRequest: selectionAnimationRequest,
            hapticsEnabled: hapticsEnabled,
            autoPlayLivePhotos: settings.autoPlayLivePhotos,
            downwardSwipeAction: settings.downwardSwipeAction,
            favoriteIdentifiers: Set(assets.lazy.filter(isFavorite).map(\.localIdentifier)),
            completionContent: completion,
            onSelection: { selectedAssetID = $0 },
            onDelete: onDelete,
            onToggleFavorite: onToggleFavorite,
            onAddToAlbum: onAddToAlbum,
            timelineTargetColumn: timelineTargetColumn,
            onTimelinePreviewChange: onTimelinePreviewChange,
            onShowTimeline: onShowTimeline,
            onImmersiveChange: onImmersiveChange,
            onCompletionControlsHiddenChange: onCompletionControlsHiddenChange,
            onSelectionAnimationFinished: onSelectionAnimationFinished,
            onNextGroup: onNextGroup,
            onEnd: onEnd
        )
    }

    static func dismantleUIViewController(
        _ controller: CleaningCardStageController,
        coordinator: Void
    ) {
        controller.tearDown()
    }
}

struct CleaningCompletionContent: Equatable {
    let hasNextGroup: Bool
    let groupNumber: Int
    let groupCount: Int
    let title: String
    let progressText: String?
    let primaryTitle: String
    let secondaryTitle: String?
}

@MainActor
final class CleaningCardStageController: UIViewController, UIGestureRecognizerDelegate {
    private let session: CleaningUIKitSession
    private let actionThreshold: CGFloat = 92
    private let pageSpacing: CGFloat = 18
    private var assets: [PHAsset] = []
    private var selectedAssetID = ""
    private var favoriteIdentifiers: Set<String> = []
    private var assetIndexByID: [String: Int] = [:]
    private var completionContent: CleaningCompletionContent?
    private var cardViews: [String: CleaningCardPageView] = [:]
    private var completionView: CleaningCompletionPageView?
    private var axis = CleaningMotionAxis.undetermined
    private var verticalIntent: CGFloat?
    private var translation = CGPoint.zero
    private var deletionProgress: CGFloat = 0
    private var isDeleting = false
    private var isTransitioning = false
    private var thresholdCrossed = false
    private var deliveredHapticDirection: CGFloat?
    private var committedActionDirection: CGFloat?
    private var undoAnimationTargetID: String?
    private var undoAnimationProgress: CGFloat = 0
    private var undoAnimationStyle = CleaningSelectionAnimationRequest.Style.deletionRestore
    private var backdropTargetID: String?
    private var animator: UIViewPropertyAnimator?
    private var inspectionAnimator: UIViewPropertyAnimator?
    private var pinchIntent = CleaningPinchIntent.undetermined
    private var viewingScale: CGFloat = 1
    private var viewingTranslation = CGPoint.zero
    private var pinchStartScale: CGFloat = 1
    private var pinchStartTranslation = CGPoint.zero
    private var pinchStartLocation = CGPoint.zero
    private var inspectionPanStart = CGPoint.zero
    private var isImmersive = false
    private var timelineTransitionProgress: CGFloat = 0
    private var timelineTargetColumn = 1
    private var isTimelinePreviewVisible = false
    private var completionControlsHidden = false
    private var hapticsEnabled = true
    private var autoPlayLivePhotos = true
    private var downwardSwipeAction = DownwardSwipeAction.favorite
    private var lastSelectionAnimationToken: UUID?
    private let deletionHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let favoriteHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let boundaryHaptic = UIImpactFeedbackGenerator(style: .soft)

    private var onSelection: ((String) -> Void)?
    private var onDelete: ((PHAsset, Int) -> Void)?
    private var onToggleFavorite: ((PHAsset, Int) -> Void)?
    private var onAddToAlbum: ((PHAsset) -> Void)?
    private var onTimelinePreviewChange: ((Bool) -> Void)?
    private var onShowTimeline: (() -> Void)?
    private var onImmersiveChange: ((Bool) -> Void)?
    private var onCompletionControlsHiddenChange: ((Bool) -> Void)?
    private var onSelectionAnimationFinished: ((UUID) -> Void)?
    private var onNextGroup: (() -> Void)?
    private var onEnd: (() -> Void)?

    init(session: CleaningUIKitSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = false
        view.accessibilityIdentifier = "tidyalbum.cleaning-stage"
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        doubleTap.cancelsTouchesInView = false
        view.addGestureRecognizer(doubleTap)

    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for page in cardViews.values { positionPageAtRest(page) }
        if let completionView { positionPageAtRest(completionView) }
        // A SwiftUI toolbar update can trigger layout while the undo animator is
        // running. Reapplying the model's end transform here would skip the
        // presentation-layer animation and make the restored card appear at once.
        if undoAnimationTargetID == nil {
            applyTransformsWithoutAnimation()
        }
    }

    func configure(
        assets: [PHAsset],
        selectedAssetID: String,
        selectionAnimationRequest: CleaningSelectionAnimationRequest?,
        hapticsEnabled: Bool,
        autoPlayLivePhotos: Bool,
        downwardSwipeAction: DownwardSwipeAction,
        favoriteIdentifiers: Set<String>,
        completionContent: CleaningCompletionContent,
        onSelection: @escaping (String) -> Void,
        onDelete: @escaping (PHAsset, Int) -> Void,
        onToggleFavorite: @escaping (PHAsset, Int) -> Void,
        onAddToAlbum: @escaping (PHAsset) -> Void,
        timelineTargetColumn: Int,
        onTimelinePreviewChange: @escaping (Bool) -> Void,
        onShowTimeline: @escaping () -> Void,
        onImmersiveChange: @escaping (Bool) -> Void,
        onCompletionControlsHiddenChange: @escaping (Bool) -> Void,
        onSelectionAnimationFinished: @escaping (UUID) -> Void,
        onNextGroup: @escaping () -> Void,
        onEnd: @escaping () -> Void
    ) {
        self.onSelection = onSelection
        self.onDelete = onDelete
        self.onToggleFavorite = onToggleFavorite
        self.onAddToAlbum = onAddToAlbum
        self.timelineTargetColumn = min(max(timelineTargetColumn, 0), 2)
        self.onTimelinePreviewChange = onTimelinePreviewChange
        self.onShowTimeline = onShowTimeline
        self.onImmersiveChange = onImmersiveChange
        self.onCompletionControlsHiddenChange = onCompletionControlsHiddenChange
        self.onSelectionAnimationFinished = onSelectionAnimationFinished
        self.onNextGroup = onNextGroup
        self.onEnd = onEnd
        self.hapticsEnabled = hapticsEnabled
        self.autoPlayLivePhotos = autoPlayLivePhotos
        self.downwardSwipeAction = downwardSwipeAction
        self.favoriteIdentifiers = favoriteIdentifiers
        self.completionContent = completionContent

        let requestedAnimation = selectionAnimationRequest.flatMap { request in
            request.token != lastSelectionAnimationToken
                && request.assetIdentifier == selectedAssetID ? request : nil
        }
        let assetsChanged = self.assets.map(\.localIdentifier) != assets.map(\.localIdentifier)
        self.assets = assets
        assetIndexByID = Dictionary(
            uniqueKeysWithValues: assets.enumerated().map { ($0.element.localIdentifier, $0.offset) }
        )
        if requestedAnimation != nil, isTransitioning {
            finishTransitionForNewGestureIfNeeded()
        }
        let previousSelectionID = self.selectedAssetID
        let selectionChanged = previousSelectionID != selectedAssetID
        if selectionChanged, viewingScale != 1 || timelineTransitionProgress != 0 {
            resetViewingState(animated: false)
            resetTimelineTransition(animated: false, keepPreview: false)
        }
        if selectionChanged {
            if let requestedAnimation,
               !previousSelectionID.isEmpty,
               pageIndex(for: selectedAssetID) != nil,
               view.window != nil {
                reconcilePages()
                lastSelectionAnimationToken = requestedAnimation.token
                animateSelectionUndo(requestedAnimation)
                return
            }
            if !isTransitioning,
               !previousSelectionID.isEmpty,
               let sourceIndex = pageIndex(for: previousSelectionID),
               let destinationIndex = pageIndex(for: selectedAssetID),
               abs(destinationIndex - sourceIndex) == 1,
               view.window != nil {
                reconcilePages()
                if let requestedAnimation {
                    lastSelectionAnimationToken = requestedAnimation.token
                }
                animateExternalSelection(
                    to: selectedAssetID,
                    direction: destinationIndex > sourceIndex ? 1 : -1
                )
                return
            }
            animator?.stopAnimation(true)
            isTransitioning = false
            resetMotion()
            self.selectedAssetID = selectedAssetID
            session.commitSelection(selectedAssetID)
        }
        if let requestedAnimation {
            lastSelectionAnimationToken = requestedAnimation.token
            DispatchQueue.main.async { [weak self] in
                self?.onSelectionAnimationFinished?(requestedAnimation.token)
            }
        }
        if assetsChanged || selectionChanged {
            reconcilePages()
        } else {
            updatePageContent()
        }
        view.setNeedsLayout()
        if !isTransitioning, axis == .undetermined {
            setCompletionControlsHidden(selectedAssetID == CleaningPageID.groupCompletion)
        }
    }

    func tearDown() {
        animator?.stopAnimation(true)
        inspectionAnimator?.stopAnimation(true)
        animator = nil
        setTimelinePreviewVisible(false)
        session.cancelTransition()
        cardViews.values.forEach { $0.tearDown() }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        finishTransitionForNewGestureIfNeeded()
        if gestureRecognizer is UIPinchGestureRecognizer || gestureRecognizer is UITapGestureRecognizer {
            return !isTransitioning && currentIndex != nil
        }
        return !isTransitioning && currentPageIndex != nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .recognized,
              !isTransitioning,
              let currentIndex,
              assets.indices.contains(currentIndex) else { return }
        inspectionAnimator?.stopAnimation(true)
        applyTransformsWithoutAnimation()
        let asset = assets[currentIndex]
        let identifier = asset.localIdentifier
        if favoriteIdentifiers.contains(identifier) {
            favoriteIdentifiers.remove(identifier)
        } else {
            favoriteIdentifiers.insert(identifier)
        }
        updatePageContent()
        if hapticsEnabled {
            favoriteHaptic.prepare()
            favoriteHaptic.impactOccurred()
        }
        onToggleFavorite?(asset, currentIndex)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard !isTransitioning, currentIndex != nil else { return }
        switch recognizer.state {
        case .began:
            inspectionAnimator?.stopAnimation(true)
            resetMotion()
            pinchStartScale = viewingScale
            pinchStartTranslation = viewingTranslation
            pinchStartLocation = recognizer.location(in: view)
            pinchIntent = CleaningMotionGeometry.resolvedPinchIntent(
                current: .undetermined,
                startingScale: viewingScale,
                gestureScale: 1
            )
            timelineTransitionProgress = 0
        case .changed:
            if pinchIntent == .undetermined {
                pinchIntent = CleaningMotionGeometry.resolvedPinchIntent(
                    current: pinchIntent,
                    startingScale: pinchStartScale,
                    gestureScale: recognizer.scale
                )
                if pinchIntent == .timeline {
                    setTimelinePreviewVisible(true)
                    setImmersive(false)
                } else if pinchIntent == .undetermined {
                    return
                }
            }
            let location = recognizer.location(in: view)
            let startRelative = CGPoint(
                x: pinchStartLocation.x - view.bounds.midX,
                y: pinchStartLocation.y - view.bounds.midY
            )
            let currentRelative = CGPoint(
                x: location.x - view.bounds.midX,
                y: location.y - view.bounds.midY
            )
            if pinchIntent == .timeline {
                let rawScale = min(max(recognizer.scale, 0.55), 1)
                timelineTransitionProgress = min(max((1 - rawScale) / 0.45, 0), 1)
                viewingScale = 1
                viewingTranslation = CGPoint(
                    x: (currentRelative.x - startRelative.x) * (1 - timelineTransitionProgress),
                    y: (currentRelative.y - startRelative.y) * (1 - timelineTransitionProgress)
                )
            } else {
                // Once a gesture starts as inspection, pinching back can only
                // return to the fitted image. It cannot cross into the timeline
                // action until the fingers lift and a new pinch begins.
                let targetScale = min(max(pinchStartScale * recognizer.scale, 1), 4)
                let ratio = targetScale / max(pinchStartScale, 0.001)
                let followingTranslation = CGPoint(
                    x: pinchStartTranslation.x + currentRelative.x - startRelative.x
                        + startRelative.x * (1 - ratio),
                    y: pinchStartTranslation.y + currentRelative.y - startRelative.y
                        + startRelative.y * (1 - ratio)
                )
                viewingScale = targetScale
                viewingTranslation = clampedViewingTranslation(
                    followingTranslation,
                    scale: targetScale
                )
                setImmersive(targetScale > 1.03)
            }
            applyTransformsWithoutAnimation()
        case .ended:
            if pinchIntent == .timeline {
                if timelineTransitionProgress >= 0.72 || recognizer.velocity < -1.2 {
                    finishTimelineTransition()
                } else {
                    resetTimelineTransition(animated: true, keepPreview: false)
                }
            } else if viewingScale < 1.03 {
                resetViewingState(animated: true)
            } else {
                viewingScale = min(viewingScale, 4)
                viewingTranslation = clampedViewingTranslation(viewingTranslation, scale: viewingScale)
                setImmersive(true)
                applyTransformsWithoutAnimation()
            }
        case .cancelled, .failed:
            if pinchIntent == .timeline {
                resetTimelineTransition(animated: true, keepPreview: false)
            } else if viewingScale < 1.03 {
                resetViewingState(animated: true)
            }
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard !isTransitioning else { return }
            inspectionAnimator?.stopAnimation(true)
            applyTransformsWithoutAnimation()
            if viewingScale > 1 {
                inspectionPanStart = viewingTranslation
                return
            }
            deliveredHapticDirection = nil
            committedActionDirection = nil
            prepareHaptics()
        case .changed:
            guard !isTransitioning else { return }
            if viewingScale > 1 {
                let value = recognizer.translation(in: view)
                viewingTranslation = clampedViewingTranslation(
                    CGPoint(x: inspectionPanStart.x + value.x, y: inspectionPanStart.y + value.y),
                    scale: viewingScale
                )
                applyTransformsWithoutAnimation()
                return
            }
            let value = recognizer.translation(in: view)
            if axis == .undetermined {
                let horizontal = abs(value.x)
                let vertical = abs(value.y)
                guard max(horizontal, vertical) > 10 else { return }
                axis = vertical > horizontal * 1.15 ? .vertical : .horizontal
                if axis == .vertical { verticalIntent = value.y < 0 ? -1 : 1 }
            }
            applyInteractiveTranslation(value)
            updateThresholdHaptic(with: translation)
        case .ended:
            guard !isTransitioning else { return }
            if viewingScale > 1 {
                viewingTranslation = clampedViewingTranslation(viewingTranslation, scale: viewingScale)
                applyTransformsWithoutAnimation()
                return
            }
            if axis != .undetermined {
                applyInteractiveTranslation(recognizer.translation(in: view))
            }
            finishGesture(velocity: recognizer.velocity(in: view))
        case .cancelled, .failed:
            guard !isTransitioning else { return }
            resetGesture(animated: true)
        default:
            break
        }
    }

    private func applyInteractiveTranslation(_ value: CGPoint) {
        if axis == .horizontal {
            translation = CGPoint(x: value.x, y: 0)
        } else {
            let lockedY: CGFloat
            if let verticalIntent {
                lockedY = CleaningMotionGeometry.lockedVerticalComponent(
                    value.y,
                    intent: verticalIntent
                )
            } else {
                lockedY = value.y
            }
            translation = CGPoint(x: 0, y: lockedY)
        }
        deletionProgress = axis == .vertical
            ? CleaningMotionGeometry.deletionProgress(
                verticalTranslation: translation.y,
                revealDistance: actionThreshold * 2.4
            )
            : 0
        applyTransformsWithoutAnimation()
        updateBackdropInteractively()
    }

    private func finishGesture(velocity: CGPoint) {
        switch axis {
        case .horizontal:
            finishHorizontalGesture(velocity: velocity.x)
        case .vertical:
            finishVerticalGesture(velocity: velocity.y)
        case .undetermined:
            resetGesture(animated: true)
        }
    }

    private func finishHorizontalGesture(velocity: CGFloat) {
        let width = pageWidth
        let projected = translation.x + velocity * 0.2
        let trigger = width * 0.2
        let direction: Int
        if projected < -trigger || translation.x < -trigger {
            direction = 1
        } else if projected > trigger || translation.x > trigger {
            direction = -1
        } else {
            resetGesture(animated: true)
            return
        }
        guard let currentPageIndex else {
            resetGesture(animated: true)
            return
        }
        let destination = currentPageIndex + direction
        guard (0...assets.count).contains(destination) else {
            playBoundaryHaptic()
            resetGesture(animated: true)
            return
        }
        let destinationID = pageID(at: destination)
        ensureBackdropTransition(targetID: destinationID)
        isTransitioning = true
        let remainingDistance = abs(-CGFloat(direction) * width - translation.x)
        let duration = settlingDuration(
            distance: remainingDistance,
            velocity: velocity,
            baselineVelocity: 1_400,
            range: 0.22...0.32
        )
        translation = CGPoint(x: -CGFloat(direction) * width, y: 0)
        animate(duration: duration, dampingRatio: 0.9, animations: {
            self.applyTransforms()
            self.session.setTransitionProgress(1)
        }) { [weak self] in
            self?.commitHorizontalSelection(destinationID)
        }
    }

    private func finishVerticalGesture(velocity: CGFloat) {
        let direction = verticalIntent ?? (translation.y < 0 ? -1 : 1)
        let lockedVelocity = CleaningMotionGeometry.lockedVerticalComponent(
            velocity,
            intent: direction
        )
        let projected = translation.y + lockedVelocity * 0.2
        let shouldCommit = abs(translation.y) >= actionThreshold
            || abs(projected) >= actionThreshold * 1.35
        guard shouldCommit else {
            resetGesture(animated: true)
            return
        }
        if direction < 0 {
            commitDeletion(releaseVelocity: velocity)
        } else if downwardSwipeAction == .addToAlbum {
            commitAddToAlbum()
        } else {
            commitFavorite()
        }
    }

    private func commitDeletion(releaseVelocity: CGFloat) {
        guard let currentIndex,
              assets.indices.contains(currentIndex),
              let geometry = CleaningMotionGeometry.deletionTarget(
                  currentIndex: currentIndex,
                  assetCount: assets.count
              ) else {
            resetGesture(animated: true)
            return
        }
        let asset = assets[currentIndex]
        let destinationID = pageID(at: geometry.pageIndex)
        ensureBackdropTransition(targetID: destinationID)
        isTransitioning = true
        translation.y = resistedVerticalOffset(translation.y)
        isDeleting = true
        committedActionDirection = -1
        applyTransformsWithoutAnimation()
        deliverActionHapticIfNeeded(deleting: true)
        let destinationY = -max(view.bounds.height * 1.18, 760)
        let duration = settlingDuration(
            distance: abs(destinationY - translation.y),
            velocity: releaseVelocity,
            baselineVelocity: 2_800,
            range: 0.12...0.24
        )
        translation.y = destinationY
        deletionProgress = 1
        animate(duration: duration, curve: .easeOut, animations: {
            self.applyTransforms()
            self.session.setTransitionProgress(1)
        }) { [weak self] in
            self?.finishDeletion(asset: asset, originalIndex: currentIndex, destinationID: destinationID)
        }
    }

    private func finishDeletion(asset: PHAsset, originalIndex: Int, destinationID: String) {
        assets.removeAll { $0.localIdentifier == asset.localIdentifier }
        rebuildAssetIndex()
        selectedAssetID = destinationID
        resetMotion()
        isTransitioning = false
        session.commitSelection(destinationID)
        setCompletionControlsHidden(destinationID == CleaningPageID.groupCompletion)
        reconcilePages()
        onDelete?(asset, originalIndex)
        onSelection?(destinationID)
    }

    private func commitFavorite() {
        guard let currentIndex, assets.indices.contains(currentIndex) else {
            resetGesture(animated: true)
            return
        }
        let asset = assets[currentIndex]
        isTransitioning = true
        committedActionDirection = 1
        applyTransformsWithoutAnimation()
        deliverActionHapticIfNeeded(deleting: false)
        onToggleFavorite?(asset, currentIndex)
        resetGesture(animated: true)
    }

    private func commitAddToAlbum() {
        guard let currentIndex, assets.indices.contains(currentIndex) else {
            resetGesture(animated: true)
            return
        }
        let asset = assets[currentIndex]
        isTransitioning = true
        committedActionDirection = 1
        applyTransformsWithoutAnimation()
        deliverActionHapticIfNeeded(deleting: false)
        onAddToAlbum?(asset)
        resetGesture(animated: true)
    }

    private func commitHorizontalSelection(_ identifier: String) {
        selectedAssetID = identifier
        resetMotion()
        isTransitioning = false
        session.commitSelection(identifier)
        setCompletionControlsHidden(identifier == CleaningPageID.groupCompletion)
        reconcilePages()
        onSelection?(identifier)
    }

    private func animateExternalSelection(to identifier: String, direction: Int) {
        setCompletionControlsHidden(identifier == CleaningPageID.groupCompletion)
        ensureBackdropTransition(targetID: identifier)
        isTransitioning = true
        axis = .horizontal
        translation = CGPoint(x: -CGFloat(direction) * pageWidth, y: 0)
        animate(duration: 0.3, dampingRatio: 0.9, animations: {
            self.applyTransforms()
            self.session.setTransitionProgress(1)
        }) { [weak self] in
            guard let self else { return }
            self.selectedAssetID = identifier
            self.resetMotion()
            self.isTransitioning = false
            self.session.commitSelection(identifier)
            self.reconcilePages()
        }
    }

    private func animateSelectionUndo(_ request: CleaningSelectionAnimationRequest) {
        let identifier = request.assetIdentifier
        setCompletionControlsHidden(false)
        guard prepareUndoPage(for: identifier) else {
            selectedAssetID = identifier
            resetMotion()
            isTransitioning = false
            session.commitSelection(identifier)
            reconcilePages()
            onSelectionAnimationFinished?(request.token)
            return
        }
        resetMotion()
        undoAnimationTargetID = identifier
        undoAnimationProgress = 0
        undoAnimationStyle = request.style
        ensureBackdropTransition(targetID: identifier)
        isTransitioning = true
        applyTransformsWithoutAnimation()

        // Keep the controller in sync with the binding immediately. SwiftUI can
        // call configure again before this animator finishes; leaving the old ID
        // here causes that update to replace the undo with a normal page turn.
        selectedAssetID = identifier
        updatePageContent()
        undoAnimationProgress = 1
        let duration: TimeInterval = request.style == .deletionRestore ? 0.32 : 0.22
        animate(duration: duration, dampingRatio: 0.9, animations: {
            self.applyTransforms()
            self.session.setTransitionProgress(1)
        }) { [weak self] in
            guard let self else { return }
            self.resetMotion()
            self.isTransitioning = false
            self.session.commitSelection(identifier)
            self.reconcilePages()
            self.onSelectionAnimationFinished?(request.token)
        }
    }

    private func prepareUndoPage(for identifier: String) -> Bool {
        if cardViews[identifier] != nil { return true }
        guard let index = assetIndexByID[identifier], assets.indices.contains(index) else { return false }
        let asset = assets[index]
        let page = CleaningCardPageView()
        cardViews[identifier] = page
        positionPageAtRest(page)
        view.addSubview(page)
        page.configure(
            asset: asset,
            isFavorite: favoriteIdentifiers.contains(identifier),
            autoPlayLivePhotos: autoPlayLivePhotos,
            host: self
        )
        return true
    }

    private func resetGesture(animated: Bool) {
        translation = .zero
        deletionProgress = 0
        committedActionDirection = nil
        backdropTargetID = nil
        if !animated {
            isTransitioning = false
            applyTransformsWithoutAnimation()
            session.cancelTransition()
            setCompletionControlsHidden(selectedAssetID == CleaningPageID.groupCompletion)
            return
        }
        isTransitioning = true
        animate(duration: 0.2, dampingRatio: 0.82, animations: {
            self.applyTransforms()
            self.session.setTransitionProgress(0)
        }) { [weak self] in
            guard let self else { return }
            self.resetMotion()
            self.isTransitioning = false
            self.session.cancelTransition()
            self.setCompletionControlsHidden(
                self.selectedAssetID == CleaningPageID.groupCompletion
            )
            self.applyTransformsWithoutAnimation()
        }
    }

    private func resetViewingState(animated: Bool) {
        inspectionAnimator?.stopAnimation(true)
        pinchIntent = .undetermined
        viewingScale = 1
        viewingTranslation = .zero
        setImmersive(false)
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            applyTransformsWithoutAnimation()
            return
        }
        let animator = UIViewPropertyAnimator(duration: 0.28, dampingRatio: 0.88) {
            self.applyTransforms()
        }
        inspectionAnimator = animator
        animator.startAnimation()
    }

    private func finishTimelineTransition() {
        inspectionAnimator?.stopAnimation(true)
        timelineTransitionProgress = 1
        viewingTranslation = .zero
        let completion = { [weak self] in
            guard let self else { return }
            self.onShowTimeline?()
            self.isTimelinePreviewVisible = false
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.timelineTransitionProgress = 0
                self.pinchIntent = .undetermined
                self.applyTransformsWithoutAnimation()
            }
        }
        guard !UIAccessibility.isReduceMotionEnabled else {
            applyTransformsWithoutAnimation()
            completion()
            return
        }
        let animator = UIViewPropertyAnimator(duration: 0.12, curve: .easeOut) {
            self.applyTransforms()
        }
        inspectionAnimator = animator
        animator.addCompletion { position in
            if position == .end { completion() }
        }
        animator.startAnimation()
    }

    private func resetTimelineTransition(animated: Bool, keepPreview: Bool) {
        inspectionAnimator?.stopAnimation(true)
        timelineTransitionProgress = 0
        viewingTranslation = .zero
        pinchIntent = .undetermined
        let completion = { [weak self] in
            guard let self else { return }
            if !keepPreview { self.setTimelinePreviewVisible(false) }
        }
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            applyTransformsWithoutAnimation()
            completion()
            return
        }
        let animator = UIViewPropertyAnimator(duration: 0.18, dampingRatio: 0.92) {
            self.applyTransforms()
        }
        inspectionAnimator = animator
        animator.addCompletion { position in
            if position == .end { completion() }
        }
        animator.startAnimation()
    }

    private func setTimelinePreviewVisible(_ visible: Bool) {
        guard visible != isTimelinePreviewVisible else { return }
        isTimelinePreviewVisible = visible
        onTimelinePreviewChange?(visible)
    }

    private func setImmersive(_ immersive: Bool) {
        guard immersive != isImmersive else { return }
        isImmersive = immersive
        onImmersiveChange?(immersive)
    }

    private func setCompletionControlsHidden(_ hidden: Bool) {
        guard hidden != completionControlsHidden else { return }
        completionControlsHidden = hidden
        DispatchQueue.main.async { [weak self] in
            self?.onCompletionControlsHiddenChange?(hidden)
        }
    }

    private func clampedViewingTranslation(_ value: CGPoint, scale: CGFloat) -> CGPoint {
        guard scale > 1 else { return .zero }
        let horizontalLimit = view.bounds.width * (scale - 1) * 0.5 + 44
        let verticalLimit = view.bounds.height * (scale - 1) * 0.5 + 44
        return CGPoint(
            x: min(max(value.x, -horizontalLimit), horizontalLimit),
            y: min(max(value.y, -verticalLimit), verticalLimit)
        )
    }

    private func resetMotion() {
        axis = .undetermined
        verticalIntent = nil
        translation = .zero
        deletionProgress = 0
        isDeleting = false
        thresholdCrossed = false
        deliveredHapticDirection = nil
        committedActionDirection = nil
        undoAnimationTargetID = nil
        undoAnimationProgress = 0
        undoAnimationStyle = .deletionRestore
        backdropTargetID = nil
    }

    private func reconcilePages() {
        guard let currentPageIndex else {
            cardViews.values.forEach { $0.removeFromSuperview() }
            cardViews.removeAll()
            completionView?.removeFromSuperview()
            completionView = nil
            return
        }
        let lower = max(0, currentPageIndex - 2)
        let upper = min(assets.count, currentPageIndex + 2)
        let visibleIndices = Set(lower...upper)
        let visibleAssetIDs = Set(visibleIndices.compactMap { index in
            assets.indices.contains(index) ? assets[index].localIdentifier : nil
        })
        let obsoletePages = cardViews.filter { !visibleAssetIDs.contains($0.key) }
        for (identifier, page) in obsoletePages {
            page.tearDown()
            page.removeFromSuperview()
            cardViews[identifier] = nil
        }
        for index in visibleIndices where assets.indices.contains(index) {
            let asset = assets[index]
            let identifier = asset.localIdentifier
            let page = cardViews[identifier] ?? CleaningCardPageView()
            if page.superview == nil {
                cardViews[identifier] = page
                positionPageAtRest(page)
                view.addSubview(page)
            }
            page.configure(
                asset: asset,
                isFavorite: favoriteIdentifiers.contains(identifier),
                autoPlayLivePhotos: autoPlayLivePhotos,
                host: self
            )
        }
        if visibleIndices.contains(assets.count) {
            let page = completionView ?? CleaningCompletionPageView()
            if page.superview == nil {
                completionView = page
                positionPageAtRest(page)
                view.addSubview(page)
            }
            if let completionContent {
                page.configure(
                    content: completionContent,
                    onPrimary: { [weak self] in
                        guard let self else { return }
                        completionContent.hasNextGroup ? self.onNextGroup?() : self.onEnd?()
                    },
                    onSecondary: { [weak self] in self?.onEnd?() }
                )
            }
        } else {
            completionView?.removeFromSuperview()
            completionView = nil
        }
        updatePageContent()
        applyTransformsWithoutAnimation()
    }

    private func updatePageContent() {
        for (identifier, page) in cardViews {
            let active = identifier == selectedAssetID
            page.setFavorite(favoriteIdentifiers.contains(identifier))
            page.setAutoPlayLivePhotos(autoPlayLivePhotos, host: self)
            page.setActive(active, host: self)
            page.accessibilityIdentifier = active
                ? "tidyalbum.cleaning-card.current"
                : "tidyalbum.cleaning-card.inactive"
            page.accessibilityElementsHidden = !active
        }
        let completionIsActive = selectedAssetID == CleaningPageID.groupCompletion
        completionView?.setActive(completionIsActive, animated: true)
        completionView?.accessibilityElementsHidden = !completionIsActive
    }

    private func applyTransformsWithoutAnimation() {
        UIView.performWithoutAnimation { applyTransforms() }
    }

    private func applyTransforms() {
        guard let currentPageIndex else { return }
        let deletionTarget = CleaningMotionGeometry.deletionTarget(
            currentIndex: currentIndex ?? -1,
            assetCount: assets.count
        )
        for (identifier, page) in cardViews {
            guard let index = assetIndexByID[identifier] else { continue }
            let motion = CleaningMotionGeometry.pageMotion(
                pageIndex: index,
                currentPageIndex: currentPageIndex,
                pageWidth: pageWidth,
                axis: axis,
                translation: translation,
                isDeleting: isDeleting,
                deletionTarget: deletionTarget,
                deletionProgress: deletionProgress,
                actionThreshold: actionThreshold
            )
            if identifier == undoAnimationTargetID {
                if undoAnimationStyle == .deletionRestore {
                    let entryY = -max(view.bounds.height * 1.18, 760) * (1 - undoAnimationProgress)
                    let scale = 0.982 + 0.018 * undoAnimationProgress
                    page.layer.setAffineTransform(
                        CGAffineTransform(translationX: 0, y: entryY)
                            .scaledBy(x: scale, y: scale)
                    )
                    page.alpha = 0.84 + 0.16 * undoAnimationProgress
                } else {
                    let scale = 0.94 + 0.06 * undoAnimationProgress
                    page.layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
                    page.alpha = undoAnimationProgress
                }
                page.layer.zPosition = 20
            } else {
                let isCurrent = index == currentPageIndex
                let scale = motion.scale * (isCurrent ? viewingScale : 1)
                let viewingOffset = isCurrent ? viewingTranslation : .zero
                page.layer.setAffineTransform(
                    CGAffineTransform(
                        translationX: motion.translation.x + viewingOffset.x,
                        y: motion.translation.y + viewingOffset.y
                    ).scaledBy(x: scale, y: scale)
                )
                page.layer.zPosition = motion.zPosition
                page.alpha = isCurrent && viewingScale < 1
                    ? 0.55 + 0.45 * viewingScale
                    : 1
            }
            let timelineSide = max((view.bounds.width - 4) / 3, 1)
            let timelineCenterX = timelineSide * 0.5
                + CGFloat(timelineTargetColumn) * (timelineSide + 2)
            page.setTimelineTransition(
                progress: index == currentPageIndex ? timelineTransitionProgress : 0,
                targetSide: timelineSide,
                targetCenterX: timelineCenterX
            )
            let actionTranslation = committedActionDirection.map { $0 * actionThreshold }
                ?? (axis == .vertical ? translation.y : 0)
            page.setActionProgress(
                translation: index == currentPageIndex ? actionTranslation : 0,
                isFavorite: favoriteIdentifiers.contains(identifier),
                downwardAction: downwardSwipeAction
            )
        }
        if let completionView {
            let index = assets.count
            let motion = CleaningMotionGeometry.pageMotion(
                pageIndex: index,
                currentPageIndex: currentPageIndex,
                pageWidth: pageWidth,
                axis: axis,
                translation: translation,
                isDeleting: isDeleting,
                deletionTarget: deletionTarget,
                deletionProgress: deletionProgress,
                actionThreshold: actionThreshold
            )
            completionView.layer.setAffineTransform(
                CGAffineTransform(
                    translationX: motion.translation.x,
                    y: motion.translation.y
                ).scaledBy(x: motion.scale, y: motion.scale)
            )
            completionView.layer.zPosition = motion.zPosition
        }
    }

    private func updateBackdropInteractively() {
        guard let currentPageIndex else { return }
        if axis == .horizontal, translation.x != 0 {
            let direction = translation.x < 0 ? 1 : -1
            let destination = currentPageIndex + direction
            guard (0...assets.count).contains(destination) else {
                session.cancelTransition()
                backdropTargetID = nil
                return
            }
            let targetID = pageID(at: destination)
            setCompletionControlsHidden(targetID == CleaningPageID.groupCompletion)
            ensureBackdropTransition(targetID: targetID)
            session.setTransitionProgress(min(abs(translation.x) / max(pageWidth, 1), 1))
        } else if axis == .vertical, deletionProgress > 0,
                  let currentIndex,
                  let target = CleaningMotionGeometry.deletionTarget(
                    currentIndex: currentIndex,
                    assetCount: assets.count
                  ) {
            let targetID = pageID(at: target.pageIndex)
            setCompletionControlsHidden(targetID == CleaningPageID.groupCompletion)
            ensureBackdropTransition(targetID: targetID)
            session.setTransitionProgress(deletionProgress)
        } else {
            session.cancelTransition()
            backdropTargetID = nil
            setCompletionControlsHidden(selectedAssetID == CleaningPageID.groupCompletion)
        }
    }

    private func ensureBackdropTransition(targetID: String) {
        guard backdropTargetID != targetID else { return }
        backdropTargetID = targetID
        session.beginTransition(sourceID: selectedAssetID, targetID: targetID)
    }

    private func animate(
        duration: TimeInterval,
        dampingRatio: CGFloat,
        animations: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        animator?.stopAnimation(true)
        let animator = UIViewPropertyAnimator(
            duration: UIAccessibility.isReduceMotionEnabled ? min(duration, 0.18) : duration,
            dampingRatio: dampingRatio,
            animations: animations
        )
        animator.addCompletion { position in
            guard position == .end else { return }
            completion()
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func animate(
        duration: TimeInterval,
        curve: UIView.AnimationCurve,
        animations: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        animator?.stopAnimation(true)
        let animator = UIViewPropertyAnimator(
            duration: UIAccessibility.isReduceMotionEnabled ? min(duration, 0.18) : duration,
            curve: curve,
            animations: animations
        )
        animator.addCompletion { position in
            guard position == .end else { return }
            completion()
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func finishTransitionForNewGestureIfNeeded() {
        guard isTransitioning, let animator, animator.state == .active else { return }
        animator.stopAnimation(false)
        animator.finishAnimation(at: .end)
    }

    private var currentPageIndex: Int? {
        if selectedAssetID == CleaningPageID.groupCompletion { return assets.count }
        return currentIndex
    }

    private var currentIndex: Int? {
        assetIndexByID[selectedAssetID]
    }

    private var pageWidth: CGFloat {
        view.bounds.width + pageSpacing
    }

    private func positionPageAtRest(_ page: UIView) {
        page.bounds = CGRect(origin: .zero, size: view.bounds.size)
        page.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }

    private func rebuildAssetIndex() {
        assetIndexByID = Dictionary(
            uniqueKeysWithValues: assets.enumerated().map { ($0.element.localIdentifier, $0.offset) }
        )
    }

    private func pageID(at index: Int) -> String {
        assets.indices.contains(index) ? assets[index].localIdentifier : CleaningPageID.groupCompletion
    }

    private func pageIndex(for identifier: String) -> Int? {
        identifier == CleaningPageID.groupCompletion ? assets.count : assetIndexByID[identifier]
    }

    private func resistedVerticalOffset(_ value: CGFloat) -> CGFloat {
        CleaningMotionGeometry.resistedVerticalOffset(value, threshold: actionThreshold)
    }

    private func settlingDuration(
        distance: CGFloat,
        velocity: CGFloat,
        baselineVelocity: CGFloat,
        range: ClosedRange<TimeInterval>
    ) -> TimeInterval {
        let resolvedVelocity = max(abs(velocity), baselineVelocity)
        let duration = TimeInterval(distance / resolvedVelocity)
        return min(max(duration, range.lowerBound), range.upperBound)
    }

    private func prepareHaptics() {
        guard hapticsEnabled else { return }
        deletionHaptic.prepare()
        favoriteHaptic.prepare()
        boundaryHaptic.prepare()
    }

    private func updateThresholdHaptic(with translation: CGPoint) {
        guard axis == .vertical else { return }
        let crossed = abs(translation.y) >= actionThreshold
        if crossed, !thresholdCrossed {
            thresholdCrossed = true
            let direction: CGFloat = translation.y < 0 ? -1 : 1
            guard hapticsEnabled, deliveredHapticDirection != direction else { return }
            if translation.y < 0 {
                deletionHaptic.impactOccurred()
            } else {
                favoriteHaptic.impactOccurred()
            }
            deliveredHapticDirection = direction
        } else if !crossed {
            thresholdCrossed = false
        }
    }

    private func deliverActionHapticIfNeeded(deleting: Bool) {
        let direction: CGFloat = deleting ? -1 : 1
        guard hapticsEnabled, deliveredHapticDirection != direction else { return }
        if deleting {
            deletionHaptic.impactOccurred()
        } else {
            favoriteHaptic.impactOccurred()
        }
        deliveredHapticDirection = direction
    }

    private func playBoundaryHaptic() {
        guard hapticsEnabled else { return }
        boundaryHaptic.impactOccurred(intensity: 0.55)
    }
}
