import CoreImage
import UIKit

actor CleaningBackdropRenderer {
    static let shared = CleaningBackdropRenderer()

    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: true
    ])
    private let cache = NSCache<NSString, CGImage>()

    private init() {
        cache.totalCostLimit = 32 * 1_024 * 1_024
    }

    func renderedImage(
        from source: CIImage,
        assetIdentifier: String,
        canvasSize: CGSize
    ) -> CGImage? {
        let width = max(Int(canvasSize.width.rounded(.up)), 1)
        let height = max(Int(canvasSize.height.rounded(.up)), 1)
        let key = "\(assetIdentifier)-\(width)x\(height)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let sourceExtent = source.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0 else { return nil }
        let targetRect = CGRect(
            x: 0,
            y: 0,
            width: sourceExtent.width.rounded(.up),
            height: sourceExtent.height.rounded(.up)
        )
        let normalized = source.transformed(
            by: CGAffineTransform(translationX: -sourceExtent.minX, y: -sourceExtent.minY)
        )
        let displayScale = max(
            CGFloat(width) / sourceExtent.width,
            CGFloat(height) / sourceExtent.height
        ) * 1.18
        let sourceBlurRadius = 54 / max(displayScale, 0.001)
        let blurred = normalized
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: sourceBlurRadius])
        guard let output = context.createCGImage(blurred, from: targetRect) else { return nil }
        cache.setObject(
            output,
            forKey: key,
            cost: Int(targetRect.width * targetRect.height) * 4
        )
        return output
    }
}
