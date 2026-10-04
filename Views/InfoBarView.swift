import SwiftUI

struct InfoBarView: View {
    @ObservedObject var library: PhotoLibrary

    var body: some View {
        HStack(spacing: 14) {
            if let photo = library.selectedPhoto {
                Text(photo.name)
                    .font(.headline)
                    .lineLimit(1)

                RatingStarsView(rating: photo.rating, size: 13, interactive: true) { value in
                    library.setRating(value, for: photo.id)
                }

                HStack(spacing: 6) {
                    ForEach(ColorLabel.assigned) { label in
                        Button {
                            library.setColor(label, for: photo.id)
                        } label: {
                            ColorDot(label: label, isSelected: photo.colorLabel == label, size: 12)
                        }
                        .buttonStyle(.plain)
                        .help(library.colorNames.name(for: label))
                    }
                }

                pickButtons(for: photo)

                Spacer()

                metadata(photo)

                ShareLink(items: library.batchPhotos.map(\.url)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help(tr("Share (Mail, Messages, AirDrop…)"))

                Menu {
                    PhotoActionsMenu(library: library)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(tr("More: Save As, Email, Copy, Export, Open With…"))
            } else {
                Text(library.folderURL == nil ? tr("No folder open") : tr("No photo selected"))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text("\(visibleIndex) / \(library.filteredPhotos.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            EdgeToggleButton(edge: .bottom, title: nil) {
                library.showInfoBar = false
            }
            .help(tr("Hide info bar (')"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(library.skin.palette.chrome)
    }

    private func pickButtons(for photo: PhotoItem) -> some View {
        HStack(spacing: 4) {
            pickButton(tr("P"), status: .picked, current: photo.pickStatus)
            pickButton(tr("X"), status: .rejected, current: photo.pickStatus)
            pickButton(tr("U"), status: .none, current: photo.pickStatus)
        }
    }

    private func pickButton(_ title: String, status: PickStatus, current: PickStatus) -> some View {
        Button(title) {
            library.setPick(status)
        }
        .buttonStyle(.bordered)
        .tint(current == status ? status.tint : nil)
        .help("\(status.title) (\(status.shortcut))")
    }

    private func metadata(_ photo: PhotoItem) -> some View {
        HStack(spacing: 12) {
            Text(photo.fileKind == "RAW" ? tr("RAW · %@", photo.url.pathExtension.uppercased()) : photo.fileKind)
                .fontWeight(.semibold)
            if let iso = photo.iso {
                Text(tr("ISO %@", iso))
            }
            if let shutter = photo.shutterSpeed {
                Text(ExposureFormat.shutterLabel(shutter))
            }
            if let aperture = photo.aperture {
                Text(ExposureFormat.apertureLabel(aperture))
            }
            if let focal = photo.focalLength {
                Text(ExposureFormat.focalLabel(focal))
            }
            if photo.camera != nil || photo.cameraMake != nil {
                Text(photo.cameraDisplayName)
                    .lineLimit(1)
            }
            if let lens = photo.lens, !lens.isEmpty {
                Text(lens)
                    .lineLimit(1)
            }
            if let date = photo.createdDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var visibleIndex: Int {
        library.selectedVisibleIndex.map { $0 + 1 } ?? 0
    }
}
