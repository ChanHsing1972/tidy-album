import CoreLocation
import MapKit
import Photos
import SwiftUI
import UniformTypeIdentifiers

// MARK: - System-Style Asset Information

struct AssetDetailsView: View {
    let asset: PHAsset
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var metadata: AssetMetadata?
    @State private var captionText: String = ""
    @State private var placeName: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 1. 顶部 4:3 预览
                    mediaPreview
                    
                    // 2. 添加说明（Caption）
//                    captionField
                    
                    // 3. 核心参数大卡片 (包含时间、文件名、相机、参数)
                    mainInfoCard
                    
                    // 4. 地理位置卡片
                    if let location = asset.location {
                        locationCard(location)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .navigationTitle(settings.t("Media Details"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: asset.localIdentifier) {
            metadata = await AssetMetadataService.shared.load(for: asset)
        }
    }

    // MARK: - 1. 4:3 Media Preview

    private var mediaPreview: some View {
        AssetMediaView(
            asset: asset,
            contentMode: .fit,
            showsVideoBadge: true,
            allowsPlayback: true,
            isActive: true
        )
        .aspectRatio(4 / 3, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 3. Main Info Card (Apple Style)

    private var mainInfoCard: some View {
        VStack(alignment: .leading, spacing: 0)  {
            // Section 1: 日期、时间与文件名
            dateAndFileHeader
                .padding(14)
            
            Divider()
            
            // Section 2: 设备信息 & Badge
            if let deviceModel = metadata?.deviceModel ?? defaultDeviceModel {
                deviceSection(model: deviceModel)
                    .padding(14)
                Divider()
            }

            // Section 3: 镜头细节与分辨率/文件大小
            cameraAndSpecsSection
                .padding(14)

            // Section 4: 底部 5 列曝光参数条 (ISO, 焦距, 光圈, 快门)
            if hasEXIFParams {
                exifParameterBar
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // Header: 时间与文件名
    private var dateAndFileHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fullFormattedDate)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 4) {
                    Text(fileName)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // Device Model & Badges
    private func deviceSection(model: String) -> some View {
        HStack {
            Text(model)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            
            Spacer()
            
            // 右侧格式 Badges (如 HEIF, RAW 等)
            HStack(spacing: 6) {
                if let format = fileFormatExtension {
                    badgeView(text: format)
                }
                if asset.mediaSubtypes.contains(.photoLive) {
                    Image(systemName: "livephoto")
                        .font(.caption2)
                        .padding(4)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .clipShape(Circle())
                }
            }
        }
    }

    // Camera Lens & Resolution
    private var cameraAndSpecsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(lensDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(specSummaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // 底部横向 EXIF 参数栏
    private var exifParameterBar: some View {
        HStack(spacing: 0) {
            exifCell(title: "ISO", value: metadata?.iso != nil ? "\(metadata!.iso!)" : "—")
            exifCell(title: settings.t("Focal Length"), value: metadata?.focalLength != nil ? String(format: "%.0f mm", metadata!.focalLength!) : "—")
            exifCell(title: settings.t("Exposure"), value: metadata?.exposureTime != nil ? String(format: "%.1f ev", metadata!.exposureTime!) : "0 ev")
            exifCell(title: settings.t("Aperture"), value: metadata?.aperture != nil ? String(format: "ƒ%.2f", metadata!.aperture!) : "—")
            exifCell(title: settings.t("Shutter"), value: shutterSpeedText)
        }
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.5))
    }

    private func exifCell(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. Location Card

    private func locationCard(_ location: CLLocation) -> some View {
        VStack(spacing: 0) {
            // 地图预览
            Map(initialPosition: .region(MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 800,
                longitudinalMeters: 800
            ))) {
                Marker("", coordinate: location.coordinate)
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 160)
            .disabled(true)

            // 地址文本
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let placeName {
                        Text(placeName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    } else {
                        Text(coordinateText(location.coordinate))
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                Spacer()
            }
            .padding(14)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            placeName = await reverseGeocode(location)
        }
    }

    // MARK: - Helpers & Formatters

    private func badgeView(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(uiColor: .tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var hasEXIFParams: Bool {
        guard let metadata else { return false }
        return metadata.iso != nil || metadata.aperture != nil || metadata.focalLength != nil
    }

    private var defaultDeviceModel: String? {
        asset.mediaType == .image ? settings.t("No device information") : nil
    }

    private var fullFormattedDate: String {
        guard let date = asset.creationDate else { return settings.t("Unknown Date") }
        return settings.fullDate(date)
    }

    private var fileName: String {
        metadata?.fileName
            ?? PHAssetResource.assetResources(for: asset).first?.originalFilename
            ?? "IMG_0000.HEIC"
    }

    private var fileFormatExtension: String? {
        let ext = metadata.flatMap { UTType($0.uniformType)?.preferredFilenameExtension?.uppercased() }
            ?? URL(fileURLWithPath: fileName).pathExtension.uppercased()
        return ext.isEmpty ? nil : ext
    }

    private var megaPixelsText: String {
        let mp = Double(asset.pixelWidth * asset.pixelHeight) / 1_000_000.0
        return String(format: "%.0f MP", mp)
    }

    private var specSummaryText: String {
        var parts: [String] = []
        parts.append(megaPixelsText)
        parts.append("\(asset.pixelWidth) × \(asset.pixelHeight)")
        if let size = metadata?.fileSize, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private var lensDescription: String {
        guard let focal = metadata?.focalLength, let aperture = metadata?.aperture else {
            return settings.t("No camera information")
        }
        return String(format: "%.0f mm ƒ/%.2f", focal, aperture)
    }

    private var shutterSpeedText: String {
        guard let exp = metadata?.exposureTime, exp > 0 else { return "—" }
        if exp < 1.0 {
            return String(format: "1/%.0f s", 1.0 / exp)
        } else {
            return String(format: "%.1f s", exp)
        }
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.reverseGeocodeLocation(location, preferredLocale: settings.language.locale)
        guard let placemark = placemarks?.first else { return nil }
        var parts: [String] = []
        if let country = placemark.country { parts.append(country) }
        if let administrativeArea = placemark.administrativeArea { parts.append(administrativeArea) }
        if let locality = placemark.locality { parts.append(locality) }
        if let subLocality = placemark.subLocality { parts.append(subLocality) }
        if let name = placemark.name { parts.append(name) }
        return parts.isEmpty ? nil : parts.joined()
    }
}
