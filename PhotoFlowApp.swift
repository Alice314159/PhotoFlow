import SwiftUI

@main
struct PhotoFlowApp: App {
    @StateObject private var library = PhotoLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Rebuild every view so all `tr()` strings pick up a language switch at once.
                .id(library.language)
                .environmentObject(library)
                .environment(\.appSkin, library.skin)
                .preferredColorScheme(library.skin.colorScheme)
                .tint(library.skin.palette.accent)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(tr("Settings…")) { library.showSettings = true }
                    .keyboardShortcut(",", modifiers: [.command])
                Picker(tr("Language"), selection: $library.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
            }

            CommandGroup(replacing: .newItem) {
                Button(tr("Open Folder…")) { library.chooseFolder() }
                    .keyboardShortcut("o", modifiers: [.command])
            }

            CommandGroup(replacing: .saveItem) {
                Button(tr("Save As…")) { library.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button(tr("Export…")) { library.openExportSheet() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Menu(tr("Email")) {
                    Button(tr("Originals")) { library.emailBatch(resized: false) }
                    Button(tr("Smaller for Mail (JPEG, 2048 px)")) { library.emailBatch(resized: true) }
                }
                Button(tr("Copy to Folder…")) { library.copyBatchToFolder() }
                Divider()
                Button(tr("Edit in Preview")) { library.openInPreview() }
                    .keyboardShortcut("e", modifiers: [.command])
                Button(tr("Show in Finder")) { library.revealBatchInFinder() }
                    .keyboardShortcut("r", modifiers: [.command])
            }

            CommandGroup(replacing: .printItem) {
                Button(tr("Print…")) { library.printSelected() }
                    .keyboardShortcut("p", modifiers: [.command])
            }

            // ⌘Z / ⇧⌘Z / ⌘A / ⌘C are handled by the key monitor so text fields keep their own.
            CommandGroup(after: .undoRedo) {
                Button(tr("Undo Mark (⌘Z)")) { library.undo() }
                Button(tr("Redo Mark (⇧⌘Z)")) { library.redo() }
            }

            CommandGroup(replacing: .sidebar) {
                Button(tr("Grid (G)")) { library.viewMode = .grid }
                Button(tr("Loupe (E)")) { library.viewMode = .loupe }
                Button(tr("Full-Screen Preview (F)")) { library.togglePresentation() }
                Divider()
                Button(tr("Zoom In")) { library.requestZoom(.zoomIn) }
                    .keyboardShortcut("=", modifiers: [.command])
                Button(tr("Zoom Out")) { library.requestZoom(.zoomOut) }
                    .keyboardShortcut("-", modifiers: [.command])
                Button(tr("Fit")) { library.requestZoom(.fit) }
                    .keyboardShortcut("0", modifiers: [.command])
                Button(tr("Actual Pixels (1:1)")) { library.requestZoom(.actual) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button(tr("Toggle Zoom (Z)")) { library.requestZoom(.toggle) }
                Divider()
                Button(tr("Filter Panel")) { library.showInspector(.filter) }
                    .keyboardShortcut("f", modifiers: [.command])
                Button(tr("Photo Info (I)")) { library.showInspector(.info) }
            }

            CommandMenu(tr("Photo")) {
                Button(tr("Pick (P)")) { library.setPick(.picked) }
                Button(tr("Reject (X)")) { library.setPick(.rejected) }
                Button(tr("Unflag (U)")) { library.setPick(.none) }
                Button(tr("Toggle Flag (`)")) { library.togglePickFlag() }
                Divider()
                Button(tr("Rating ★ (1)")) { library.setRating(1) }
                Button(tr("Rating ★★ (2)")) { library.setRating(2) }
                Button(tr("Rating ★★★ (3)")) { library.setRating(3) }
                Button(tr("Rating ★★★★ (4)")) { library.setRating(4) }
                Button(tr("Rating ★★★★★ (5)")) { library.setRating(5) }
                Button(tr("Clear Rating (0)")) { library.setRating(0) }
                Button(tr("Decrease Rating ([)")) { library.adjustRating(by: -1) }
                Button(tr("Increase Rating (])")) { library.adjustRating(by: 1) }
                Divider()
                // Arrow keys are handled by the key monitor; a bare-arrow menu
                // shortcut would steal them from text fields.
                Button(tr("Previous Photo (←)")) { library.selectPrevious() }
                Button(tr("Next Photo (→)")) { library.selectNext() }
                Button(tr("First Photo (Home)")) { library.selectFirst() }
                Button(tr("Last Photo (End)")) { library.selectLast() }
                Divider()
                Button(tr("Rename… (F2)")) { library.openRenameSheet() }
            }

            CommandMenu(tr("Library")) {
                Button(tr("New Collection…")) { library.promptNewCollection() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button(tr("Add to Target Collection (B)")) { library.toggleTargetCollection() }
                Button(tr("Show Target Collection")) { library.showTargetCollection() }
                    .keyboardShortcut("b", modifiers: [.command])
                Button(tr("Remove from Collection (⌫)")) { library.removeBatchFromActiveCollection() }
                    .disabled(library.activeCollectionID == nil)
                Divider()
                Button(tr("Group Photos by Content")) { library.startAnalysis() }
                Button(tr("Re-analyze All (keeps manual edits)")) { library.startAnalysis(force: true) }
                Button(tr("Stop Analyzing")) { library.cancelAnalysis() }
                    .disabled(!library.isAnalyzing)
                Toggle(tr("Analyze Automatically"), isOn: $library.autoAnalyze)
                Divider()
                Button(tr("Set Location…")) { library.promptSetLocation() }
                Toggle(tr("Look Up Place Names"), isOn: $library.lookUpPlaces)
            }

            CommandMenu(tr("Panels")) {
                Button(tr("Top Bar (F5)")) { library.showTopBar.toggle() }
                Button(tr("Filmstrip (F6)")) { library.showFilmstrip.toggle() }
                Button(tr("Library Panel (F7)")) { library.showSidebar.toggle() }
                Button(tr("Inspector Panel (F8)")) { library.showFilterPanel.toggle() }
                Button(tr("Info Bar (')")) { library.showInfoBar.toggle() }
                Divider()
                Button(tr("Toggle Side Panels (Tab)")) { library.toggleSidePanels() }
                Button(tr("Toggle All Panels (⇧Tab)")) { library.toggleEverything() }
            }

            CommandMenu(tr("Skin")) {
                Picker(tr("Skin"), selection: $library.skin) {
                    ForEach(AppSkin.allCases) { skin in
                        Text(skin.title).tag(skin)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
                Button(tr("Next Skin")) { library.cycleSkin(forward: true) }
                    .keyboardShortcut("k", modifiers: [.command, .option])
                Button(tr("Previous Skin")) { library.cycleSkin(forward: false) }
                    .keyboardShortcut("k", modifiers: [.command, .option, .shift])
            }

            CommandMenu(tr("Selection")) {
                Button(tr("Select All (⌘A)")) { library.selectAllVisible() }
                Button(tr("Select None")) { library.selectNone() }
                    .keyboardShortcut("d", modifiers: [.command])
                Button(tr("Keep Current Only (Esc)")) { library.clearChecked() }
                Divider()
                Button(tr("Copy Selected Files (⌘C)")) { library.copyBatchToPasteboard() }
                Button(tr("Copy Selected to Folder…")) { library.copyBatchToFolder() }
                Button(tr("Rename Selected… (F2)")) { library.openRenameSheet() }
                Button(tr("Export Selected… (⇧⌘E)")) { library.openExportSheet() }
            }

            CommandMenu(tr("Export")) {
                Button(tr("Export Selected…")) { library.openExportSheet() }
                Button(tr("Export Picked Photos…")) { library.exportPicked() }
                Button(tr("Export Visible Photos…")) { library.exportFiltered() }
            }

            CommandGroup(replacing: .help) {
                Button(tr("Keyboard Shortcuts")) { library.showShortcuts = true }
                    .keyboardShortcut("/", modifiers: [.command])
            }
        }
    }
}
