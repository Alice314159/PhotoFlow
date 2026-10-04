import SwiftUI

struct MetadataInspectorView: View {
    @ObservedObject var library: PhotoLibrary

    var body: some View {
        ScrollView {
            if let photo = library.selectedPhoto {
                VStack(alignment: .leading, spacing: 16) {
                    header(photo)
                    marks(photo)
                    content(photo)
                    location(photo)
                    exposure(photo)
                    gear(photo)
                    file(photo)
                }
                .padding(16)
            } else {
                ContentUnavailableView(
                    tr("No Photo"),
                    systemImage: "info.circle",
                    description: Text(tr("Select a photo to inspect EXIF and marks."))
                )
                .padding()
            }
        }
        .background(library.skin.palette.panel)
    }

    private func header(_ photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(photo.name)
                .font(.headline)
                .textSelection(.enabled)
            if let date = photo.createdDate ?? photo.fileModificationDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func marks(_ photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(tr("Marks"))
            RatingStarsView(rating: photo.rating, size: 15, interactive: true) { value in
                library.setRating(value, for: photo.id)
            }
            HStack(spacing: 8) {
                ForEach(ColorLabel.assigned) { label in
                    Button {
                        library.setColor(label, for: photo.id)
                    } label: {
                        ColorDot(label: label, isSelected: photo.colorLabel == label, size: 13)
                    }
                    .buttonStyle(.plain)
                    .help(library.colorNames.name(for: label))
                }
            }
            if photo.colorLabel != .none {
                Text(library.colorNames.name(for: photo.colorLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Label(photo.pickStatus.title, systemImage: photo.pickStatus.systemImage)
                    .foregroundStyle(photo.pickStatus.tint)
            }
            .font(.subheadline)
        }
    }

    private func content(_ photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(tr("Content"))
                Spacer()
                if photo.categoriesEditedByUser {
                    Text(tr("edited"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Menu {
                    ForEach(PhotoCategory.allCases.filter { $0 != .other }) { category in
                        Toggle(isOn: Binding(
                            get: { photo.categories.contains(category) },
                            set: { _ in library.toggleCategory(category, for: photo.id) }
                        )) {
                            Label(category.title, systemImage: category.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "pencil")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(tr("Add or remove groups by hand"))
            }
            let assigned = PhotoCategory.allCases.filter { photo.categories.contains($0) && $0 != .other }
            if !photo.isAnalyzed {
                Text(library.isAnalyzing ? tr("Analyzing…") : tr("Not analyzed yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if assigned.isEmpty {
                Text(tr("No group"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !assigned.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 5)], alignment: .leading, spacing: 5) {
                    ForEach(assigned) { category in
                        Button {
                            library.selectCategory(category, additive: false)
                        } label: {
                            Label(category.title, systemImage: category.systemImage)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(Color.white)
                                .background(category.tint.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help(tr("Show all photos in this group"))
                    }
                }
            }
            if !photo.contentLabels.isEmpty {
                Text(photo.contentLabels.prefix(8).map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func location(_ photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("Location"))
            if let place = photo.placeName {
                Label(place, systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.medium))
                    .textSelection(.enabled)
                if let text = photo.placeText, text != place {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            } else if photo.latitude != nil {
                Text(library.lookUpPlaces ? tr("Looking up place name…") : tr("Place lookup is off (Settings)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(tr("No GPS in this file."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let latitude = photo.latitude, let longitude = photo.longitude {
                Text(String(format: "%.5f, %.5f", latitude, longitude))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button(photo.placeName == nil ? tr("Set Location…") : tr("Edit…")) {
                    library.focusContext(on: photo)
                    library.promptSetLocation()
                }
                if photo.latitude != nil || photo.placeName != nil {
                    Button(tr("Open in Maps")) { library.openInMaps(photo) }
                }
            }
            .controlSize(.small)
        }
    }

    private func exposure(_ photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("Exposure"))
            row(tr("Shutter"), photo.shutterSpeed.map(ExposureFormat.shutterLabel))
            row(tr("Aperture"), photo.aperture.map(ExposureFormat.apertureLabel))
            row(tr("ISO"), photo.iso.map { "\($0)" })
            row(tr("Focal Length"), photo.focalLength.map(ExposureFormat.focalLabel))
        }
    }

    private func gear(_ photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("Camera"))
            row(tr("Brand"), photo.cameraBrand)
            row(tr("Body"), photo.camera)
            row(tr("Lens"), photo.lens)
        }
    }

    private func file(_ photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("File"))
            row(tr("Size"), dimension(photo))
            row(tr("Path"), photo.filePath)
        }
    }

    private func dimension(_ photo: PhotoItem) -> String? {
        guard let width = photo.width, let height = photo.height else { return nil }
        return "\(width) × \(height)"
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value ?? "—")
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
    }
}
