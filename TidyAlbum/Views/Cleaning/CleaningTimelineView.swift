import Photos
import SwiftUI
import UIKit

enum CleaningTimelineLayout {
    static let columnCount = 3
    static let spacing: CGFloat = 6
    static let horizontalInset: CGFloat = 12

    static func itemSide(containerWidth: CGFloat) -> CGFloat {
        (
            containerWidth
                - 2 * horizontalInset
                - CGFloat(columnCount - 1) * spacing
        ) / CGFloat(columnCount)
    }

    static func targetColumn(in assets: [PHAsset], selectedAssetID: String) -> Int {
        targetColumns(in: assets)[selectedAssetID] ?? 1
    }

    static func targetColumns(in assets: [PHAsset]) -> [String: Int] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: assets) { asset in
            asset.creationDate.map {
                calendar.dateComponents([.year, .month], from: $0)
            } ?? DateComponents()
        }
        var result: [String: Int] = [:]
        result.reserveCapacity(assets.count)
        for sectionAssets in grouped.values {
            for (index, asset) in sectionAssets.sorted(by: {
                ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
            }).enumerated() {
                result[asset.localIdentifier] = index % columnCount
            }
        }
        return result
    }
}

/// Shared by the UIKit card stage and the timeline controller. It keeps the
/// pinch transition on the main run loop instead of publishing a SwiftUI
/// state update for every finger movement.
@MainActor
final class CleaningTimelineSession {
    weak var controller: CleaningTimelineViewController?
    private var progress: CGFloat = 0

    func attach(_ controller: CleaningTimelineViewController) {
        self.controller = controller
        controller.setTransitionProgress(progress)
    }

    func detach(_ controller: CleaningTimelineViewController) {
        if self.controller === controller { self.controller = nil }
    }

    func setProgress(_ progress: CGFloat) {
        let clamped = min(max(progress, 0), 1)
        guard abs(self.progress - clamped) > 0.0005 else { return }
        self.progress = clamped
        controller?.setTransitionProgress(self.progress)
    }

    func setVisible(_ visible: Bool) {
        setProgress(visible ? 1 : 0)
    }

    func targetFrame(in view: UIView) -> CGRect? {
        controller?.selectedAssetFrame(in: view)
    }
}

struct CleaningTimelineView: UIViewControllerRepresentable {
    let session: CleaningTimelineSession
    let assets: [PHAsset]
    let selectedAssetID: String
    @ObservedObject var settings: SettingsStore
    let onSelect: (PHAsset) -> Void

    func makeUIViewController(context: Context) -> CleaningTimelineViewController {
        let controller = CleaningTimelineViewController()
        session.attach(controller)
        controller.configure(
            assets: assets,
            selectedAssetID: selectedAssetID,
            settings: settings,
            onSelect: onSelect
        )
        return controller
    }

    func updateUIViewController(
        _ controller: CleaningTimelineViewController,
        context: Context
    ) {
        session.attach(controller)
        controller.configure(
            assets: assets,
            selectedAssetID: selectedAssetID,
            settings: settings,
            onSelect: onSelect
        )
    }

    static func dismantleUIViewController(
        _ controller: CleaningTimelineViewController,
        coordinator: ()
    ) {
        controller.tearDown()
    }
}

@MainActor
final class CleaningTimelineViewController: UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout
{
    private struct Section {
        let id: String
        let date: Date?
        let title: String
        let assets: [PHAsset]
    }

    private final class Cell: UICollectionViewCell {
        static let reuseIdentifier = "timeline-photo"
        let imageView = UIImageView()
        let selectionView = UIView()
        let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        var requestID: PHImageRequestID?
        var representedID = ""

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.clipsToBounds = true
            contentView.layer.cornerRadius = 12
            contentView.layer.cornerCurve = .continuous
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.backgroundColor = .secondarySystemBackground
            contentView.addSubview(imageView)

            selectionView.isUserInteractionEnabled = false
            selectionView.backgroundColor = .clear
            selectionView.layer.borderColor = UIColor.white.cgColor
            selectionView.layer.borderWidth = 2.5
            selectionView.layer.cornerRadius = 10
            contentView.addSubview(selectionView)

            checkmark.tintColor = .systemBlue
            checkmark.backgroundColor = .white
            checkmark.layer.cornerRadius = 9
            checkmark.clipsToBounds = true
            contentView.addSubview(checkmark)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            imageView.frame = contentView.bounds
            selectionView.frame = contentView.bounds.insetBy(dx: 1, dy: 1)
            checkmark.frame = CGRect(x: bounds.maxX - 24, y: 5, width: 18, height: 18)
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            if let requestID { AssetImagePipeline.shared.cancel(requestID) }
            requestID = nil
            representedID = ""
            imageView.image = nil
            selectionView.isHidden = true
            checkmark.isHidden = true
        }

        func configure(asset: PHAsset, selected: Bool) {
            if representedID != asset.localIdentifier {
                if let requestID { AssetImagePipeline.shared.cancel(requestID) }
                requestID = nil
                representedID = asset.localIdentifier
                imageView.image = nil
                let targetSize = CGSize(width: 360, height: 360)
                if let cached = AssetImagePipeline.shared.cachedImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFill
                ) {
                    imageView.image = cached
                } else {
                    let requestedID = asset.localIdentifier
                    requestID = AssetImagePipeline.shared.requestImage(
                        for: asset,
                        targetSize: targetSize,
                        contentMode: .aspectFill
                    ) { [weak self] image, isFinal in
                        guard let self,
                              self.representedID == requestedID else { return }
                        self.imageView.image = image
                        if isFinal { self.requestID = nil }
                    }
                }
            }
            selectionView.isHidden = !selected
            checkmark.isHidden = !selected
        }
    }

    private let collectionView: UICollectionView
    private var assets: [PHAsset] = []
    private var sections: [Section] = []
    private var selectedAssetID = ""
    private var settings: SettingsStore?
    private var onSelect: ((PHAsset) -> Void)?
    private var didInitialScroll = false
    private var transitionProgress: CGFloat = 0
    private var alignmentRequestID = 0
    private var contentInsetBoundsSize = CGSize.zero

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = CleaningTimelineLayout.spacing
        layout.minimumLineSpacing = CleaningTimelineLayout.spacing
        layout.sectionInset = UIEdgeInsets(top: 4, left: 12, bottom: 24, right: 12)
        layout.headerReferenceSize = CGSize(width: 0, height: 48)
        layout.sectionHeadersPinToVisibleBounds = false
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        view.alpha = 0
        collectionView.backgroundColor = .secondarySystemBackground
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(Cell.self, forCellWithReuseIdentifier: Cell.reuseIdentifier)
        collectionView.register(
            TimelineHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: TimelineHeader.reuseIdentifier
        )
        view.addSubview(collectionView)
        collectionView.accessibilityIdentifier = "tidyalbum.cleaning-timeline"
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.frame = view.bounds
        if contentInsetBoundsSize != view.bounds.size {
            contentInsetBoundsSize = view.bounds.size
            let insets = UIEdgeInsets(
                top: max(view.safeAreaInsets.top + 56, 96),
                left: 0,
                bottom: max(view.safeAreaInsets.bottom + 12, 24),
                right: 0
            )
            collectionView.contentInset = insets
            collectionView.scrollIndicatorInsets = insets
            didInitialScroll = false
        }
        if !didInitialScroll { scrollToSelection(animated: false) }
    }

    func configure(
        assets: [PHAsset],
        selectedAssetID: String,
        settings: SettingsStore,
        onSelect: @escaping (PHAsset) -> Void
    ) {
        let idsChanged = self.assets.count != assets.count
            || self.assets.first?.localIdentifier != assets.first?.localIdentifier
            || self.assets.last?.localIdentifier != assets.last?.localIdentifier
        let selectionChanged = self.selectedAssetID != selectedAssetID
        self.assets = assets
        self.selectedAssetID = selectedAssetID
        self.settings = settings
        self.onSelect = onSelect
        if idsChanged {
            sections = makeSections(assets)
            collectionView.reloadData()
            didInitialScroll = false
            alignmentRequestID += 1
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        if selectionChanged || idsChanged { scrollToSelection(animated: false) }
    }

    func setTransitionProgress(_ progress: CGFloat) {
        transitionProgress = min(max(progress, 0), 1)
        // Align before revealing the first frame of the pinch transition. A
        // regular scrollToItem call can run before contentSize is final and
        // leave the selected month one or more rows away from the card.
        if transitionProgress > 0.001, !didInitialScroll {
            scrollToSelection(animated: false)
        }
        view.alpha = transitionProgress
        view.accessibilityElementsHidden = transitionProgress <= 0.001
        collectionView.accessibilityIdentifier = transitionProgress > 0.001
            ? "tidyalbum.cleaning-timeline"
            : nil
    }

    func tearDown() {
        collectionView.visibleCells.compactMap { $0 as? Cell }.forEach { cell in
            if let requestID = cell.requestID { AssetImagePipeline.shared.cancel(requestID) }
        }
    }

    private func makeSections(_ assets: [PHAsset]) -> [Section] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: assets) { asset -> DateComponents in
            guard let date = asset.creationDate else { return DateComponents() }
            return calendar.dateComponents([.year, .month], from: date)
        }
        return grouped.map { components, groupedAssets in
            let date = calendar.date(from: components)
            return Section(
                id: "\(components.year ?? 0)-\(components.month ?? 0)",
                date: date,
                title: sectionTitle(for: date),
                assets: groupedAssets.sorted {
                    ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
                }
            )
        }.sorted { lhs, rhs in
            (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast)
        }
    }

    private func sectionTitle(for date: Date?) -> String {
        guard let date else { return settings?.t("Unknown Date") ?? "Unknown Date" }
        let formatter = DateFormatter()
        formatter.locale = settings?.language.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: date)
    }

    private func scrollToSelection(animated: Bool) {
        guard collectionView.bounds.width > 0,
              let indexPath = selectedIndexPath else { return }
        collectionView.layoutIfNeeded()
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
            let requestID = alignmentRequestID
            DispatchQueue.main.async { [weak self] in
                guard let self, self.alignmentRequestID == requestID else { return }
                self.scrollToSelection(animated: animated)
            }
            return
        }
        let insets = collectionView.adjustedContentInset
        let visibleHeight = max(collectionView.bounds.height - insets.top - insets.bottom, 1)
        let desiredY = attributes.center.y - insets.top - visibleHeight * 0.5
        let minimumY = -insets.top
        let maximumY = max(
            minimumY,
            collectionView.contentSize.height - collectionView.bounds.height + insets.bottom
        )
        let targetOffset = CGPoint(
            x: collectionView.contentOffset.x,
            y: min(max(desiredY, minimumY), maximumY)
        )
        if animated {
            collectionView.setContentOffset(targetOffset, animated: true)
        } else {
            UIView.performWithoutAnimation {
                collectionView.setContentOffset(targetOffset, animated: false)
            }
        }
        didInitialScroll = true
    }

    func selectedAssetFrame(in coordinateView: UIView) -> CGRect? {
        if !didInitialScroll { scrollToSelection(animated: false) }
        collectionView.layoutIfNeeded()
        guard let indexPath = selectedIndexPath,
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
        return collectionView.convert(attributes.frame, to: coordinateView)
    }

    private var selectedIndexPath: IndexPath? {
        guard !sections.isEmpty,
              let sectionIndex = sections.firstIndex(where: {
                  $0.assets.contains { $0.localIdentifier == selectedAssetID }
              }),
              let itemIndex = sections[sectionIndex].assets.firstIndex(where: {
                  $0.localIdentifier == selectedAssetID
              }) else { return nil }
        return IndexPath(item: itemIndex, section: sectionIndex)
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int { sections[section].assets.count }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: Cell.reuseIdentifier,
            for: indexPath
        ) as! Cell
        let asset = sections[indexPath.section].assets[indexPath.item]
        cell.configure(asset: asset, selected: asset.localIdentifier == selectedAssetID)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        onSelect?(sections[indexPath.section].assets[indexPath.item])
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = CleaningTimelineLayout.itemSide(containerWidth: collectionView.bounds.width)
        return CGSize(width: width, height: width)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: TimelineHeader.reuseIdentifier,
            for: indexPath
        ) as! TimelineHeader
        header.titleLabel.text = sections[indexPath.section].title
        header.countLabel.text = sections[indexPath.section].assets.count.formatted()
        return header
    }
}

@MainActor
private final class TimelineHeader: UICollectionReusableView {
    static let reuseIdentifier = "timeline-header"
    let titleLabel = UILabel()
    let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        countLabel.textColor = .secondaryLabel
        addSubview(titleLabel)
        addSubview(countLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.frame = CGRect(x: 18, y: 10, width: bounds.width - 110, height: 24)
        countLabel.sizeToFit()
        countLabel.frame.origin = CGPoint(x: bounds.width - countLabel.bounds.width - 18, y: 12)
    }
}
