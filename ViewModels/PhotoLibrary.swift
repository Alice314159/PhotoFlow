import AppKit
import Foundation
import SwiftUI

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case loupe
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loupe: tr("Loupe")
        case .grid: tr("Grid")
        }
    }

    var systemImage: String {
        switch self {
        case .loupe: "rectangle.inset.filled"
        case .grid: "square.grid.2x2"
        }
    }
}

struct ZoomCommand: Equatable {
    enum Kind {
        case toggle, zoomIn, zoomOut, fit, actual
    }

    let kind: Kind
    let id = UUID()
}

@MainActor
final class PhotoLibrary: ObservableObject {
    @Published var photos: [PhotoItem] = [] {
        didSet { rebuildIndexes() }
    }
    @Published var selectedID: String? {
        didSet {
            if let selectedID, let position = visibleIndex[selectedID] { lastVisiblePosition = position }
            if selectedID != oldValue { prefetchNeighbors() }
        }
    }
    @Published var folderURL: URL?
    @Published var filter = FilterState() {
        didSet {
            rebuildVisible()
            revealSelection()
        }
    }
    @Published var bounds = FilterBounds()
    @Published var viewMode: LibraryViewMode = .loupe
    @Published var sort: PhotoSort = .filename {
        didSet { rebuildVisible() }
    }
    @Published private(set) var filteredPhotos: [PhotoItem] = []
    @Published var inspectorTab: InspectorTab = .filter
    @Published var isLoading = false
    @Published var scanProgress = ""
    @Published var showSidebar = true {
        didSet { persistPanels() }
    }
    @Published var showFilterPanel = true {
        didSet { persistPanels() }
    }
    @Published var showFilmstrip = true {
        didSet { persistPanels() }
    }
    @Published var showInfoBar = true {
        didSet { persistPanels() }
    }
    @Published var isExporting = false
    @Published var exportSettings = ExportSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(exportSettings) {
                UserDefaults.standard.set(data, forKey: "exportSettings")
            }
        }
    }
    @Published var copyNote: String?
    @Published var showSettings = false
    @Published var showExportSheet = false
    @Published var showRenameSheet = false
    @Published var checkedIDs: Set<String> = []
    @Published var exportNote: String?
    @Published var autoAdvanceOnPick = true {
        didSet { UserDefaults.standard.set(autoAdvanceOnPick, forKey: "autoAdvanceOnPick") }
    }
    @Published var colorNames = ColorLabelNames() {
        didSet { persistColorNames() }
    }
    @Published var skin: AppSkin = .midnight {
        didSet { UserDefaults.standard.set(skin.rawValue, forKey: "appSkin") }
    }
    @Published var showTopBar = true {
        didSet {
            if !isRestoringPanels { UserDefaults.standard.set(showTopBar, forKey: "showTopBar") }
        }
    }
    @Published var gridThumbnailSize: Double = 170 {
        didSet { UserDefaults.standard.set(gridThumbnailSize, forKey: "gridThumbnailSize") }
    }
    @Published var showShortcuts = false
    @Published var language: AppLanguage = L10n.language {
        didSet {
            L10n.language = language
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        }
    }
    @Published var collapsedSidebarSections = Set(UserDefaults.standard.stringArray(forKey: "collapsedSidebarSections") ?? []) {
        didSet { UserDefaults.standard.set(Array(collapsedSidebarSections), forKey: "collapsedSidebarSections") }
    }
    @Published var autoAnalyze = true {
        didSet { UserDefaults.standard.set(autoAnalyze, forKey: "autoAnalyzeContent") }
    }
    @Published var analysisDone = 0
    @Published var analysisTotal = 0
    @Published private(set) var categoryCounts: [PhotoCategory: Int] = [:]
    @Published private(set) var placeCounts: [FacetCount] = []
    @Published var lookUpPlaces = true {
        didSet {
            UserDefaults.standard.set(lookUpPlaces, forKey: "lookUpPlaces")
            if lookUpPlaces, !oldValue, !photos.isEmpty { startLocationIndexing() }
        }
    }
    @Published var placeLookupDone = 0
    @Published var placeLookupTotal = 0
    @Published var collections: [PhotoCollection] = []
    @Published var activeCollectionID: Int64?
    @Published var targetCollectionID: Int64? {
        didSet {
            if let targetCollectionID {
                UserDefaults.standard.set(targetCollectionID, forKey: "targetCollectionID")
            } else {
                UserDefaults.standard.removeObject(forKey: "targetCollectionID")
            }
        }
    }
    @Published private(set) var isPresenting = false
    @Published private(set) var zoomCommand: ZoomCommand?

    static let gridSizeRange: ClosedRange<Double> = 110...360

    private let scanner = FolderScanner()
    let database = PhotoDatabase.shared
    private var folderAccess: URL?
    var loadTask: Task<Void, Never>?
    var analysisTask: Task<Void, Never>?
    var locationTask: Task<Void, Never>?
    var selectionAnchorID: String?
    private(set) var photoIndex: [String: Int] = [:]
    private var visibleIndex: [String: Int] = [:]
    private var panelsBeforeFocus: [Bool]?
    private var isRestoringPanels = false
    /// Where the selection sat in `filteredPhotos`, so a photo leaving the filter selects its neighbour.
    private var lastVisiblePosition = 0
    private var prefetchTask: Task<Void, Never>?
    private var undoStack: [[PhotoItem]] = []
    private var redoStack: [[PhotoItem]] = []
    private var presentationSnapshot: (panels: [Bool], topBar: Bool, mode: LibraryViewMode, wasFullScreen: Bool)?
    private var keyMonitor: Any?
    private var windowObserver: NSObjectProtocol?
    private var fullScreenObserver: NSObjectProtocol?
    private var focusClearedWindows: Set<ObjectIdentifier> = []

    var selectedPhoto: PhotoItem? {
        guard let selectedID, let index = photoIndex[selectedID] else { return nil }
        return photos[index]
    }

    /// Zero-based position of the selection inside `filteredPhotos`.
    var selectedVisibleIndex: Int? {
        selectedID.flatMap { visibleIndex[$0] }
    }

    var canSelectPrevious: Bool {
        (selectedVisibleIndex ?? 0) > 0
    }

    var canSelectNext: Bool {
        guard let index = selectedVisibleIndex else { return false }
        return index < filteredPhotos.count - 1
    }

    var anyPanelVisible: Bool {
        showSidebar || showFilterPanel || showFilmstrip || showInfoBar
    }

    /// Brands with their bodies, most-used first. Rebuilt only when `photos` changes.
    @Published private(set) var cameraFacets: [CameraFacet] = []
    @Published private(set) var lensFacets: [FacetCount] = []
    @Published private(set) var kindFacets: [FacetCount] = []

    func colorCount(_ label: ColorLabel) -> Int {
        photos.filter { $0.colorLabel == label }.count
    }

    init() {
        if UserDefaults.standard.object(forKey: "autoAdvanceOnPick") != nil {
            autoAdvanceOnPick = UserDefaults.standard.bool(forKey: "autoAdvanceOnPick")
        }
        if let raw = UserDefaults.standard.string(forKey: "appSkin"),
           let stored = AppSkin(rawValue: raw) {
            skin = stored
        }
        restorePanels()
        if UserDefaults.standard.object(forKey: "showTopBar") != nil {
            showTopBar = UserDefaults.standard.bool(forKey: "showTopBar")
        }
        let storedGrid = UserDefaults.standard.double(forKey: "gridThumbnailSize")
        if storedGrid > 0 {
            gridThumbnailSize = min(max(storedGrid, Self.gridSizeRange.lowerBound), Self.gridSizeRange.upperBound)
        }
        restoreColorNames()
        if UserDefaults.standard.object(forKey: "autoAnalyzeContent") != nil {
            autoAnalyze = UserDefaults.standard.bool(forKey: "autoAnalyzeContent")
        }
        if UserDefaults.standard.object(forKey: "lookUpPlaces") != nil {
            lookUpPlaces = UserDefaults.standard.bool(forKey: "lookUpPlaces")
        }
        reloadCollections()
        if let stored = UserDefaults.standard.object(forKey: "targetCollectionID") as? Int64,
           collections.contains(where: { $0.id == stored }) {
            targetCollectionID = stored
        }
        if let data = UserDefaults.standard.data(forKey: "exportSettings"),
           let stored = try? JSONDecoder().decode(ExportSettings.self, from: data) {
            exportSettings = stored
        }
        installKeyMonitor()
        restoreLastFolder()
    }

    func openFolder(_ url: URL) {
        loadTask?.cancel()
        cancelAnalysis()
        cancelLocationIndexing()
        activeCollectionID = nil
        stopAccessingFolder()

        let accessed = url.startAccessingSecurityScopedResource()
        if accessed { folderAccess = url }

        folderURL = url
        persistBookmark(url)
        isLoading = true
        scanProgress = tr("Scanning…")
        photos = []
        selectedID = nil
        checkedIDs = []
        selectionAnchorID = nil
        filter.clear()
        filter.smartAlbum = .all

        loadTask = Task { [weak self] in
            await self?.loadFolder(url)
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = tr("Open")
        panel.message = tr("Choose a photo folder to browse. Original files are never modified.")

        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url)
        }
    }

    func select(_ photo: PhotoItem) {
        selectPhoto(photo, toggle: false, extend: false)
    }

    func selectPhoto(_ photo: PhotoItem, toggle: Bool, extend: Bool) {
        selectedID = photo.id
        if toggle {
            if checkedIDs.contains(photo.id) {
                checkedIDs.remove(photo.id)
            } else {
                checkedIDs.insert(photo.id)
            }
            selectionAnchorID = photo.id
        } else if extend {
            let items = filteredPhotos
            let startID = selectionAnchorID ?? selectedID ?? photo.id
            guard let start = items.firstIndex(where: { $0.id == startID }),
                  let end = items.firstIndex(where: { $0.id == photo.id }) else {
                checkedIDs = [photo.id]
                selectionAnchorID = photo.id
                return
            }
            let range = min(start, end)...max(start, end)
            checkedIDs.formUnion(items[range].map(\.id))
        } else {
            checkedIDs = [photo.id]
            selectionAnchorID = photo.id
        }
    }

    func toggleChecked(_ photo: PhotoItem) {
        if checkedIDs.contains(photo.id) {
            checkedIDs.remove(photo.id)
        } else {
            checkedIDs.insert(photo.id)
        }
        selectedID = photo.id
        selectionAnchorID = photo.id
    }

    func selectAllVisible() {
        checkedIDs = Set(filteredPhotos.map(\.id))
    }

    func clearChecked() {
        if let selectedID {
            checkedIDs = [selectedID]
        } else {
            checkedIDs = []
        }
    }

    var batchPhotos: [PhotoItem] {
        if checkedIDs.isEmpty {
            return selectedPhoto.map { [$0] } ?? []
        }
        return filteredPhotos.filter { checkedIDs.contains($0.id) }
    }

    func openExportSheet() {
        guard !batchPhotos.isEmpty else {
            exportNote = tr("Select photos first.")
            return
        }
        showExportSheet = true
    }

    func openRenameSheet() {
        guard !batchPhotos.isEmpty else {
            exportNote = tr("Select photos first.")
            return
        }
        showRenameSheet = true
    }

    func isChecked(_ photo: PhotoItem) -> Bool {
        checkedIDs.contains(photo.id)
    }

    func selectNext() {
        moveSelection(offset: 1)
    }

    func selectPrevious() {
        moveSelection(offset: -1)
    }

    /// True when marks (stars, colors, picks) apply to the whole checked set.
    var isBatchMarking: Bool {
        checkedIDs.count > 1
    }

    func setRating(_ rating: Int, for id: String? = nil) {
        let value = min(max(rating, 0), 5)
        if id == nil, isBatchMarking {
            updateMany(batchPhotos.map(\.id)) { $0.rating = value }
            return
        }
        let target = id ?? selectedID
        guard let target else { return }
        let clamped = value == current(target)?.rating && value > 0 ? 0 : value
        update(target) { $0.rating = clamped }
    }

    func setColor(_ color: ColorLabel, for id: String? = nil) {
        if id == nil, isBatchMarking {
            let targets = batchPhotos
            let allHaveIt = targets.allSatisfy { $0.colorLabel == color }
            updateMany(targets.map(\.id)) { $0.colorLabel = allHaveIt ? .none : color }
            return
        }
        let target = id ?? selectedID
        guard let target else { return }
        update(target) { photo in
            photo.colorLabel = photo.colorLabel == color ? .none : color
        }
    }

    func setPick(_ status: PickStatus, for id: String? = nil) {
        if id == nil, isBatchMarking {
            updateMany(batchPhotos.map(\.id)) { $0.pickStatus = status }
            return
        }
        let target = id ?? selectedID
        guard let target else { return }
        let upcoming = neighborID(after: target, offset: 1)
        update(target) { $0.pickStatus = status }
        if autoAdvanceOnPick, status == .picked || status == .rejected, let upcoming,
           visibleIndex[upcoming] != nil {
            selectedID = upcoming
        }
    }

    func toggleViewMode() {
        viewMode = viewMode == .loupe ? .grid : .loupe
    }

    func showInspector(_ tab: InspectorTab) {
        if showFilterPanel, inspectorTab == tab {
            showFilterPanel = false
        } else {
            inspectorTab = tab
            showFilterPanel = true
        }
    }

    /// Collapses every panel around the image, or restores the previous layout.
    func toggleAllPanels() {
        if anyPanelVisible {
            hideAllPanels()
        } else {
            showAllPanels()
        }
    }

    func hideAllPanels() {
        panelsBeforeFocus = [showSidebar, showFilterPanel, showFilmstrip, showInfoBar]
        setPanels([false, false, false, false])
    }

    func showAllPanels() {
        let saved = panelsBeforeFocus ?? []
        panelsBeforeFocus = nil
        if saved.count == 4, saved.contains(true) {
            setPanels(saved)
        } else {
            setPanels([true, true, true, true])
        }
    }

    private func setPanels(_ values: [Bool]) {
        isRestoringPanels = true
        showSidebar = values[0]
        showFilterPanel = values[1]
        showFilmstrip = values[2]
        showInfoBar = values[3]
        isRestoringPanels = false
        persistPanels()
    }

    // MARK: - Lightroom-style commands

    /// Tab: the left and right panels only, like Lightroom.
    func toggleSidePanels() {
        let show = !(showSidebar || showFilterPanel)
        showSidebar = show
        showFilterPanel = show
    }

    /// ⇧Tab: every panel including the top bar.
    func toggleEverything() {
        if anyPanelVisible || showTopBar {
            hideAllPanels()
            showTopBar = false
        } else {
            showAllPanels()
            showTopBar = true
        }
    }

    /// F: full-screen preview of the current photo; F or Esc returns.
    func togglePresentation() {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        if isPresenting, let saved = presentationSnapshot {
            isRestoringPanels = true
            showSidebar = saved.panels[0]
            showFilterPanel = saved.panels[1]
            showFilmstrip = saved.panels[2]
            showInfoBar = saved.panels[3]
            showTopBar = saved.topBar
            isRestoringPanels = false
            viewMode = saved.mode
            if !saved.wasFullScreen, window?.styleMask.contains(.fullScreen) == true {
                window?.toggleFullScreen(nil)
            }
            presentationSnapshot = nil
            isPresenting = false
            return
        }
        guard selectedPhoto != nil else { return }
        let wasFullScreen = window?.styleMask.contains(.fullScreen) == true
        presentationSnapshot = (
            [showSidebar, showFilterPanel, showFilmstrip, showInfoBar], showTopBar, viewMode, wasFullScreen
        )
        isRestoringPanels = true
        showSidebar = false
        showFilterPanel = false
        showFilmstrip = false
        showInfoBar = false
        showTopBar = false
        isRestoringPanels = false
        viewMode = .loupe
        isPresenting = true
        if !wasFullScreen { window?.toggleFullScreen(nil) }
    }

    /// `[` / `]`: step the rating down or up for the selection.
    func adjustRating(by delta: Int) {
        let targets = isBatchMarking ? batchPhotos : (selectedPhoto.map { [$0] } ?? [])
        guard !targets.isEmpty else { return }
        let values = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, min(max($0.rating + delta, 0), 5)) })
        updateMany(targets.map(\.id)) { $0.rating = values[$0.id] ?? $0.rating }
    }

    /// Backtick: flip between Picked and Unflagged.
    func togglePickFlag() {
        let targets = isBatchMarking ? batchPhotos : (selectedPhoto.map { [$0] } ?? [])
        guard !targets.isEmpty else { return }
        let allPicked = targets.allSatisfy { $0.pickStatus == .picked }
        updateMany(targets.map(\.id)) { $0.pickStatus = allPicked ? .none : .picked }
    }

    func selectFirst() {
        guard let first = filteredPhotos.first else { return }
        select(first)
    }

    func selectLast() {
        guard let last = filteredPhotos.last else { return }
        select(last)
    }

    func selectNone() {
        checkedIDs = []
        selectionAnchorID = nil
    }

    func requestZoom(_ kind: ZoomCommand.Kind) {
        if viewMode == .grid {
            switch kind {
            case .zoomIn: adjustGridSize(by: 30)
            case .zoomOut: adjustGridSize(by: -30)
            case .fit, .actual, .toggle: viewMode = .loupe
            }
            return
        }
        zoomCommand = ZoomCommand(kind: kind)
    }

    func adjustGridSize(by delta: Double) {
        gridThumbnailSize = min(max(gridThumbnailSize + delta, Self.gridSizeRange.lowerBound), Self.gridSizeRange.upperBound)
    }

    func cycleSkin(forward: Bool = true) {
        let all = AppSkin.allCases
        guard let index = all.firstIndex(of: skin) else { return }
        let next = (index + (forward ? 1 : all.count - 1)) % all.count
        skin = all[next]
        flashCopyNote(tr("Skin: %@", skin.title))
    }

    func exportPicked() {
        checkedIDs = Set(photos.filter { $0.pickStatus == .picked }.map(\.id))
        openExportSheet()
    }

    func exportFiltered() {
        checkedIDs = Set(filteredPhotos.map(\.id))
        openExportSheet()
    }

    func exportBatch(_ settings: ExportSettings) {
        let items = batchPhotos
        guard !items.isEmpty else {
            exportNote = tr("Nothing to export.")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = tr("Export")
        panel.message = tr("Export %@ photos. Originals stay untouched.", items.count)

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        isExporting = true
        Task.detached(priority: .userInitiated) { [self] in
            let note: String
            do {
                let count = try PhotoExporter.export(items, to: folder, settings: settings)
                let skipped = items.count - count
                note = tr("Exported %@ photos to %@.", count, folder.lastPathComponent)
                    + (skipped > 0 ? tr(" %@ could not be decoded and were skipped.", skipped) : "")
            } catch {
                note = tr("Export failed: %@", error.localizedDescription)
            }
            await MainActor.run {
                self.isExporting = false
                self.exportNote = note
            }
        }
    }

    /// Copies the original files, byte for byte, into a folder the user picks.
    func copyBatchToFolder() {
        let items = batchPhotos
        guard !items.isEmpty else {
            exportNote = tr("Select photos first.")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = tr("Copy Here")
        panel.message = tr("Copy %@ original files. Existing files are never overwritten.", items.count)

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        isExporting = true
        Task.detached(priority: .userInitiated) { [self] in
            let note: String
            do {
                let count = try PhotoExporter.copy(items, to: folder)
                note = tr("Copied %@ photos to %@.", count, folder.lastPathComponent)
            } catch {
                note = tr("Copy failed: %@", error.localizedDescription)
            }
            await MainActor.run {
                self.isExporting = false
                self.exportNote = note
            }
        }
    }

    /// Puts the selected files on the pasteboard so they can be pasted in Finder or other apps.
    func copyBatchToPasteboard() {
        let urls = batchPhotos.map { $0.url as NSURL }
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls)
        copyNote = urls.count == 1 ? tr("Copied 1 photo") : tr("Copied %@ photos", urls.count)
        let note = copyNote
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.copyNote == note { self?.copyNote = nil }
        }
    }

    func renameBatch(pattern: String) {
        let items = batchPhotos
        guard !items.isEmpty else { return }

        var nextPhotos = photos
        var nextChecked = Set<String>()
        var newSelection = selectedID
        var renamed = 0
        var renames: [String: String] = [:]

        for (offset, photo) in items.enumerated() {
            let ext = photo.url.pathExtension
            let name = NameTemplate.resolve(pattern, photo: photo, index: offset + 1, fileExtension: ext)
            let destination = photo.url.deletingLastPathComponent().appendingPathComponent(name)
            if destination.path == photo.filePath {
                nextChecked.insert(photo.id)
                continue
            }
            var unique = destination
            if FileManager.default.fileExists(atPath: unique.path) {
                unique = PhotoExporter.uniqueURL(named: name, in: photo.url.deletingLastPathComponent())
            }
            do {
                try FileManager.default.moveItem(at: photo.url, to: unique)
                if let index = nextPhotos.firstIndex(where: { $0.id == photo.id }) {
                    let oldPath = nextPhotos[index].filePath
                    nextPhotos[index].filePath = unique.path
                    database.updatePath(from: oldPath, to: unique.path)
                    renames[oldPath] = unique.path
                }
                if photo.id == selectedID {
                    newSelection = unique.path
                }
                nextChecked.insert(unique.path)
                renamed += 1
            } catch {
                nextChecked.insert(photo.id)
            }
        }

        photos = nextPhotos
        selectedID = newSelection
        checkedIDs = nextChecked
        if !renames.isEmpty {
            collections = collections.map { collection in
                var updated = collection
                updated.paths = Set(collection.paths.map { renames[$0] ?? $0 })
                return updated
            }
        }
        exportNote = renamed == 0 ? tr("No files renamed.") : tr("Renamed %@ files.", renamed)
    }

    func revealInFinder() {
        guard let photo = selectedPhoto else { return }
        NSWorkspace.shared.activateFileViewerSelecting([photo.url])
    }

    func applySmartAlbum(_ album: SmartAlbum) {
        filter.applySmartAlbum(album)
        revealSelection()
    }

    func clearFilters() {
        filter.clear()
        revealSelection()
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, !isEditingText {
            // Handled here rather than as menu shortcuts so text fields keep ⌘C / ⌘A / ⌘Z.
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                copyBatchToPasteboard()
                return true
            case "a":
                selectAllVisible()
                return true
            case "z":
                undo()
                return true
            default:
                return false
            }
        }
        if flags == [.command, .shift], !isEditingText,
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            redo()
            return true
        }
        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
            return false
        }

        if isEditingText {
            // Esc / Return leave the search field so arrows page photos again.
            if event.keyCode == 53 || event.keyCode == 36 {
                resignTextFocus()
                return true
            }
            // An empty field has no caret to move, so ← → keep paging photos.
            if (event.keyCode == 123 || event.keyCode == 124), editingText.isEmpty {
                resignTextFocus()
            } else {
                return false
            }
        }

        let shift = flags.contains(.shift)
        switch event.keyCode {
        case 123:
            selectPrevious()
            return true
        case 124:
            selectNext()
            return true
        case 126 where viewMode == .loupe:
            selectPrevious()
            return true
        case 125 where viewMode == .loupe:
            selectNext()
            return true
        case 115:
            selectFirst()
            return true
        case 119:
            selectLast()
            return true
        case 36, 76:
            if viewMode == .grid { viewMode = .loupe }
            return true
        case 48:
            if shift { toggleEverything() } else { toggleSidePanels() }
            return true
        case 53:
            if isPresenting { togglePresentation() } else { clearChecked() }
            return true
        case 120:
            openRenameSheet()
            return true
        case 51 where activeCollectionID != nil, 117 where activeCollectionID != nil:
            removeBatchFromActiveCollection()
            return true
        case 96:
            showTopBar.toggle()
            return true
        case 97:
            showFilmstrip.toggle()
            return true
        case 98:
            showSidebar.toggle()
            return true
        case 100:
            showFilterPanel.toggle()
            return true
        default:
            break
        }

        // Lightroom: Shift + a marking key applies it and moves to the next photo.
        if shift, let mark = Self.shiftedMarks[event.keyCode] {
            markAndAdvance(mark)
            return true
        }

        let chars = (event.charactersIgnoringModifiers ?? "").lowercased()
        switch chars {
        case "1": setRating(1)
        case "2": setRating(2)
        case "3": setRating(3)
        case "4": setRating(4)
        case "5": setRating(5)
        case "0": setRating(0)
        case "p": setPick(.picked)
        case "x": setPick(.rejected)
        case "u": setPick(.none)
        case "`": togglePickFlag()
        case "b": toggleTargetCollection()
        case "6": setColor(.red)
        case "7": setColor(.yellow)
        case "8": setColor(.green)
        case "9": setColor(.blue)
        case "-": setColor(.purple)
        case "[": adjustRating(by: -1)
        case "]": adjustRating(by: 1)
        case "g": viewMode = .grid
        case "e": viewMode = .loupe
        case "z": requestZoom(.toggle)
        case " ":
            if viewMode == .loupe { requestZoom(.toggle) } else { viewMode = .loupe }
        case "f": togglePresentation()
        case "i": showInspector(.info)
        case "\\": showInspector(.filter)
        case "'": showInfoBar.toggle()
        default:
            return false
        }
        return true
    }

    private enum Mark {
        case rating(Int), pick(PickStatus), color(ColorLabel)
    }

    /// Physical key codes, so Shift doesn't turn "1" into "!".
    private static let shiftedMarks: [UInt16: Mark] = [
        29: .rating(0), 18: .rating(1), 19: .rating(2), 20: .rating(3), 21: .rating(4), 23: .rating(5),
        22: .color(.red), 26: .color(.yellow), 28: .color(.green), 25: .color(.blue), 27: .color(.purple),
        35: .pick(.picked), 7: .pick(.rejected), 32: .pick(.none),
    ]

    private func markAndAdvance(_ mark: Mark) {
        let before = selectedID
        switch mark {
        case .rating(let value): setRating(value)
        case .pick(let status): setPick(status)
        case .color(let color): setColor(color)
        }
        if selectedID == before, !isBatchMarking { selectNext() }
    }

    func resignTextFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// Installed once for the app's lifetime so view re-creation can never drop it.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Sheets (export, rename, settings) and open panels keep their own keys.
            guard let self, let window = event.window, window.attachedSheet == nil,
                  window.sheetParent == nil, !(window is NSPanel) else {
                return event
            }
            return MainActor.assumeIsolated { self.handleKey(event) } ? nil : event
        }

        // SwiftUI focuses the search field when the window first becomes key,
        // which happens after onAppear; clear it so arrows page photos immediately.
        // Leaving full screen with the green button or Esc-by-system must also end the preview,
        // otherwise every panel stays hidden.
        fullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPresenting else { return }
                self.togglePresentation()
            }
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow, !(window is NSPanel), window.sheetParent == nil else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let id = ObjectIdentifier(window)
                guard !self.focusClearedWindows.contains(id) else { return }
                self.focusClearedWindows.insert(id)
                DispatchQueue.main.async {
                    if self.isEditingText, self.editingText.isEmpty {
                        window.makeFirstResponder(nil)
                    }
                }
            }
        }
    }

    private var editingText: String {
        let responder = NSApp.keyWindow?.firstResponder
        if let textView = responder as? NSTextView { return textView.string }
        if let field = responder as? NSTextField { return field.stringValue }
        return ""
    }

    private var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let field = responder as? NSTextField { return field.isEditable }
        if let textView = responder as? NSTextView {
            return textView.isEditable && textView.isFieldEditor
        }
        return false
    }

    private func loadFolder(_ url: URL) async {
        let scanned = await Task.detached { [scanner] in
            scanner.scan(folder: url)
        }.value

        if Task.isCancelled { return }
        await loadFiles(scanned)
    }

    /// Reads marks, EXIF and stored content groups for `scanned`, publishing progress as it goes.
    func loadFiles(_ scanned: [ScannedFile]) async {
        let paths = scanned.map { $0.url.path }
        let (stored, analyses, locations) = await Task.detached { [database] in
            (database.annotations(for: paths), database.analyses(for: paths), database.locations(for: paths))
        }.value
        if Task.isCancelled { return }

        let reader = Task.detached(priority: .userInitiated) { [self] () -> ([PhotoItem], Set<String>)? in
            var items: [PhotoItem] = []
            var dirty: Set<String> = []
            items.reserveCapacity(scanned.count)
            let batch = scanned.count > 2000 ? 200 : 60

            for (index, file) in scanned.enumerated() {
                if Task.isCancelled { return nil }

                var item = stored[file.url.path] ?? PhotoItem(filePath: file.url.path)
                if MetadataReader.needsRefresh(existing: stored[file.url.path], modificationDate: file.modificationDate) {
                    item = MetadataReader.read(into: item, modificationDate: file.modificationDate)
                    dirty.insert(item.id)
                } else {
                    item.fileModificationDate = file.modificationDate
                }
                item.fileByteSize = file.fileSize
                if let analysis = analyses[file.url.path] {
                    item.categories = analysis.categories
                    item.contentLabels = analysis.labels
                    item.categoriesEditedByUser = analysis.manual
                    item.isAnalyzed = analysis.manual || analysis.version >= PhotoClassifier.version
                }
                if let location = locations[file.url.path] {
                    item.latitude = location.latitude
                    item.longitude = location.longitude
                    item.placeName = location.placeName
                    item.placeText = location.placeText
                    item.locationChecked = true
                }
                items.append(item)

                if index % batch == 0 || index == scanned.count - 1 {
                    let snapshot = items
                    let progress = tr("Reading %@ / %@", index + 1, scanned.count)
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.photos = self.keepingCurrentMarks(snapshot)
                        self.scanProgress = progress
                        if self.selectedID == nil {
                            self.selectedID = self.filteredPhotos.first?.id
                        }
                    }
                }
            }

            return (items, dirty)
        }

        let result = await withTaskCancellationHandler {
            await reader.value
        } onCancel: {
            reader.cancel()
        }
        guard let (loaded, dirty) = result, !Task.isCancelled else { return }

        // Marks set while the folder was still loading live only in `photos`; keep them.
        let items = keepingCurrentMarks(loaded)
        photos = items
        if !dirty.isEmpty {
            let refreshed = items.filter { dirty.contains($0.id) }
            Task.detached(priority: .utility) { [database] in
                database.saveMany(refreshed)
            }
        }
        bounds = FilterBounds.from(photos: items)
        isLoading = false
        scanProgress = ""
        revealSelection()
        startLocationIndexing()
        if autoAnalyze { startAnalysis() }
    }

    private func keepingCurrentMarks(_ items: [PhotoItem]) -> [PhotoItem] {
        guard !photos.isEmpty else { return items }
        var result = items
        for index in result.indices {
            guard let current = photoIndex[result[index].id].map({ photos[$0] }) else { continue }
            result[index].rating = current.rating
            result[index].colorLabel = current.colorLabel
            result[index].pickStatus = current.pickStatus
        }
        return result
    }

    private func rebuildIndexes() {
        var map: [String: Int] = [:]
        map.reserveCapacity(photos.count)
        for (index, photo) in photos.enumerated() {
            map[photo.id] = index
        }
        photoIndex = map
        let facets = CameraFacet.build(from: photos)
        if facets.cameras != cameraFacets { cameraFacets = facets.cameras }
        if facets.lenses != lensFacets { lensFacets = facets.lenses }
        if facets.kinds != kindFacets { kindFacets = facets.kinds }
        var counts: [PhotoCategory: Int] = [:]
        for photo in photos {
            for category in photo.categories { counts[category, default: 0] += 1 }
        }
        if counts != categoryCounts { categoryCounts = counts }
        var places: [String: Int] = [:]
        for photo in photos {
            if let place = photo.placeName { places[place, default: 0] += 1 }
        }
        let placeFacets = places.map { FacetCount(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        if placeFacets != placeCounts { placeCounts = placeFacets }
        rebuildVisible()
    }

    private func rebuildVisible() {
        let query = SearchQuery(filter.searchText)
        let visible = photos.filter { filter.matches($0, query: query) }.sorted(by: sort.compare)
        var map: [String: Int] = [:]
        map.reserveCapacity(visible.count)
        for (index, photo) in visible.enumerated() {
            map[photo.id] = index
        }
        visibleIndex = map
        filteredPhotos = visible
    }

    /// Decodes the neighbours of the current photo so paging feels instant.
    private func prefetchNeighbors() {
        guard let index = selectedVisibleIndex else { return }
        let urls = [index + 1, index - 1, index + 2]
            .filter { filteredPhotos.indices.contains($0) }
            .map { filteredPhotos[$0].url }
        guard !urls.isEmpty else { return }
        // Holding an arrow key would otherwise queue dozens of full-size decodes.
        prefetchTask?.cancel()
        prefetchTask = Task.detached(priority: .utility) {
            for url in urls {
                if Task.isCancelled { return }
                _ = ThumbnailCache.shared.image(for: url, maxPixelSize: ThumbnailCache.loupeSize)
            }
        }
    }

    private func persistPanels() {
        guard !isRestoringPanels else { return }
        UserDefaults.standard.set(
            [showSidebar, showFilterPanel, showFilmstrip, showInfoBar],
            forKey: "panelVisibility"
        )
    }

    private func restorePanels() {
        guard let values = UserDefaults.standard.array(forKey: "panelVisibility") as? [Bool],
              values.count == 4 else { return }
        isRestoringPanels = true
        showSidebar = values[0]
        showFilterPanel = values[1]
        showFilmstrip = values[2]
        showInfoBar = values[3]
        isRestoringPanels = false
    }

    private func update(_ id: String, mutate: (inout PhotoItem) -> Void) {
        guard let index = photoIndex[id] else { return }
        var next = photos
        recordUndo([next[index]])
        mutate(&next[index])
        photos = next
        let photo = next[index]
        Task.detached { [database] in
            database.save(photo)
        }
        if !filter.matches(photo) {
            revealSelection()
        }
    }

    private func updateMany(_ ids: [String], mutate: (inout PhotoItem) -> Void) {
        guard !ids.isEmpty else { return }
        var next = photos
        var changed: [PhotoItem] = []
        recordUndo(ids.compactMap { photoIndex[$0].map { next[$0] } })
        for id in ids {
            guard let index = photoIndex[id] else { continue }
            mutate(&next[index])
            changed.append(next[index])
        }
        photos = next
        Task.detached { [database] in
            database.saveMany(changed)
        }
        revealSelection()
    }

    private func current(_ id: String) -> PhotoItem? {
        photoIndex[id].map { photos[$0] }
    }

    // MARK: - Undo (ratings, colors, picks)

    private func recordUndo(_ before: [PhotoItem]) {
        guard !before.isEmpty else { return }
        undoStack.append(before)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(restore(snapshot))
        flashCopyNote(tr("Undo"))
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(restore(snapshot))
        flashCopyNote(tr("Redo"))
    }

    /// Puts `snapshot` back and returns what it replaced.
    private func restore(_ snapshot: [PhotoItem]) -> [PhotoItem] {
        var next = photos
        var replaced: [PhotoItem] = []
        var changed: [PhotoItem] = []
        for item in snapshot {
            guard let index = photoIndex[item.id] else { continue }
            replaced.append(next[index])
            var restored = next[index]
            restored.rating = item.rating
            restored.colorLabel = item.colorLabel
            restored.pickStatus = item.pickStatus
            next[index] = restored
            changed.append(restored)
        }
        photos = next
        // Save the current rows with restored marks, not the old snapshot (which may be stale or from another folder).
        Task.detached { [database] in
            database.saveMany(changed)
        }
        revealSelection()
        return replaced
    }

    private func neighborID(after id: String, offset: Int) -> String? {
        guard let index = visibleIndex[id] else { return nil }
        let next = index + offset
        guard filteredPhotos.indices.contains(next) else { return nil }
        return filteredPhotos[next].id
    }

    private func moveSelection(offset: Int) {
        let items = filteredPhotos
        guard !items.isEmpty else { return }
        if let index = selectedVisibleIndex {
            let next = min(max(index + offset, 0), items.count - 1)
            selectedID = items[next].id
        } else {
            selectedID = items[offset >= 0 ? 0 : items.count - 1].id
        }
        // Paging leaves a multi-selection, so later marks hit only the new photo.
        if let selectedID {
            checkedIDs = [selectedID]
            selectionAnchorID = selectedID
        }
    }

    /// Keeps the selection visible: if the photo left the filter (e.g. flagged in "Unflagged"),
    /// select the one that took its place instead of jumping back to the first photo.
    func revealSelection() {
        if let selectedID, visibleIndex[selectedID] != nil {
            return
        }
        guard !filteredPhotos.isEmpty else {
            selectedID = nil
            return
        }
        let replacement = filteredPhotos[min(lastVisiblePosition, filteredPhotos.count - 1)].id
        selectedID = replacement
        if checkedIDs.count <= 1 {
            checkedIDs = [replacement]
            selectionAnchorID = replacement
        }
    }

    private func persistBookmark(_ url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: "lastFolderBookmark")
        } catch {
            UserDefaults.standard.set(url.path, forKey: "lastFolderPath")
        }
    }

    private func restoreLastFolder() {
        if let data = UserDefaults.standard.data(forKey: "lastFolderBookmark") {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                openFolder(url)
                return
            }
        }
        if let path = UserDefaults.standard.string(forKey: "lastFolderPath") {
            openFolder(URL(fileURLWithPath: path))
        }
    }

    private func persistColorNames() {
        if let data = try? JSONEncoder().encode(colorNames) {
            UserDefaults.standard.set(data, forKey: "colorLabelNames")
        }
    }

    private func restoreColorNames() {
        guard let data = UserDefaults.standard.data(forKey: "colorLabelNames"),
              let names = try? JSONDecoder().decode(ColorLabelNames.self, from: data) else { return }
        colorNames = names
    }

    private func stopAccessingFolder() {
        folderAccess?.stopAccessingSecurityScopedResource()
        folderAccess = nil
    }
}
