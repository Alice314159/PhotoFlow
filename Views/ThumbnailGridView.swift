import AppKit
import SwiftUI

struct ThumbnailGridView: View {
    @ObservedObject var library: PhotoLibrary

    var body: some View {
        let size = library.gridThumbnailSize.rounded()
        let columns = [GridItem(.adaptive(minimum: size, maximum: size + 40), spacing: 10)]
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(library.filteredPhotos) { photo in
                        ThumbnailCell(
                            photo: photo,
                            isSelected: library.selectedID == photo.id,
                            isChecked: library.isChecked(photo),
                            width: size,
                            height: (size * 0.71).rounded(),
                            inTargetCollection: library.isInTargetCollection(photo),
                            onToggleCheck: { library.toggleChecked(photo) }
                        )
                        .id(photo.id)
                        .draggable(photo.url) {
                            CachedThumbnail(url: photo.url, version: photo.fileModificationDate)
                                .frame(width: 90, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .contextMenu { PhotoActionsMenu(library: library, anchor: photo) }
                        .onTapGesture(count: 2) {
                            library.select(photo)
                            library.viewMode = .loupe
                        }
                        .onTapGesture(count: 1) {
                            let flags = NSEvent.modifierFlags
                            library.selectPhoto(
                                photo,
                                toggle: flags.contains(.command),
                                extend: flags.contains(.shift)
                            )
                        }
                    }
                }
                .padding(14)
            }
            .onChange(of: library.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
        .background(library.skin.palette.canvas)
    }
}
