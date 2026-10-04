import SwiftUI

/// Shown while two or more photos are checked; every action applies to the whole set.
struct BatchBarView: View {
    @ObservedObject var library: PhotoLibrary

    var body: some View {
        let photos = library.batchPhotos

        HStack(spacing: 10) {
            Label(tr("%@ selected", photos.count), systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(library.skin.palette.accent)
                .fixedSize()

            Button(tr("All")) { library.selectAllVisible() }
                .controlSize(.small)
                .help(tr("Select all visible photos (⌘A)"))

            Divider().frame(height: 18)

            HStack(spacing: 4) {
                RatingStarsView(rating: sharedRating(photos), size: 13, interactive: true) { value in
                    library.setRating(value)
                }
                Button {
                    library.setRating(0)
                } label: {
                    Image(systemName: "star.slash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help(tr("Clear rating (0)"))
            }
            .help(tr("Rate all selected (1–5)"))

            HStack(spacing: 5) {
                ForEach(ColorLabel.assigned) { label in
                    Button {
                        library.setColor(label)
                    } label: {
                        ColorDot(label: label, isSelected: !photos.isEmpty && photos.allSatisfy { $0.colorLabel == label }, size: 13)
                    }
                    .buttonStyle(.plain)
                    .help(tr("Label all as %@", library.colorNames.name(for: label)))
                }
            }

            HStack(spacing: 2) {
                pickButton(.picked, tr("P"))
                pickButton(.rejected, tr("X"))
                pickButton(.none, tr("U"))
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Menu {
                    Button(tr("Copy Files (⌘C)")) { library.copyBatchToPasteboard() }
                    Button(tr("Copy to Folder…")) { library.copyBatchToFolder() }
                } label: {
                    Label(tr("Copy"), systemImage: "doc.on.doc")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(tr("Copy original files (never modified)"))

                Menu {
                    Button(tr("Originals (%@)", ByteCount.string(library.batchByteCount))) { library.emailBatch(resized: false) }
                    Button(tr("Smaller for Mail (JPEG, 2048 px)")) { library.emailBatch(resized: true) }
                } label: {
                    Label(tr("Email"), systemImage: "envelope")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                ShareLink(items: photos.map(\.url)) {
                    Label(tr("Share"), systemImage: "square.and.arrow.up")
                }

                Button {
                    library.openExportSheet()
                } label: {
                    Label(tr("Export"), systemImage: "square.and.arrow.up.on.square")
                }
                .buttonStyle(.borderedProminent)

                Menu {
                    PhotoActionsMenu(library: library)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(tr("More: Save As, Rename, Open With, Copy Paths…"))
            }
            .controlSize(.small)

            Button {
                library.clearChecked()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(tr("Clear selection (Esc)"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(library.skin.palette.chrome)
    }

    private func sharedRating(_ photos: [PhotoItem]) -> Int {
        guard let first = photos.first?.rating, photos.allSatisfy({ $0.rating == first }) else { return 0 }
        return first
    }

    private func pickButton(_ status: PickStatus, _ key: String) -> some View {
        let photos = library.batchPhotos
        let active = !photos.isEmpty && photos.allSatisfy { $0.pickStatus == status }
        return Button {
            library.setPick(status)
        } label: {
            Image(systemName: status == .none ? "flag.slash" : status.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active && status != .none ? status.tint : Color.secondary)
                .frame(width: 22, height: 20)
                .background(active ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(tr("%@ all selected (%@)", status.title, key))
    }
}
