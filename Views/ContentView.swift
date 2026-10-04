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
            BatchExportView(library: library)
        }
        .sheet(isPresented: $library.showRenameSheet) {
            BatchRenameView(library: library)
        }
        .alert(tr("PhotoFlow"), isPresented: exportAlert) {
            Button(tr("OK"), role: .cancel) { library.exportNote = nil }
        } message: {
            Text(library.exportNote ?? "")
        }
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
                ThumbnailGridView(library: library)
            } else {
                ImageViewerView(library: library)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if let note = library.copyNote {
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
        .animation(.easeInOut(duration: 0.2), value: library.copyNote)
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
                FilmstripView(library: library)
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

    private var exportAlert: Binding<Bool> {
        Binding(
            get: { library.exportNote != nil },
            set: { if !$0 { library.exportNote = nil } }
        )
    }
}
