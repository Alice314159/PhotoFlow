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
final class BackgroundProgress: ObservableObject {
    @Published var analysisDone = 0
    @Published var placeLookupDone = 0
}

/// Export / copy toasts. Kept off `PhotoLibrary` so a flash or spinner does not rebuild the grid.
@MainActor
final class LibraryActivity: ObservableObject {
    @Published var isExporting = false
    @Published var exportNote: String?
    @Published var copyNote: String?
}

/// What the grid, filmstrip, and loupe actually draw. Chrome can publish without invalidating these views.
@MainActor
final class LibraryBrowser: ObservableObject {
    @Published var filteredPhotos: [PhotoItem] = []
    @Published var selectedID: String?
    @Published var checkedIDs: Set<String> = []
    @Published var gridThumbnailSize: Double = 170
    @Published var viewMode: LibraryViewMode = .loupe
    @Published var skin: AppSkin = .midnight
    @Published var targetPaths: Set<String> = []
    @Published var isLoading = false
    @Published var scanProgress = ""
    @Published var showInfoBar = true
    @Published var zoomCommand: ZoomCommand?

    func isInTarget(_ photo: PhotoItem) -> Bool {
        targetPaths.contains(photo.filePath)
    }
}

/// Search field text. Typing here must not publish `PhotoLibrary` on every key.
@MainActor
final class SearchBox: ObservableObject {
    @Published var text = ""
}

/// Sidebar lists: Smart albums, collections, Auto Groups, Places. Search text is not included.
@MainActor
final class LibraryLists: ObservableObject {
    struct Snapshot: Equatable {
        var folderName: String?
        var folderPath: String?
        var activeCollectionID: Int64?
        var collections: [PhotoCollection] = []
        var targetCollectionID: Int64?
        var markCounts = MarkCounts()
        var photoCount = 0
        var categoryCounts: [PhotoCategory: Int] = [:]
        var placeCounts: [FacetCount] = []
        var smartAlbum: SmartAlbum = .all
        var selectedCategories: Set<PhotoCategory> = []
        var selectedPlaces: Set<String> = []
        var colorNames = ColorLabelNames()
        var isLoading = false
        var scanProgress = ""
        var analysisTotal = 0
        var placeLookupTotal = 0
        var collapsed: Set<String> = []
        var skin: AppSkin = .midnight
    }

    @Published var snapshot = Snapshot()
}

/// Filter / inspector chrome. Search text is omitted so typing does not rebuild facets.
@MainActor
final class LibraryFilters: ObservableObject {
    struct Snapshot: Equatable {
        var filter = FilterState()
        var cameraFacets: [CameraFacet] = []
        var lensFacets: [FacetCount] = []
        var kindFacets: [FacetCount] = []
        var bounds = FilterBounds()
        var colorNames = ColorLabelNames()
        var skin: AppSkin = .midnight
        var photoCount = 0
        var visibleCount = 0
        var inspectorTab: InspectorTab = .filter
    }

    @Published var snapshot = Snapshot()
}

@MainActor
final class PhotoLibrary: ObservableObject {
    @Published var photos: [PhotoItem] = [] {
        didSet {
            if let changed = markOnlyChange {
                markOnlyChange = nil
                refreshAfterMarks(changed)
            } else if let changed = contentOnlyChange {
                contentOnlyChange = nil
                refreshAfterContent(changed)
            } else if deferFacetRebuild {
                rebuildPhotoIndex()
                rebuildVisible()
            } else {
                rebuildIndexes()
            }
            syncLists()
            syncFilters()
        }
    }
    @Published private(set) var markCounts = MarkCounts() {
        didSet { syncLists() }
    }
    @Published var selectedID: String? {
        didSet {
            if let selectedID, let position = visibleIndex[selectedID] { lastVisiblePosition = position }
            if selectedID != oldValue { prefetchNeighbors() }
            syncBrowser()
        }
    }
    @Published var folderURL: URL? {
        didSet { syncLists() }
    }
    @Published var filter = FilterState() {
        didSet {
            if filter.differsOnlyInSearch(from: oldValue) {
                scheduleSearchRebuild()
            } else {
                searchRebuildTask?.cancel()
                rebuildVisible()
                revealSelection()
                syncLists()
                syncFilters()
            }
        }
    }
    @Published var bounds = FilterBounds() {
        didSet { syncFilters() }
    }
    @Published var viewMode: LibraryViewMode = .loupe {
        didSet { syncBrowser() }
    }
    @Published var sort: PhotoSort = .filename {
        didSet { rebuildVisible() }
    }
    @Published private(set) var filteredPhotos: [PhotoItem] = [] {
        didSet {
            syncBrowser()
            syncFilters()
        }
    }
    @Published var inspectorTab: InspectorTab = .filter {
        didSet { syncFilters() }
    }
    @Published var isLoading = false {
        didSet {
            syncBrowser()
            syncLists()
        }
    }
    @Published var scanProgress = "" {
        didSet {
            syncBrowser()
            syncLists()
        }
    }
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
        didSet {
            persistPanels()
            syncBrowser()
        }
    }
    @Published var exportSettings = ExportSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(exportSettings) {
                UserDefaults.standard.set(data, forKey: Preferences.Key.exportSettings)
            }
        }
    }
    @Published var showSettings = false
    @Published var showExportSheet = false
    @Published var showRenameSheet = false
    @Published var checkedIDs: Set<String> = [] {
        didSet { syncBrowser() }
    }
    @Published var autoAdvanceOnPick = true {
        didSet { UserDefaults.standard.set(autoAdvanceOnPick, forKey: Preferences.Key.autoAdvanceOnPick) }
    }
    @Published var colorNames = ColorLabelNames() {
        didSet {
            persistColorNames()
            syncLists()
            syncFilters()
        }
    }
    @Published var skin: AppSkin = .midnight {
        didSet {
            UserDefaults.standard.set(skin.rawValue, forKey: Preferences.Key.skin)
            syncBrowser()
            syncLists()
            syncFilters()
        }
    }
    @Published var showTopBar = true {
        didSet {
            if !isRestoringPanels { UserDefaults.standard.set(showTopBar, forKey: Preferences.Key.showTopBar) }
        }
    }
    @Published var gridThumbnailSize: Double = 170 {
        didSet {
            schedulePersistGridSize()
            syncBrowser()
        }
    }
    @Published var showShortcuts = false
    @Published var language: AppLanguage = L10n.language {
        didSet {
            L10n.language = language
            UserDefaults.standard.set(language.rawValue, forKey: Preferences.Key.language)
        }
    }
    @Published var collapsedSidebarSections = Set(UserDefaults.standard.stringArray(forKey: Preferences.Key.collapsedSidebarSections) ?? []) {
        didSet {
            UserDefaults.standard.set(Array(collapsedSidebarSections), forKey: Preferences.Key.collapsedSidebarSections)
            syncLists()
        }
    }
    @Published var autoAnalyze = true {
        didSet { UserDefaults.standard.set(autoAnalyze, forKey: Preferences.Key.autoAnalyze) }
    }
    @Published var analysisTotal = 0 {
        didSet { syncLists() }
    }
    @Published private(set) var categoryCounts: [PhotoCategory: Int] = [:] {
        didSet { syncLists() }
    }
    @Published private(set) var placeCounts: [FacetCount] = [] {
        didSet { syncLists() }
    }
    @Published var lookUpPlaces = true {
        didSet {
            UserDefaults.standard.set(lookUpPlaces, forKey: Preferences.Key.lookUpPlaces)
            if lookUpPlaces, !oldValue, !photos.isEmpty { startLocationIndexing() }
        }
    }
    /// Counters that tick often live outside the library so only the progress rows redraw.
    let progress = BackgroundProgress()
    let activity = LibraryActivity()
    let browser = LibraryBrowser()
    let searchBox = SearchBox()
    let lists = LibraryLists()
    let filters = LibraryFilters()
    /// Paths in the B-key target collection; grid cells read this instead of scanning `collections`.
    private(set) var targetCollectionPaths: Set<String> = []
    var isExporting: Bool {
        get { activity.isExporting }
        set { activity.isExporting = newValue }
    }
    var exportNote: String? {
        get { activity.exportNote }
        set { activity.exportNote = newValue }
    }
    var copyNote: String? {
        get { activity.copyNote }
        set { activity.copyNote = newValue }
    }
    var analysisDone: Int {
        get { progress.analysisDone }
        set { progress.analysisDone = newValue }
    }
    var placeLookupDone: Int {
        get { progress.placeLookupDone }
        set { progress.placeLookupDone = newValue }
    }
    @Published var placeLookupTotal = 0 {
        didSet { syncLists() }
    }
    @Published var collections: [PhotoCollection] = [] {
        didSet { syncLists() }
    }
    @Published var activeCollectionID: Int64? {
        didSet { syncLists() }
    }
    @Published var targetCollectionID: Int64? {
        didSet {
            if let targetCollectionID {
                UserDefaults.standard.set(targetCollectionID, forKey: Preferences.Key.targetCollectionID)
            } else {
                UserDefaults.standard.removeObject(forKey: Preferences.Key.targetCollectionID)
            }
            refreshTargetPaths()
            syncLists()
        }
    }
    @Published var isPresenting = false

    static let gridSizeRange: ClosedRange<Double> = 110...360

    let scanner = FolderScanner()
    let database = PhotoDatabase.shared
    var folderAccess: URL?
    var extraFolderAccess: [URL] = []
    var loadTask: Task<Void, Never>?
    var analysisTask: Task<Void, Never>?
    var locationTask: Task<Void, Never>?
    var selectionAnchorID: String?
    private(set) var photoIndex: [String: Int] = [:]
    var visibleIndex: [String: Int] = [:]
    var panelsBeforeFocus: [Bool]?
    var isRestoringPanels = false
    /// Where the selection sat in `filteredPhotos`, so a photo leaving the filter selects its neighbour.
    private var lastVisiblePosition = 0
    private var prefetchTask: Task<Void, Never>?
    /// IDs whose ratings, colors, or flags are the only thing changing in the next `photos` assignment.
    var markOnlyChange: [String]?
    /// Analysis or GPS text changed; camera facets can stay.
    var contentOnlyChange: [String]?
    var gridSizePersistTask: Task<Void, Never>?
    /// Incremental folder load: keep the grid updating, skip expensive facet passes until the end.
    var deferFacetRebuild = false
    var searchRebuildTask: Task<Void, Never>?
    var undoStack: [[MarkDelta]] = []
    var redoStack: [[MarkDelta]] = []
    var presentationSnapshot: (panels: [Bool], topBar: Bool, mode: LibraryViewMode, wasFullScreen: Bool)?
    var keyMonitor: Any?
    var windowObserver: NSObjectProtocol?
    var fullScreenObserver: NSObjectProtocol?
    var activationObserver: NSObjectProtocol?
    var focusClearedWindows: Set<ObjectIdentifier> = []

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
        markCounts.colors[label] ?? 0
    }

    init() {
        autoAdvanceOnPick = Preferences.bool(Preferences.Key.autoAdvanceOnPick, default: autoAdvanceOnPick)
        if let raw = UserDefaults.standard.string(forKey: Preferences.Key.skin),
           let stored = AppSkin(rawValue: raw) {
            skin = stored
        }
        restorePanels()
        showTopBar = Preferences.bool(Preferences.Key.showTopBar, default: showTopBar)
        let storedGrid = UserDefaults.standard.double(forKey: Preferences.Key.gridThumbnailSize)
        if storedGrid > 0 {
            gridThumbnailSize = min(max(storedGrid, Self.gridSizeRange.lowerBound), Self.gridSizeRange.upperBound)
        }
        restoreColorNames()
        autoAnalyze = Preferences.bool(Preferences.Key.autoAnalyze, default: autoAnalyze)
        lookUpPlaces = Preferences.bool(Preferences.Key.lookUpPlaces, default: lookUpPlaces)
        reloadCollections()
        if let stored = UserDefaults.standard.object(forKey: Preferences.Key.targetCollectionID) as? Int64,
           collections.contains(where: { $0.id == stored }) {
            targetCollectionID = stored
        }
        if let data = UserDefaults.standard.data(forKey: Preferences.Key.exportSettings),
           let stored = try? JSONDecoder().decode(ExportSettings.self, from: data) {
            exportSettings = stored
        }
        installKeyMonitor()
        observeAppActivation()
        if !database.isAvailable {
            exportNote = tr("Couldn’t open PhotoFlow’s database. Marks won’t be saved until the app can write to Application Support.")
        }
        restoreLastFolder()
        syncBrowser()
        syncLists()
        syncFilters()
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

    func applySmartAlbum(_ album: SmartAlbum) {
        filter.applySmartAlbum(album)
        revealSelection()
    }

    func clearFilters() {
        filter.clear()
        revealSelection()
    }

    private func rebuildPhotoIndex() {
        var map: [String: Int] = [:]
        map.reserveCapacity(photos.count)
        for (index, photo) in photos.enumerated() {
            map[photo.id] = index
        }
        photoIndex = map
    }

    private func rebuildIndexes() {
        rebuildPhotoIndex()
        let facets = CameraFacet.build(from: photos)
        if facets.cameras != cameraFacets { cameraFacets = facets.cameras }
        if facets.lenses != lensFacets { lensFacets = facets.lenses }
        if facets.kinds != kindFacets { kindFacets = facets.kinds }
        rebuildContentFacets()
        let marks = MarkCounts(photos)
        if marks != markCounts { markCounts = marks }
        rebuildVisible()
    }

    private func rebuildContentFacets() {
        var counts: [PhotoCategory: Int] = [:]
        var places: [String: Int] = [:]
        for photo in photos {
            for category in photo.categories { counts[category, default: 0] += 1 }
            if let place = photo.placeName { places[place, default: 0] += 1 }
        }
        if counts != categoryCounts { categoryCounts = counts }
        let placeFacets = places.map { FacetCount(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        if placeFacets != placeCounts { placeCounts = placeFacets }
    }

    private func scheduleSearchRebuild() {
        searchRebuildTask?.cancel()
        if filter.searchText.isEmpty {
            rebuildVisible()
            revealSelection()
            return
        }
        searchRebuildTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            self.rebuildVisible()
            self.revealSelection()
        }
    }

    /// Marks don't affect camera, lens, group, or place facets, so only the counts and,
    /// when the filter or sort looks at marks, the visible list need refreshing.
    private func refreshAfterMarks(_ ids: [String]) {
        let marks = MarkCounts(photos)
        if marks != markCounts { markCounts = marks }
        if filter.dependsOnMarks || sort.dependsOnMarks {
            rebuildVisible()
            return
        }
        var visible = filteredPhotos
        for id in ids {
            if let position = visibleIndex[id], let index = photoIndex[id] {
                visible[position] = photos[index]
            }
        }
        filteredPhotos = visible
    }

    /// Analysis and GPS names don't change camera facets; only group/place counts and, when
    /// search or those filters are on, the visible list.
    private func refreshAfterContent(_ ids: [String]) {
        rebuildContentFacets()
        if filter.dependsOnContent {
            rebuildVisible()
            return
        }
        var visible = filteredPhotos
        for id in ids {
            if let position = visibleIndex[id], let index = photoIndex[id] {
                visible[position] = photos[index]
            }
        }
        filteredPhotos = visible
    }

    func setSearchText(_ text: String) {
        if filter.searchText != text {
            filter.searchText = text
        }
        if searchBox.text != text {
            searchBox.text = text
        }
    }

    func refreshTargetPaths() {
        let next = targetCollection?.paths ?? []
        if next != targetCollectionPaths {
            targetCollectionPaths = next
            syncBrowser()
        }
    }

    private func schedulePersistGridSize() {
        gridSizePersistTask?.cancel()
        gridSizePersistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard let self, !Task.isCancelled else { return }
            UserDefaults.standard.set(self.gridThumbnailSize, forKey: Preferences.Key.gridThumbnailSize)
        }
    }

    private func syncBrowser() {
        let surface = browser
        if surface.selectedID != selectedID { surface.selectedID = selectedID }
        if surface.checkedIDs != checkedIDs { surface.checkedIDs = checkedIDs }
        if surface.gridThumbnailSize != gridThumbnailSize { surface.gridThumbnailSize = gridThumbnailSize }
        if surface.viewMode != viewMode { surface.viewMode = viewMode }
        if surface.skin != skin { surface.skin = skin }
        if surface.targetPaths != targetCollectionPaths { surface.targetPaths = targetCollectionPaths }
        if surface.isLoading != isLoading { surface.isLoading = isLoading }
        if surface.scanProgress != scanProgress { surface.scanProgress = scanProgress }
        if surface.showInfoBar != showInfoBar { surface.showInfoBar = showInfoBar }
        if !surface.filteredPhotos.elementsEqual(filteredPhotos, by: {
            $0.id == $1.id
                && $0.rating == $1.rating
                && $0.colorLabel == $1.colorLabel
                && $0.pickStatus == $1.pickStatus
                && $0.availability == $1.availability
        }) {
            surface.filteredPhotos = filteredPhotos
        }
    }

    private func syncLists() {
        let next = LibraryLists.Snapshot(
            folderName: folderURL?.lastPathComponent,
            folderPath: folderURL?.path,
            activeCollectionID: activeCollectionID,
            collections: collections,
            targetCollectionID: targetCollectionID,
            markCounts: markCounts,
            photoCount: photos.count,
            categoryCounts: categoryCounts,
            placeCounts: placeCounts,
            smartAlbum: filter.smartAlbum,
            selectedCategories: filter.selectedCategories,
            selectedPlaces: filter.selectedPlaces,
            colorNames: colorNames,
            isLoading: isLoading,
            scanProgress: scanProgress,
            analysisTotal: analysisTotal,
            placeLookupTotal: placeLookupTotal,
            collapsed: collapsedSidebarSections,
            skin: skin
        )
        if lists.snapshot != next {
            lists.snapshot = next
        }
    }

    private func syncFilters() {
        let next = LibraryFilters.Snapshot(
            filter: filter.erasingSearch(),
            cameraFacets: cameraFacets,
            lensFacets: lensFacets,
            kindFacets: kindFacets,
            bounds: bounds,
            colorNames: colorNames,
            skin: skin,
            photoCount: photos.count,
            visibleCount: filteredPhotos.count,
            inspectorTab: inspectorTab
        )
        if filters.snapshot != next {
            filters.snapshot = next
        }
    }

    private func patchVisiblePhotos() {
        var visible = filteredPhotos
        for index in visible.indices {
            if let photo = photoIndex[visible[index].id].map({ photos[$0] }) {
                visible[index] = photo
            }
        }
        filteredPhotos = visible
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
        let targets = [index + 1, index - 1, index + 2]
            .filter { filteredPhotos.indices.contains($0) }
            .map { (filteredPhotos[$0].url, filteredPhotos[$0].fileModificationDate) }
        guard !targets.isEmpty else { return }
        // Holding an arrow key would otherwise queue dozens of full-size decodes.
        prefetchTask?.cancel()
        prefetchTask = Task.detached(priority: .utility) {
            for (url, version) in targets {
                if Task.isCancelled { return }
                _ = ThumbnailCache.shared.image(for: url, version: version, maxPixelSize: ThumbnailCache.loupeSize)
            }
        }
    }

    func current(_ id: String) -> PhotoItem? {
        photoIndex[id].map { photos[$0] }
    }

    func neighborID(after id: String, offset: Int) -> String? {
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

    func persistBookmark(_ url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: Preferences.Key.lastFolderBookmark)
        } catch {
            UserDefaults.standard.set(url.path, forKey: Preferences.Key.lastFolderPath)
        }
    }

    private func restoreLastFolder() {
        if let data = UserDefaults.standard.data(forKey: Preferences.Key.lastFolderBookmark) {
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
        if let path = UserDefaults.standard.string(forKey: Preferences.Key.lastFolderPath) {
            openFolder(URL(fileURLWithPath: path))
        }
    }

    private func persistColorNames() {
        if let data = try? JSONEncoder().encode(colorNames) {
            UserDefaults.standard.set(data, forKey: Preferences.Key.colorLabelNames)
        }
    }

    private func restoreColorNames() {
        guard let data = UserDefaults.standard.data(forKey: Preferences.Key.colorLabelNames),
              let names = try? JSONDecoder().decode(ColorLabelNames.self, from: data) else { return }
        colorNames = names
    }

    func stopAccessingFolder() {
        folderAccess?.stopAccessingSecurityScopedResource()
        folderAccess = nil
        for url in extraFolderAccess {
            url.stopAccessingSecurityScopedResource()
        }
        extraFolderAccess = []
    }

    func rememberFolderAccess(_ url: URL) {
        FolderAccessStore.remember(url)
    }

    func startStoredFolderAccess() {
        extraFolderAccess = FolderAccessStore.beginAccess()
    }
}
