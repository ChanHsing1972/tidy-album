import Photos
import SwiftUI
import UIKit

enum CleaningPageID {
    static let groupCompletion = "tidyalbum.group-completion"
}

struct CleaningSelectionAnimationRequest: Equatable {
    let token: UUID
    let assetIdentifier: String
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
    private var translation = CGPoint.zero
    private var deletionProgress: CGFloat = 0
    private var isDeleting = false
    private var isTransitioning = false
    private var thresholdCrossed = false
    private var deliveredHapticDirection: CGFloat?
    private var committedActionDirection: CGFloat?
    private var undoAnimationTargetID: String?
    private var undoAnimationProgress: CGFloat = 0
    private var backdropTargetID: String?
    private var animator: UIViewPropertyAnimator?
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
        onNextGroup: @escaping () -> Void,
        onEnd: @escaping () -> Void
    ) {
        self.onSelection = onSelection
        self.onDelete = onDelete
        self.onToggleFavorite = onToggleFavorite
        self.onAddToAlbum = onAddToAlbum
        self.onNextGroup = onNextGroup
        self.onEnd = onEnd
        self.hapticsEnabled = hapticsEnabled
        self.autoPlayLivePhotos = autoPlayLivePhotos
        self.downwardSwipeAction = downwardSwipeAction
        self.favoriteIdentifiers = favoriteIdentifiers
        self.completionContent = completionContent

        let assetsChanged = self.assets.map(\.localIdentifier) != assets.map(\.localIdentifier)
        let previousSelectionID = self.selectedAssetID
        let selectionChanged = previousSelectionID != selectedAssetID
        let requestedAnimation = selectionAnimationRequest.flatMap { request in
            request.token != lastSelectionAnimationToken
                && request.assetIdentifier == selectedAssetID ? request : nil
        }
        self.assets = assets
        assetIndexByID = Dictionary(
            uniqueKeysWithValues: assets.enumerated().map { ($0.element.localIdentifier, $0.offset) }
        )
        if selectionChanged {
            if let requestedAnimation,
               !isTransitioning,
               !previousSelectionID.isEmpty,
               pageIndex(for: previousSelectionID) != nil,
               pageIndex(for: selectedAssetID) != nil,
               view.window != nil {
                reconcilePages()
                lastSelectionAnimationToken = requestedAnimation.token
                animateDeletionUndo(to: selectedAssetID)
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
        }
        if assetsChanged || selectionChanged {
            reconcilePages()
        } else {
            updatePageContent()
        }
        view.setNeedsLayout()
    }

    func tearDown() {
        animator?.stopAnimation(true)
        animator = nil
        session.cancelTransition()
        cardViews.values.forEach { $0.tearDown() }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        finishTransitionForNewGestureIfNeeded()
        return !isTransitioning && currentPageIndex != nil
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard !isTransitioning else { return }
            deliveredHapticDirection = nil
            committedActionDirection = nil
            prepareHaptics()
        case .changed:
            guard !isTransitioning else { return }
            let value = recognizer.translation(in: view)
            if axis == .undetermined {
                let horizontal = abs(value.x)
                let vertical = abs(value.y)
                guard max(horizontal, vertical) > 10 else { return }
                axis = vertical > horizontal * 1.15 ? .vertical : .horizontal
            }
            applyInteractiveTranslation(value)
            updateThresholdHaptic(with: value)
        case .ended:
            guard !isTransitioning else { return }
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
        translation = axis == .horizontal
            ? CGPoint(x: value.x, y: 0)
            : CGPoint(x: 0, y: value.y)
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
        let projected = translation.y + velocity * 0.2
        let resolved = projected == 0 ? translation.y : projected
        let shouldCommit = abs(translation.y) >= actionThreshold
            || abs(projected) >= actionThreshold * 1.35
        guard shouldCommit else {
            resetGesture(animated: true)
            return
        }
        if resolved < 0 {
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
        reconcilePages()
        onSelection?(identifier)
    }

    private func animateExternalSelection(to identifier: String, direction: Int) {
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

    private func animateDeletionUndo(to identifier: String) {
        guard prepareUndoPage(for: identifier) else {
            selectedAssetID = identifier
            resetMotion()
            isTransitioning = false
            session.commitSelection(identifier)
            reconcilePages()
            return
        }
        resetMotion()
        undoAnimationTargetID = identifier
        undoAnimationProgress = 0
        ensureBackdropTransition(targetID: identifier)
        isTransitioning = true
        applyTransformsWithoutAnimation()

        // Keep the controller in sync with the binding immediately. SwiftUI can
        // call configure again before this animator finishes; leaving the old ID
        // here causes that update to replace the undo with a normal page turn.
        selectedAssetID = identifier
        updatePageContent()
        undoAnimationProgress = 1
        animate(duration: 0.38, dampingRatio: 0.9, animations: {
            self.applyTransforms()
            self.session.setTransitionProgress(1)
        }) { [weak self] in
            guard let self else { return }
            self.resetMotion()
            self.isTransitioning = false
            self.session.commitSelection(identifier)
            self.reconcilePages()
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
            self.applyTransformsWithoutAnimation()
        }
    }

    private func resetMotion() {
        axis = .undetermined
        translation = .zero
        deletionProgress = 0
        isDeleting = false
        thresholdCrossed = false
        deliveredHapticDirection = nil
        committedActionDirection = nil
        undoAnimationTargetID = nil
        undoAnimationProgress = 0
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
                let entryY = -max(view.bounds.height * 1.18, 760) * (1 - undoAnimationProgress)
                let scale = 0.982 + 0.018 * undoAnimationProgress
                page.layer.setAffineTransform(
                    CGAffineTransform(translationX: 0, y: entryY)
                        .scaledBy(x: scale, y: scale)
                )
                page.layer.zPosition = 20
                page.alpha = 0.84 + 0.16 * undoAnimationProgress
            } else {
                page.layer.setAffineTransform(
                    CGAffineTransform(
                        translationX: motion.translation.x,
                        y: motion.translation.y
                    ).scaledBy(x: motion.scale, y: motion.scale)
                )
                page.layer.zPosition = motion.zPosition
                page.alpha = 1
            }
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
            ensureBackdropTransition(targetID: targetID)
            session.setTransitionProgress(min(abs(translation.x) / max(pageWidth, 1), 1))
        } else if axis == .vertical, deletionProgress > 0,
                  let currentIndex,
                  let target = CleaningMotionGeometry.deletionTarget(
                    currentIndex: currentIndex,
                    assetCount: assets.count
                  ) {
            let targetID = pageID(at: target.pageIndex)
            ensureBackdropTransition(targetID: targetID)
            session.setTransitionProgress(deletionProgress)
        } else {
            session.cancelTransition()
            backdropTargetID = nil
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
