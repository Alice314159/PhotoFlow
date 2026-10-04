import SwiftUI

struct InspectorPanelView: View {
    @ObservedObject var library: PhotoLibrary

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker(tr("Inspector"), selection: $library.inspectorTab) {
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
                if library.inspectorTab == .filter {
                    FilterPanelView(library: library)
                } else {
                    MetadataInspectorView(library: library)
                }
            }
        }
        .frame(minWidth: 240, idealWidth: 268, maxWidth: 300)
        .background(library.skin.palette.panel)
    }

    private func title(for tab: InspectorTab) -> String {
        let count = library.filter.activeCount
        return tab == .filter && count > 0 ? "\(tab.title) · \(count)" : tab.title
    }
}
