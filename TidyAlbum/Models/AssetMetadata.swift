import CoreLocation
import Foundation

// MARK: - Asset Metadata

struct AssetMetadata {
    let fileName: String
    let fileSize: Int64
    let uniformType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let deviceModel: String?
    let lensModel: String?
    let aperture: Double?
    let exposureTime: Double?
    let iso: Int?
    let focalLength: Double?
    let location: CLLocation?
}
