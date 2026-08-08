import Photos
import UIKit

nonisolated struct SimilarityKeeperRank: Comparable {
    let isFavorite: Bool
    let pixelCount: Int64
    let isLivePhoto: Bool
    let creationTimestamp: TimeInterval

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.isFavorite != rhs.isFavorite { return !lhs.isFavorite }
        if lhs.pixelCount != rhs.pixelCount { return lhs.pixelCount < rhs.pixelCount }
        if lhs.isLivePhoto != rhs.isLivePhoto { return !lhs.isLivePhoto }
        return lhs.creationTimestamp < rhs.creationTimestamp
    }
}

nonisolated struct SimilarPhotoGroup: Identifiable {
    let id: String
    let assets: [PHAsset]

    nonisolated init(assets: [PHAsset]) {
        self.assets = assets.sorted {
            ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
        }
        id = self.assets.map(\.localIdentifier).sorted().joined(separator: "|")
    }

    var recommendedKeeper: PHAsset? {
        assets.max(by: Self.isLowerKeeperPriority)
    }

    var suggestedDeletionAssets: [PHAsset] {
        let keeperID = recommendedKeeper?.localIdentifier
        return assets.filter { asset in
            asset.localIdentifier != keeperID && !asset.isFavorite
        }
    }

    private static func isLowerKeeperPriority(_ lhs: PHAsset, _ rhs: PHAsset) -> Bool {
        rank(for: lhs) < rank(for: rhs)
    }

    private static func rank(for asset: PHAsset) -> SimilarityKeeperRank {
        SimilarityKeeperRank(
            isFavorite: asset.isFavorite,
            pixelCount: Int64(asset.pixelWidth) * Int64(asset.pixelHeight),
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            creationTimestamp: asset.creationDate?.timeIntervalSinceReferenceDate
                ?? Date.distantPast.timeIntervalSinceReferenceDate
        )
    }
}

/// A small, on-device visual fingerprint scanner used for the Similar Photos
/// collection. It never exports image data and only keeps compact fingerprints.
actor LocalSimilarityService {
    static let shared = LocalSimilarityService()

    private struct Fingerprint: Codable {
        let hash: UInt64
        let red: Float
        let green: Float
        let blue: Float
        let aspectRatio: Float
        let pixelWidth: Int
        let pixelHeight: Int
        let modificationTimestamp: TimeInterval

        var averageColor: SIMD3<Float> { SIMD3(red, green, blue) }

        func matches(_ asset: PHAsset) -> Bool {
            pixelWidth == asset.pixelWidth
                && pixelHeight == asset.pixelHeight
                && abs(
                    modificationTimestamp
                        - (asset.modificationDate?.timeIntervalSinceReferenceDate ?? 0)
                ) < 0.5
        }
    }

    private struct CachePayload: Codable {
        let version: Int
        let fingerprints: [String: Fingerprint]
    }

    private struct BucketKey: Hashable {
        let segment: Int
        let value: UInt16
    }

    private var fingerprintCache: [String: Fingerprint] = [:]
    private var didLoadPersistentCache = false
    private let cacheVersion = 1

    private init() {}

    func similarAssets(
        in assets: [PHAsset],
        progress: @escaping @MainActor (Double) -> Void
    ) async -> [PHAsset] {
        await similarGroups(in: assets, progress: progress).flatMap(\.assets)
    }

    func similarGroups(
        in assets: [PHAsset],
        progress: @escaping @MainActor (Double) -> Void
    ) async -> [SimilarPhotoGroup] {
        guard assets.count > 1 else { return [] }
        loadPersistentCacheIfNeeded()
        var values = [Fingerprint?](repeating: nil, count: assets.count)
        for index in assets.indices {
            let asset = assets[index]
            if let cached = fingerprintCache[asset.localIdentifier], cached.matches(asset) {
                values[index] = cached
            }
        }
        // The scanner is only active on its dedicated tab. Use a bounded
        // burst of fast thumbnails so a large library finishes in seconds,
        // while the cleaning session can cancel the whole task before it
        // starts its own high-resolution requests.
        let batchSize = 24
        for lowerBound in stride(from: 0, to: assets.count, by: batchSize) {
            guard !Task.isCancelled else { return [] }
            let upperBound = min(lowerBound + batchSize, assets.count)
            let loaded = await withTaskGroup(of: (Int, Fingerprint?).self) { group in
                for index in lowerBound..<upperBound where values[index] == nil {
                    let asset = assets[index]
                    group.addTask {
                        (index, await Self.fingerprint(for: asset))
                    }
                }
                var loaded: [(Int, Fingerprint?)] = []
                for await result in group { loaded.append(result) }
                return loaded
            }
            for (index, value) in loaded {
                values[index] = value
                if let value {
                    fingerprintCache[assets[index].localIdentifier] = value
                }
            }
            if upperBound == assets.count || upperBound.isMultiple(of: 128) {
                await progress(Double(upperBound) / Double(assets.count))
            }
            await Task.yield()
        }

        let activeIdentifiers = Set(assets.map(\.localIdentifier))
        fingerprintCache = fingerprintCache.filter { activeIdentifiers.contains($0.key) }
        persistCache()

        let fingerprints = assets.indices.compactMap { index in
            values[index].map { (asset: assets[index], value: $0) }
        }

        guard fingerprints.count > 1 else { return [] }
        var parent = Array(0..<fingerprints.count)
        var buckets: [BucketKey: [Int]] = [:]

        func root(_ value: Int) -> Int {
            var value = value
            while parent[value] != value {
                parent[value] = parent[parent[value]]
                value = parent[value]
            }
            return value
        }

        func union(_ lhs: Int, _ rhs: Int) {
            let left = root(lhs)
            let right = root(rhs)
            if left != right { parent[right] = left }
        }

        for index in fingerprints.indices {
            let value = fingerprints[index].value
            let parts = [
                UInt16(truncatingIfNeeded: value.hash),
                UInt16(truncatingIfNeeded: value.hash >> 16),
                UInt16(truncatingIfNeeded: value.hash >> 32),
                UInt16(truncatingIfNeeded: value.hash >> 48)
            ]
            var candidates = Set<Int>()
            for (segment, part) in parts.enumerated() {
                candidates.formUnion(buckets[BucketKey(segment: segment, value: part)] ?? [])
            }
            for candidate in candidates {
                let other = fingerprints[candidate].value
                guard abs(value.aspectRatio - other.aspectRatio) < 0.12 else { continue }
                guard colorDistance(value.averageColor, other.averageColor) < 0.34 else { continue }
                guard (value.hash ^ other.hash).nonzeroBitCount <= 11 else { continue }
                union(index, candidate)
            }
            for (segment, part) in parts.enumerated() {
                let key = BucketKey(segment: segment, value: part)
                buckets[key, default: []].append(index)
                if buckets[key, default: []].count > 96 {
                    buckets[key]?.removeFirst()
                }
            }
        }

        var groups: [Int: [PHAsset]] = [:]
        for index in fingerprints.indices {
            groups[root(index), default: []].append(fingerprints[index].asset)
        }
        return groups.values
            .filter { $0.count > 1 }
            .map(SimilarPhotoGroup.init)
            .sorted {
                ($0.assets.first?.creationDate ?? .distantPast)
                    > ($1.assets.first?.creationDate ?? .distantPast)
            }
    }

    private nonisolated static func fingerprint(for asset: PHAsset) async -> Fingerprint? {
        await Task.detached(priority: .userInitiated) {
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            options.isSynchronous = true
            var image: UIImage?
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 32, height: 28),
                contentMode: .aspectFit,
                options: options
            ) { candidate, _ in image = candidate }
            guard let image, let cgImage = image.cgImage else { return nil }

            let width = 9
            let height = 8
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            var hash: UInt64 = 0
            var red: Float = 0
            var green: Float = 0
            var blue: Float = 0
            for row in 0..<height {
                for column in 0..<width {
                    let offset = (row * width + column) * 4
                    let r = Float(pixels[offset]) / 255
                    let g = Float(pixels[offset + 1]) / 255
                    let b = Float(pixels[offset + 2]) / 255
                    red += r
                    green += g
                    blue += b
                    if column < width - 1 {
                        let nextOffset = offset + 4
                        let currentLuma = 0.299 * r + 0.587 * g + 0.114 * b
                        let nextLuma = 0.299 * (Float(pixels[nextOffset]) / 255)
                            + 0.587 * (Float(pixels[nextOffset + 1]) / 255)
                            + 0.114 * (Float(pixels[nextOffset + 2]) / 255)
                        hash = (hash << 1) | (currentLuma > nextLuma ? 1 : 0)
                    }
                }
            }
            let count = Float(width * height)
            let ratio = Float(asset.pixelWidth) / Float(max(asset.pixelHeight, 1))
            return Fingerprint(
                hash: hash,
                red: red / count,
                green: green / count,
                blue: blue / count,
                aspectRatio: ratio,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                modificationTimestamp: asset.modificationDate?.timeIntervalSinceReferenceDate ?? 0
            )
        }.value
    }

    private func loadPersistentCacheIfNeeded() {
        guard !didLoadPersistentCache else { return }
        didLoadPersistentCache = true
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data),
              payload.version == cacheVersion else { return }
        fingerprintCache = payload.fingerprints
    }

    private func persistCache() {
        guard let url = cacheURL,
              let data = try? JSONEncoder().encode(
                  CachePayload(version: cacheVersion, fingerprints: fingerprintCache)
              ) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Similarity", isDirectory: true)
            .appendingPathComponent("fingerprints-v1.json", isDirectory: false)
    }

    private func colorDistance(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float {
        simd_distance(lhs, rhs)
    }
}
