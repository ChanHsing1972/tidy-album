import Combine
import Foundation
import Photos

// MARK: - Statistics Models

enum CleanupMediaKind: String, Codable, CaseIterable, Identifiable {
    case photo
    case video

    var id: String { rawValue }
}

enum CleanupCategory: String, Codable, CaseIterable, Identifiable {
    case screenshot
    case largeVideo
    case other

    var id: String { rawValue }
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
        let category: CleanupCategory
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            category = .screenshot
        } else if asset.mediaType == .video && bytes >= 100_000_000 {
            category = .largeVideo
        } else {
            category = .other
        }
        statistics.events.append(
            CleanupEvent(id: UUID(), date: .now, mediaKind: mediaKind, category: category, bytes: max(bytes, 0))
        )
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(statistics) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
