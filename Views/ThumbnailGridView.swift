import AppKit
import SwiftUI

struct ThumbnailGridView: View, Equatable {
    let library: PhotoLibrary
    @ObservedObject var browser: LibraryBrowser

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.library === rhs.library && lhs.browser === rhs.browser
    }

    var body: some View {
        let size = browser.gridThumbnailSize.rounded()
        let columns = [GridItem(.adaptive(minimum: size, maximum: size + 40), spacing: 10)]
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(browser.filteredPhotos) { photo in
                        ThumbnailCell(
                            photo: photo,
                            isSelected: browser.selectedID == photo.id,
                            isChecked: browser.checkedIDs.contains(photo.id),
                            width: size,
                            height: (size * 0.71).rounded(),
                            inTargetCollection: browser.isInTarget(photo),
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
            .onChange(of: browser.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
        .background(browser.skin.palette.canvas)
    }
}
