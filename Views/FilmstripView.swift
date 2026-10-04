import AppKit
import SwiftUI

struct FilmstripView: View {
    @ObservedObject var library: PhotoLibrary

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 8) {
                    ForEach(library.filteredPhotos) { photo in
                        ThumbnailCell(
                            photo: photo,
                            isSelected: library.selectedID == photo.id,
                            isChecked: library.isChecked(photo),
                            width: 136,
                            height: 94,
                            inTargetCollection: library.isInTargetCollection(photo),
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
            .onChange(of: library.selectedID) { _, id in
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
