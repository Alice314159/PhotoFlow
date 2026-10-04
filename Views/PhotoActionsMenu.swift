import SwiftUI

/// Menu items shared by the right-click menu, the "⋯" button and the batch bar.
/// `anchor` is the photo that was right-clicked; it becomes the selection if it wasn't part of it.
struct PhotoActionsMenu: View {
    @ObservedObject var library: PhotoLibrary
    var anchor: PhotoItem?

    var body: some View {
        let targets = targetPhotos
        let single = targets.count == 1
        let noun = single ? "" : tr(" %@ Photos", targets.count)

        Button(tr("Open in Preview")) { run { library.openInPreview() } }
        Button(tr("Open with Default App")) { run { library.openWithDefaultApp() } }
        Button(tr("Reveal in Finder")) { run { library.revealBatchInFinder() } }

        Divider()

        Button(tr("Copy%@  ⌘C", noun)) { run { library.copyBatchToPasteboard() } }
        if single {
            Button(tr("Copy Image")) { run { library.copyImageToPasteboard() } }
        }
        Button(single ? tr("Copy Path") : tr("Copy Paths")) { run { library.copyPathsToPasteboard() } }
        Button(tr("Copy to Folder…")) { run { library.copyBatchToFolder() } }

        Divider()

        Button(single ? tr("Save As…  ⇧⌘S") : tr("Save%@ As…  ⇧⌘S", noun)) { run { library.saveAs() } }
        Button(tr("Export%@…  ⇧⌘E", noun)) { run { library.openExportSheet() } }
        Button(tr("Rename%@…", noun)) { run { library.openRenameSheet() } }

        Divider()

        Menu(tr("Email")) {
            Button(tr("Originals (%@)", ByteCount.string(byteCount(targets)))) { run { library.emailBatch(resized: false) } }
            Button(tr("Smaller for Mail (JPEG, 2048 px)")) { run { library.emailBatch(resized: true) } }
        }
        ShareLink(items: targets.map(\.url)) {
            Label(tr("Share…"), systemImage: "square.and.arrow.up")
        }

        Divider()

        Menu(tr("Rating")) {
            ForEach(0...5, id: \.self) { value in
                Button(value == 0 ? tr("No Rating  0") : String(repeating: "★", count: value) + "  \(value)") {
                    run { library.setRating(value) }
                }
            }
        }
        Menu(tr("Color Label")) {
            ForEach(ColorLabel.assigned) { label in
                Button(library.colorNames.name(for: label)) { run { library.setColor(label) } }
            }
        }
        Button(tr("Pick  P")) { run { library.setPick(.picked) } }
        Button(tr("Reject  X")) { run { library.setPick(.rejected) } }
        Button(tr("Unflag  U")) { run { library.setPick(.none) } }

        Divider()

        Menu(tr("Add to Collection")) {
            ForEach(library.collections) { collection in
                Button(collection.id == library.targetCollectionID ? tr("%@  B", collection.name) : collection.name) {
                    run { library.addBatch(to: collection.id) }
                }
            }
            if !library.collections.isEmpty { Divider() }
            Button(tr("New Collection…  ⌘N")) { run { library.promptNewCollection() } }
        }
        if let active = library.activeCollection {
            Button(tr("Remove from “%@”  ⌫", active.name)) { run { library.removeBatchFromActiveCollection() } }
        }
        Button(tr("Set Location…")) { run { library.promptSetLocation() } }
        Menu(tr("Content Groups")) {
            ForEach(PhotoCategory.allCases) { category in
                Toggle(category.title, isOn: Binding(
                    get: { !targets.isEmpty && targets.allSatisfy { $0.categories.contains(category) } },
                    set: { _ in run { library.toggleCategory(category) } }
                ))
            }
        }

        if single {
            Divider()
            Button(tr("Set as Desktop Picture")) { run { library.setDesktopPicture() } }
            Button(tr("Print…  ⌘P")) { run { library.printSelected() } }
        }
    }

    private var targetPhotos: [PhotoItem] {
        if let anchor, !library.checkedIDs.contains(anchor.id) { return [anchor] }
        return library.batchPhotos
    }

    private func byteCount(_ photos: [PhotoItem]) -> Int64 {
        photos.reduce(Int64(0)) { $0 + ($1.fileByteSize ?? 0) }
    }

    private func run(_ action: () -> Void) {
        if let anchor { library.focusContext(on: anchor) }
        action()
    }
}
