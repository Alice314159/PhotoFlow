import AppKit
import SwiftUI

struct FilmstripView: View, Equatable {
    let library: PhotoLibrary
    @ObservedObject var browser: LibraryBrowser

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.library === rhs.library && lhs.browser === rhs.browser
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 8) {
                    ForEach(browser.filteredPhotos) { photo in
                        ThumbnailCell(
                            photo: photo,
                            isSelected: browser.selectedID == photo.id,
                            isChecked: browser.checkedIDs.contains(photo.id),
                            width: 136,
                            height: 94,
                            inTargetCollection: browser.isInTarget(photo),
                            onToggleCheck: { library.toggleChecked(photo) }
                        )
                        .id(photo.id)
                        .draggable(photo.url)
                        .contextMenu { PhotoActionsMenu(library: library, anchor: photo) }
                        .onTapGesture {
                            let flags = NSEvent.modifierFlags
                            library.selectPhoto(
                                photo,
                                toggle: flags.contains(.command),
                                extend: flags.contains(.shift)
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 10)
            }
            .onChange(of: browser.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(height: 110)
        .background(HorizontalWheelScroll().allowsHitTesting(false))
    }
}
