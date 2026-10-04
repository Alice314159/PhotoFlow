import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: PhotoLibrary

    var body: some View {
        VStack(spacing: 0) {
            if library.showTopBar {
                TopBarView(library: library)
                    .transition(.move(edge: .top))
                Divider()
            } else if !library.isPresenting {
                EdgeRail(edge: .top, title: tr("Top Bar")) {
                    library.showTopBar = true
                }
                Divider()
            }

            HStack(spacing: 0) {
                if !library.isPresenting { leftPanel }

                VStack(spacing: 0) {
                    viewer
                    if library.checkedIDs.count > 1, !library.isPresenting {
                        Divider()
                        BatchBarView(library: library)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if !library.isPresenting { bottomPanels }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !library.isPresenting { rightPanel }
            }
        }
        .sheet(isPresented: $library.showSettings) {
            SettingsView(library: library)
        }
        .sheet(isPresented: $library.showShortcuts) {
            ShortcutsView(library: library)
        }
        .sheet(isPresented: $library.showExportSheet) {
            BatchExportView(library: library, activity: library.activity)
        }
        .sheet(isPresented: $library.showRenameSheet) {
            BatchRenameView(library: library)
        }
        .background { LibraryActivityAlerts(activity: library.activity) }
        .environment(\.appSkin, library.skin)
        .preferredColorScheme(library.skin.colorScheme)
        .tint(library.skin.palette.accent)
        .background(library.skin.palette.window)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            // SwiftUI focuses the search field on launch, which would swallow arrow keys.
            DispatchQueue.main.async { library.resignTextFocus() }
        }
        .animation(.easeInOut(duration: 0.18), value: library.showSidebar)
        .animation(.easeInOut(duration: 0.18), value: library.showFilterPanel)
        .animation(.easeInOut(duration: 0.18), value: library.showFilmstrip)
        .animation(.easeInOut(duration: 0.18), value: library.showInfoBar)
        .animation(.easeInOut(duration: 0.18), value: library.showTopBar)
        .animation(.easeInOut(duration: 0.18), value: library.checkedIDs.count > 1)
    }

    private var viewer: some View {
        Group {
            if library.viewMode == .grid {
                ThumbnailGridView(library: library, browser: library.browser)
                    .equatable()
            } else {
                ImageViewerView(library: library, browser: library.browser)
                    .equatable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            LibraryCopyToast(activity: library.activity)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded { library.resignTextFocus() }
        )
    }

    @ViewBuilder
    private var leftPanel: some View {
        if library.showSidebar {
            VStack(spacing: 0) {
                PanelHeader(title: tr("Library"), edge: .leading) {
                    library.showSidebar = false
                }
                SidebarView(library: library)
                    .equatable()
            }
            .frame(width: 220)
            .background(library.skin.palette.panel)
            .transition(.move(edge: .leading))
            Divider()
        } else {
            EdgeRail(edge: .leading, title: tr("Library")) {
                library.showSidebar = true
            }
            Divider()
        }
    }

    @ViewBuilder
    private var rightPanel: some View {
        Divider()
        if library.showFilterPanel {
            InspectorPanelView(library: library)
                .equatable()
                .transition(.move(edge: .trailing))
        } else {
            EdgeRail(edge: .trailing, title: library.inspectorTab.title) {
                library.showFilterPanel = true
            }
        }
    }

    @ViewBuilder
    private var bottomPanels: some View {
        let filmstripApplies = library.viewMode == .loupe

        if filmstripApplies, library.showFilmstrip {
            Divider()
            VStack(spacing: 0) {
                PanelHeader(title: tr("Filmstrip"), edge: .bottom, onCollapse: {
                    library.showFilmstrip = false
                }) {
                    Text(tr("%@ photos", library.filteredPhotos.count))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                FilmstripView(library: library, browser: library.browser)
                    .equatable()
            }
            .background(library.skin.palette.chrome)
            .transition(.move(edge: .bottom))
        }

        if library.showInfoBar {
            Divider()
            InfoBarView(library: library)
        }

        if (filmstripApplies && !library.showFilmstrip) || !library.showInfoBar {
            Divider()
            HStack(spacing: 0) {
                if filmstripApplies, !library.showFilmstrip {
                    EdgeRail(edge: .bottom, title: tr("Filmstrip")) {
                        library.showFilmstrip = true
                    }
                }
                if !library.showInfoBar {
                    EdgeRail(edge: .bottom, title: tr("Info Bar")) {
                        library.showInfoBar = true
                    }
                }
            }
        }
    }

}

private struct LibraryActivityAlerts: View {
    @ObservedObject var activity: LibraryActivity

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .alert(tr("PhotoFlow"), isPresented: Binding(
                get: { activity.exportNote != nil },
                set: { if !$0 { activity.exportNote = nil } }
            )) {
                Button(tr("OK"), role: .cancel) { activity.exportNote = nil }
            } message: {
                Text(activity.exportNote ?? "")
            }
    }
}

private struct LibraryCopyToast: View {
    @ObservedObject var activity: LibraryActivity

    var body: some View {
        Group {
            if let note = activity.copyNote {
                Label(note, systemImage: "doc.on.clipboard")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 48)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activity.copyNote)
    }
}
