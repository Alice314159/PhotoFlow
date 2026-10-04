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

            PickButtons(current: sharedPick(photos), appliesToSelection: true) { library.setPick($0) }

            Spacer(minLength: 8)

            ViewThatFits(in: .horizontal) {
                actions(photos, labeled: true)
                actions(photos, labeled: false)
            }

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

    /// Copy, Email, Share, Export, and More; icon-only when the window is narrow.
    private func actions(_ photos: [PhotoItem], labeled: Bool) -> some View {
        HStack(spacing: 6) {
            Menu {
                Button(tr("Copy Files (⌘C)")) { library.copyBatchToPasteboard() }
                Button(tr("Copy to Folder…")) { library.copyBatchToFolder() }
            } label: {
                label(tr("Copy"), "doc.on.doc", labeled)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(tr("Copy original files (never modified)"))

            Menu {
                Button(tr("Originals (%@)", ByteCount.string(library.batchByteCount))) { library.emailBatch(resized: false) }
                Button(tr("Smaller for Mail (JPEG, 2048 px)")) { library.emailBatch(resized: true) }
            } label: {
                label(tr("Email"), "envelope", labeled)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(tr("Email"))

            ShareLink(items: photos.map(\.url)) {
                label(tr("Share"), "square.and.arrow.up", labeled)
            }
            .help(tr("Share"))

            Button {
                library.openExportSheet()
            } label: {
                label(tr("Export"), "square.and.arrow.up.on.square", labeled)
            }
            .buttonStyle(.borderedProminent)
            .help(tr("Export Selected… (⇧⌘E)"))

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
        .fixedSize()
    }

    @ViewBuilder
    private func label(_ title: String, _ symbol: String, _ labeled: Bool) -> some View {
        if labeled {
            Label(title, systemImage: symbol)
        } else {
            Image(systemName: symbol)
        }
    }

    private func sharedPick(_ photos: [PhotoItem]) -> PickStatus? {
        guard let first = photos.first?.pickStatus, photos.allSatisfy({ $0.pickStatus == first }) else { return nil }
        return first
    }
}
