import SwiftUI

struct InspectorPanelView: View, Equatable {
    let library: PhotoLibrary
    @ObservedObject var filters: LibraryFilters

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.library === rhs.library && lhs.filters === rhs.filters
    }

    init(library: PhotoLibrary) {
        self.library = library
        _filters = ObservedObject(wrappedValue: library.filters)
    }

    private var snap: LibraryFilters.Snapshot { filters.snapshot }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker(tr("Inspector"), selection: Binding(
                    get: { snap.inspectorTab },
                    set: { library.inspectorTab = $0 }
                )) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(title(for: tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help(tr("Filter (\\ or ⌘F)  ·  Info (I)"))

                EdgeToggleButton(edge: .trailing, helpText: tr("Hide Inspector (F8)")) {
                    library.showFilterPanel = false
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            Group {
                if snap.inspectorTab == .filter {
                    FilterPanelView(library: library)
                        .equatable()
                } else {
                    MetadataInspectorView(library: library)
                }
            }
        }
        .frame(minWidth: 240, idealWidth: 268, maxWidth: 300)
        .background(snap.skin.palette.panel)
    }

    private func title(for tab: InspectorTab) -> String {
        let count = snap.filter.activeCount
        return tab == .filter && count > 0 ? "\(tab.title) · \(count)" : tab.title
    }
}
