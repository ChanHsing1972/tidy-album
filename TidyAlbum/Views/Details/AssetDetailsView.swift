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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    mediaPreview
                    capturedSection
                    fileSection
                    if hasCameraDetails { cameraSection }
                    if let location = asset.location { locationSection(location) }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(settings.t("Media Details"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: asset.localIdentifier) {
            metadata = await AssetMetadataService.shared.load(for: asset)
        }
    }

    // MARK: Preview

    private var mediaPreview: some View {
        AssetMediaView(
            asset: asset,
            contentMode: .fit,
            showsVideoBadge: true,
            allowsPlayback: true,
            isActive: true
        )
        .aspectRatio(assetAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 270)
        .background(Color.black.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var assetAspectRatio: CGFloat {
        guard asset.pixelHeight > 0 else { return 1 }
        return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }

    // MARK: Captured Information

    private var capturedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(capturedDate)
                        .font(.headline)
                    Text(capturedTime)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: asset.mediaType == .video ? "video.fill" : "photo.fill")
                    .foregroundStyle(.blue)
            }
        }
        .informationGroup()
    }

    // MARK: File Information

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(fileName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(fileSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if metadata == nil { ProgressView().controlSize(.small) }
            }
            Divider()
            LazyVGrid(columns: technicalColumns, alignment: .leading, spacing: 12) {
                technicalValue(settings.t("Dimensions"), value: "\(asset.pixelWidth) × \(asset.pixelHeight)")
                if asset.mediaType == .video {
                    technicalValue(settings.t("Duration"), value: durationText)
                }
                if let metadata, metadata.fileSize > 0 {
                    technicalValue(
                        settings.t("File Size"),
                        value: ByteCountFormatter.string(fromByteCount: metadata.fileSize, countStyle: .file)
                    )
                }
            }
        }
        .informationGroup()
    }

    private var technicalColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96), spacing: 12)]
    }

    private func technicalValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    // MARK: Camera Information

    private var hasCameraDetails: Bool {
        guard let metadata else { return false }
        return metadata.deviceModel != nil || metadata.lensModel != nil || metadata.aperture != nil
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let model = metadata?.deviceModel {
                Label(model, systemImage: "camera.fill")
                    .font(.subheadline.weight(.semibold))
            }
            if let lens = metadata?.lensModel {
                Text(lens)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            LazyVGrid(columns: technicalColumns, alignment: .leading, spacing: 12) {
                if let aperture = metadata?.aperture {
                    technicalValue(settings.t("Aperture"), value: String(format: "ƒ/%.1f", aperture))
                }
                if let exposure = metadata?.exposureTime, exposure > 0 {
                    technicalValue(settings.t("Exposure"), value: String(format: "1/%.0f s", 1 / exposure))
                }
                if let iso = metadata?.iso {
                    technicalValue(settings.t("ISO"), value: "ISO \(iso)")
                }
                if let focalLength = metadata?.focalLength {
                    technicalValue(settings.t("Focal Length"), value: String(format: "%.0f mm", focalLength))
                }
            }
        }
        .informationGroup()
    }

    // MARK: Location

    private func locationSection(_ location: CLLocation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(settings.t("Location"), systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
            Map(initialPosition: .region(MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 900,
                longitudinalMeters: 900
            ))) {
                Marker(settings.t("Captured"), coordinate: location.coordinate)
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(coordinateText(location.coordinate))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .informationGroup()
    }

    // MARK: Formatting

    private var fileName: String {
        metadata?.fileName
            ?? PHAssetResource.assetResources(for: asset).first?.originalFilename
            ?? settings.t("Unknown File")
    }

    private var fileSummary: String {
        let type = metadata.flatMap { UTType($0.uniformType)?.preferredFilenameExtension?.uppercased() }
            ?? URL(fileURLWithPath: fileName).pathExtension.uppercased()
        let media = asset.mediaType == .video ? settings.t("Video") : settings.t("Photo")
        return type.isEmpty ? media : "\(media) · \(type)"
    }

    private var capturedDate: String {
        asset.creationDate?.formatted(date: .complete, time: .omitted) ?? settings.t("Unknown Date")
    }

    private var capturedTime: String {
        asset.creationDate?.formatted(date: .omitted, time: .shortened) ?? "—"
    }

    private var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = asset.duration >= 3_600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: asset.duration) ?? "0:00"
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
}

private extension View {
    func informationGroup() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
