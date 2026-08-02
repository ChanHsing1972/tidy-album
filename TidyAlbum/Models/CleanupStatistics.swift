import Combine
import Foundation
import Photos
import UniformTypeIdentifiers

// MARK: - Statistics Models

enum CleanupMediaKind: String, Codable, CaseIterable, Identifiable {
    case photo
    case video

    var id: String { rawValue }
}

enum CleanupCategory: String, Codable, CaseIterable, Identifiable {
    case screenshot
    case livePhoto
    case panorama
    case portrait
    case rawPhoto
    case largeVideo
    case video
    case photo
    case other

    var id: String { rawValue }

    nonisolated static func classify(
        mediaType: PHAssetMediaType,
        mediaSubtypes: PHAssetMediaSubtype,
        bytes: Int64,
        resourceFilenames: [String]
    ) -> CleanupCategory {
        if mediaSubtypes.contains(.photoScreenshot) {
            return .screenshot
        }
        if mediaType == .video {
            return bytes >= 100_000_000 ? .largeVideo : .video
        }
        if mediaSubtypes.contains(.photoLive) {
            return .livePhoto
        }
        if mediaSubtypes.contains(.photoPanorama) {
            return .panorama
        }
        if mediaSubtypes.contains(.photoDepthEffect) {
            return .portrait
        }
        if resourceFilenames.contains(where: isRawImageFilename) {
            return .rawPhoto
        }
        return mediaType == .image ? .photo : .other
    }

    nonisolated private static func isRawImageFilename(_ filename: String) -> Bool {
        let fileExtension = URL(fileURLWithPath: filename).pathExtension
        guard !fileExtension.isEmpty,
              let type = UTType(filenameExtension: fileExtension) else {
            return false
        }
        return type.conforms(to: .rawImage)
    }
}

struct CleanupEvent: Codable, Identifiable {
    let id: UUID
    let date: Date
    let mediaKind: CleanupMediaKind
    let category: CleanupCategory
    let bytes: Int64
}

struct CleanupStatistics: Codable {
    var reviewedCount = 0
    var events: [CleanupEvent] = []

    var cleanedCount: Int { events.count }
    var reclaimedBytes: Int64 { events.reduce(0) { $0 + $1.bytes } }

    func bytes(for kind: CleanupMediaKind) -> Int64 {
        events.filter { $0.mediaKind == kind }.reduce(0) { $0 + $1.bytes }
    }

    func count(for category: CleanupCategory) -> Int {
        events.filter { $0.category == category }.count
    }

    var mostProductiveHour: Int? {
        Dictionary(grouping: events) { Calendar.current.component(.hour, from: $0.date) }
            .max { $0.value.count < $1.value.count }?.key
    }
}

struct CleaningSessionSummary: Equatable {
    var reviewedCount = 0
    var markedForDeletionCount = 0
    var estimatedReclaimBytes: Int64 = 0
}

// MARK: - Statistics Store

@MainActor
final class AnalyticsStore: ObservableObject {
    @Published private(set) var statistics: CleanupStatistics
    private let defaults: UserDefaults
    private let storageKey = "analytics.cleanupStatistics.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(CleanupStatistics.self, from: data) {
            statistics = decoded
        } else {
            statistics = CleanupStatistics()
        }
    }

    func recordReview() {
        statistics.reviewedCount += 1
        persist()
    }

    func recordDeletion(asset: PHAsset, bytes: Int64) {
        let mediaKind: CleanupMediaKind = asset.mediaType == .video ? .video : .photo
        let category = CleanupCategory.classify(
            mediaType: asset.mediaType,
            mediaSubtypes: asset.mediaSubtypes,
            bytes: bytes,
            resourceFilenames: PHAssetResource.assetResources(for: asset).map(\.originalFilename)
        )
        statistics.events.append(
            CleanupEvent(id: UUID(), date: .now, mediaKind: mediaKind, category: category, bytes: max(bytes, 0))
        )
        persist()
    }

    func reset() {
        statistics = CleanupStatistics()
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(statistics) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
