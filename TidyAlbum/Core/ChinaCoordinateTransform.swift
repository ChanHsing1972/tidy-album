import CoreLocation
import Foundation

enum ChinaCoordinateTransform {
    private static let semiMajorAxis = 6_378_245.0
    private static let eccentricitySquared = 0.006693421622965943

    static func gcj02Location(fromWGS84 location: CLLocation) -> CLLocation {
        let coordinate = gcj02Coordinate(fromWGS84: location.coordinate)
        guard coordinate.latitude != location.coordinate.latitude
                || coordinate.longitude != location.coordinate.longitude else {
            return location
        }
        return CLLocation(
            coordinate: coordinate,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            timestamp: location.timestamp
        )
    }

    static func gcj02Coordinate(
        fromWGS84 coordinate: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        guard CLLocationCoordinate2DIsValid(coordinate), isInMainlandChina(coordinate) else {
            return coordinate
        }
        let latitudeOffset = coordinate.latitude - 35
        let longitudeOffset = coordinate.longitude - 105
        var latitudeDelta = transformLatitude(x: longitudeOffset, y: latitudeOffset)
        var longitudeDelta = transformLongitude(x: longitudeOffset, y: latitudeOffset)
        let radians = coordinate.latitude / 180 * .pi
        let sine = sin(radians)
        let magic = 1 - eccentricitySquared * sine * sine
        let rootMagic = sqrt(magic)
        latitudeDelta = latitudeDelta * 180
            / ((semiMajorAxis * (1 - eccentricitySquared)) / (magic * rootMagic) * .pi)
        longitudeDelta = longitudeDelta * 180
            / (semiMajorAxis / rootMagic * cos(radians) * .pi)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + latitudeDelta,
            longitude: coordinate.longitude + longitudeDelta
        )
    }

    private static func isInMainlandChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard (0.8293...55.8271).contains(coordinate.latitude),
              (72.004...137.8347).contains(coordinate.longitude) else { return false }
        let isHongKong = (22.1...22.37).contains(coordinate.latitude)
            && (113.8...114.5).contains(coordinate.longitude)
        let isMacau = (22.05...22.23).contains(coordinate.latitude)
            && (113.5...113.65).contains(coordinate.longitude)
        let isTaiwan = (21.7...25.5).contains(coordinate.latitude)
            && (119...122.2).contains(coordinate.longitude)
        return !isHongKong && !isMacau && !isTaiwan
    }

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var value = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y
            + 0.2 * sqrt(abs(x))
        value += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        value += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        value += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        return value
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var value = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y
            + 0.1 * sqrt(abs(x))
        value += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        value += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        value += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        return value
    }
}
