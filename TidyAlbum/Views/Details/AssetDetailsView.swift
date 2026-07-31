import CoreLocation
import MapKit
import Photos
import SwiftUI

// MARK: - Asset Details Sheet

struct AssetDetailsView: View {
    let asset: PHAsset
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var metadata: AssetMetadata?

    var body: some View {
        NavigationStack {
            List {
                // Header - always visible
                Section {
                    HStack(spacing: 14) {
                        AssetMediaView(asset: asset, contentMode: .fill, showsVideoBadge: false)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metadata?.fileName ?? PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "—")
                                .font(.headline)
                                .lineLimit(1)
                            Text(asset.mediaType == .video ? settings.t("Video") : settings.t("Photo"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Basic info from PHAsset - always available
                Section(settings.t("File")) {
                    detailRow(settings.t("Dimensions"), value: "\(asset.pixelWidth) × \(asset.pixelHeight)")
                    if let date = asset.creationDate {
                        detailRow(settings.t("Captured"), value: date.formatted(date: .complete, time: .shortened))
                    }
                }

                // Loaded metadata
                if let metadata {
                    if metadata.fileSize > 0 {
                        // File info (loaded)
                        Section {
                            detailRow(settings.t("File Size"), value: ByteCountFormatter.string(fromByteCount: metadata.fileSize, countStyle: .file))
                            detailRow(settings.t("Format"), value: metadata.uniformType)
                        }
                    }

                    if metadata.deviceModel != nil || metadata.lensModel != nil {
                        Section(settings.t("Camera")) {
                            if let value = metadata.deviceModel { detailRow(settings.t("Device"), value: value) }
                            if let value = metadata.lensModel { detailRow(settings.t("Lens"), value: value) }
                            if let value = metadata.aperture { detailRow(settings.t("Aperture"), value: String(format: "ƒ/%.1f", value)) }
                            if let value = metadata.exposureTime { detailRow(settings.t("Exposure"), value: String(format: "1/%.0f s", 1 / value)) }
                            if let value = metadata.iso { detailRow(settings.t("ISO"), value: "ISO \(value)") }
                            if let value = metadata.focalLength { detailRow(settings.t("Focal Length"), value: String(format: "%.0f mm", value)) }
                        }
                    }
                }

                Section(settings.t("Location")) {
                    if let location = asset.location {
                        locationMap(location)
                            .frame(height: 180)
                            .listRowInsets(EdgeInsets())
                    } else {
                        Label(settings.t("No location data"), systemImage: "location.slash")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(settings.t("Photo Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(settings.t("Done")) { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if metadata == nil {
                    HStack {
                        ProgressView()
                        Text(settings.t("Loading details…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 16)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            metadata = await AssetMetadataService().load(for: asset)
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func locationMap(_ location: CLLocation) -> some View {
        let coordinate = location.coordinate
        return Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 900,
            longitudinalMeters: 900
        ))) {
            Marker(settings.t("Captured"), coordinate: coordinate)
        }
        .mapStyle(.standard(elevation: .realistic))
    }
}