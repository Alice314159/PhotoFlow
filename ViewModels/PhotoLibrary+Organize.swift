import AppKit
import Foundation

// MARK: - Automatic content groups

extension PhotoLibrary {
    var isAnalyzing: Bool { analysisTotal > 0 }

    var analyzedCount: Int { photos.filter(\.isAnalyzed).count }

    /// Analyzes photos without stored results. `force` redoes everything except groups the user edited.
    func startAnalysis(force: Bool = false) {
        analysisTask?.cancel()
        let pending = photos
            .filter { force ? !$0.categoriesEditedByUser : !$0.isAnalyzed }
            .map(\.url)
        guard !pending.isEmpty else {
            analysisTotal = 0
            analysisDone = 0
            if force { flashCopyNote(tr("Nothing to analyze")) }
            return
        }
        analysisDone = 0
        analysisTotal = pending.count
        analysisTask = Task { [weak self] in
            await self?.runAnalysis(pending)
        }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        analysisDone = 0
        analysisTotal = 0
    }

    private func runAnalysis(_ urls: [URL]) async {
        let worker = Task.detached(priority: .utility) { [self, database] () -> Bool in
            var buffer: [(String, PhotoAnalysis)] = []
            var successes = 0
            var failures = 0

            func flush() async {
                guard !buffer.isEmpty else { return }
                let batch = buffer
                buffer.removeAll()
                database.saveAnalyses(batch.map {
                    ($0.0, $0.1.categories, $0.1.labels, $0.1.faceCount, PhotoClassifier.version, false)
                })
                await MainActor.run { self.applyAnalyses(batch) }
            }

            await withTaskGroup(of: (String, PhotoAnalysis?).self) { group in
                var remaining = urls.makeIterator()
                func enqueue() {
                    guard let url = remaining.next() else { return }
                    group.addTask { (url.path, PhotoClassifier.analyze(url: url)) }
                }
                for _ in 0..<3 { enqueue() }
                for await (path, result) in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        return
                    }
                    if let result {
                        successes += 1
                        buffer.append((path, result))
                    } else {
                        failures += 1
                        // Vision unavailable: stop rather than grind through every file.
                        if successes == 0, failures >= 6 {
                            group.cancelAll()
                            return
                        }
                    }
                    enqueue()
                    if buffer.count >= 24 { await flush() }
                }
            }
            if !Task.isCancelled { await flush() }
            return successes > 0 || failures == 0
        }
        let succeeded = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        if !Task.isCancelled {
            analysisTotal = 0
            analysisDone = 0
            if !succeeded {
                exportNote = tr("Content analysis is unavailable on this Mac right now (Vision could not process images). Photos were left unchanged; try again later from Library ▸ Group Photos by Content.")
            }
        }
    }

    private func applyAnalyses(_ batch: [(String, PhotoAnalysis)]) {
        guard analysisTotal > 0 else { return }
        var next = photos
        for (path, analysis) in batch {
            guard let index = photoIndex[path], !next[index].categoriesEditedByUser else { continue }
            next[index].categories = analysis.categories
            next[index].contentLabels = analysis.labels
            next[index].isAnalyzed = true
        }
        photos = next
        analysisDone = min(analysisDone + batch.count, analysisTotal)
    }

    /// Adds or removes a group by hand; such photos keep their groups when re-analyzing.
    func toggleCategory(_ category: PhotoCategory, for id: String? = nil) {
        let targets = id.flatMap { id in photos.first { $0.id == id } }.map { [$0] } ?? batchPhotos
        guard !targets.isEmpty else { return }
        let allHave = targets.allSatisfy { $0.categories.contains(category) }
        var next = photos
        var saved: [(path: String, categories: Set<PhotoCategory>, labels: [String], faceCount: Int, version: Int, manual: Bool)] = []
        for target in targets {
            guard let index = photoIndex[target.id] else { continue }
            var groups = next[index].categories
            if allHave {
                groups.remove(category)
            } else {
                groups.insert(category)
                if category != .other { groups.remove(.other) }
            }
            if groups.isEmpty { groups = [.other] }
            next[index].categories = groups
            next[index].isAnalyzed = true
            next[index].categoriesEditedByUser = true
            saved.append((target.id, groups, next[index].contentLabels, 0, PhotoClassifier.version, true))
        }
        photos = next
        let rows = saved
        database.write { $0.saveAnalyses(rows) }
        revealSelection()
    }

    /// Sidebar click: show one group; ⌘-click adds or removes it from the current set.
    func selectCategory(_ category: PhotoCategory, additive: Bool) {
        var selected = filter.selectedCategories
        if additive {
            if selected.contains(category) { selected.remove(category) } else { selected.insert(category) }
        } else {
            selected = selected == [category] ? [] : [category]
        }
        filter.selectedCategories = selected
        revealSelection()
    }

    func toggleCategoryFilter(_ category: PhotoCategory) {
        selectCategory(category, additive: true)
    }
}

// MARK: - Places

extension PhotoLibrary {
    var isLookingUpPlaces: Bool { placeLookupTotal > 0 }

    /// Reads GPS for photos never checked, then names the places (if enabled).
    func startLocationIndexing() {
        locationTask?.cancel()
        let unchecked = photos.filter { !$0.locationChecked }.map(\.url)
        locationTask = Task { [weak self] in
            await self?.runLocationIndexing(unchecked)
        }
    }

    func cancelLocationIndexing() {
        locationTask?.cancel()
        locationTask = nil
        placeLookupDone = 0
        placeLookupTotal = 0
    }

    private func runLocationIndexing(_ unchecked: [URL]) async {
        if !unchecked.isEmpty {
            let rows = await Task.detached(priority: .utility) { [database] () -> [(String, PhotoDatabase.StoredLocation)] in
                var rows: [(String, PhotoDatabase.StoredLocation)] = []
                for url in unchecked {
                    if Task.isCancelled { return [] }
                    let coordinate = LocationService.coordinate(of: url)
                    rows.append((url.path, .init(latitude: coordinate?.latitude, longitude: coordinate?.longitude)))
                }
                database.saveLocations(rows.map { ($0.0, $0.1, false) })
                return rows
            }.value
            guard !Task.isCancelled else { return }
            applyLocations(rows)
        }

        guard lookUpPlaces else { return }
        var cells: [String: (latitude: Double, longitude: Double, paths: [String])] = [:]
        for photo in photos where photo.placeName == nil {
            guard let latitude = photo.latitude, let longitude = photo.longitude else { continue }
            let cell = LocationService.cell(for: .init(latitude: latitude, longitude: longitude))
            cells[cell, default: (latitude, longitude, [])].paths.append(photo.filePath)
        }
        guard !cells.isEmpty else { return }

        placeLookupDone = 0
        placeLookupTotal = cells.count
        var failures = 0
        for (cell, group) in cells {
            if Task.isCancelled { return }
            var place = database.cachedPlace(cell: cell)
            if place == nil {
                do {
                    place = try await LocationService.placeNames(for: .init(latitude: group.latitude, longitude: group.longitude))
                    if let place { database.cachePlace(cell: cell, name: place.name, text: place.text) }
                    // Apple's geocoder throttles bursts.
                    try await Task.sleep(for: .milliseconds(1200))
                } catch {
                    if Task.isCancelled { return }
                    failures += 1
                    if failures >= 3 {
                        flashCopyNote(tr("Place lookup paused — offline or rate-limited. It resumes next time."))
                        break
                    }
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }
            }
            if let place {
                let rows = group.paths.map {
                    ($0, PhotoDatabase.StoredLocation(latitude: group.latitude, longitude: group.longitude, placeName: place.name, placeText: place.text))
                }
                database.saveLocations(rows.map { ($0.0, $0.1, false) })
                applyLocations(rows)
            }
            placeLookupDone += 1
        }
        placeLookupTotal = 0
        placeLookupDone = 0
    }

    private func applyLocations(_ rows: [(String, PhotoDatabase.StoredLocation)]) {
        guard !rows.isEmpty else { return }
        var next = photos
        for (path, location) in rows {
            guard let index = photoIndex[path] else { continue }
            next[index].latitude = location.latitude
            next[index].longitude = location.longitude
            next[index].placeName = location.placeName
            next[index].placeText = location.placeText
            next[index].locationChecked = true
        }
        photos = next
    }

    /// For cameras without GPS: name the place by hand. Stored in PhotoFlow only.
    func promptSetLocation() {
        let targets = batchPhotos
        guard !targets.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = targets.count == 1 ? tr("Set Location") : tr("Set Location for %@ Photos", targets.count)
        alert.informativeText = tr("Type a place, e.g. “上海 外滩” or “Yosemite”. It becomes searchable and appears under Places. The photo files are not changed.")
        alert.addButton(withTitle: tr("Save"))
        alert.addButton(withTitle: tr("Cancel"))
        if targets.contains(where: { $0.placeName != nil }) {
            alert.addButton(withTitle: tr("Remove Location"))
        }
        let field = NSTextField(string: targets.first?.placeName ?? "")
        field.placeholderString = tr("Place name")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows: [(String, PhotoDatabase.StoredLocation)]
        switch response {
        case .alertFirstButtonReturn where !text.isEmpty:
            rows = targets.map { photo in
                let gpsText = photo.placeText.map { " · \($0)" } ?? ""
                return (photo.filePath, .init(latitude: photo.latitude, longitude: photo.longitude, placeName: text, placeText: text + gpsText))
            }
        case .alertThirdButtonReturn:
            rows = targets.map { ($0.filePath, .init(latitude: $0.latitude, longitude: $0.longitude)) }
        default:
            return
        }
        let manual = rows.map { ($0.0, $0.1, true) }
        database.write { $0.saveLocations(manual) }
        applyLocations(rows)
        revealSelection()
    }

    func selectPlace(_ name: String, additive: Bool) {
        var selected = filter.selectedPlaces
        if additive {
            if selected.contains(name) { selected.remove(name) } else { selected.insert(name) }
        } else {
            selected = selected == [name] ? [] : [name]
        }
        filter.selectedPlaces = selected
        revealSelection()
    }

    func openInMaps(_ photo: PhotoItem) {
        var components = URLComponents(string: "http://maps.apple.com/")!
        if let latitude = photo.latitude, let longitude = photo.longitude {
            components.queryItems = [URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
                                     URLQueryItem(name: "q", value: photo.placeName ?? photo.name)]
        } else if let place = photo.placeName {
            components.queryItems = [URLQueryItem(name: "q", value: place)]
        } else {
            return
        }
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Collections

extension PhotoLibrary {
    var activeCollection: PhotoCollection? {
        activeCollectionID.flatMap { id in collections.first { $0.id == id } }
    }

    var targetCollection: PhotoCollection? {
        targetCollectionID.flatMap { id in collections.first { $0.id == id } }
    }

    func reloadCollections() {
        database.waitForWrites()
        collections = database.loadCollections()
    }

    func isInTargetCollection(_ photo: PhotoItem) -> Bool {
        targetCollection?.paths.contains(photo.filePath) ?? false
    }

    /// Shows a collection's photos, wherever they live on disk.
    func openCollection(_ id: Int64) {
        guard let collection = collections.first(where: { $0.id == id }) else { return }
        loadTask?.cancel()
        cancelAnalysis()
        cancelLocationIndexing()
        activeCollectionID = id
        isLoading = true
        scanProgress = tr("Loading “%@”…", collection.name)
        photos = []
        selectedID = nil
        checkedIDs = []
        selectionAnchorID = nil
        filter.clear()
        filter.smartAlbum = .all

        let paths = collection.paths
        loadTask = Task { [weak self] in
            let files = await Task.detached { FolderScanner.files(atPaths: paths) }.value
            guard !Task.isCancelled else { return }
            await self?.loadFiles(files)
            if let self, files.count < paths.count {
                self.flashCopyNote(tr("%@ photos in this collection are missing on disk", paths.count - files.count))
            }
        }
    }

    func returnToFolder() {
        guard activeCollectionID != nil else { return }
        if let folderURL {
            openFolder(folderURL)
        } else {
            loadTask?.cancel()
            activeCollectionID = nil
            photos = []
            selectedID = nil
            checkedIDs = []
        }
    }

    @discardableResult
    func createCollection(named name: String, paths: [String] = []) -> Int64? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = database.createCollection(named: trimmed) else { return nil }
        database.addToCollection(id, paths: paths)
        reloadCollections()
        if targetCollectionID == nil { targetCollectionID = id }
        return id
    }

    /// ⌘N: asks for a name, optionally seeding the collection with the selection.
    func promptNewCollection() {
        let selection = batchPhotos
        guard let result = promptForName(
            title: tr("New Collection"),
            message: tr("Collections only reference photos; files are not copied or moved."),
            defaultName: activeCollection == nil ? (folderURL?.lastPathComponent ?? tr("New Collection")) : tr("New Collection"),
            checkbox: selection.isEmpty ? nil : (selection.count == 1 ? tr("Include 1 selected photo") : tr("Include %@ selected photos", selection.count))
        ) else { return }
        if let id = createCollection(named: result.name, paths: result.checked ? selection.map(\.filePath) : []) {
            flashCopyNote(tr("Created “%@”", collections.first { $0.id == id }?.name ?? result.name))
        }
    }

    func promptRenameCollection(_ id: Int64) {
        guard let collection = collections.first(where: { $0.id == id }),
              let result = promptForName(title: tr("Rename Collection"), message: nil, defaultName: collection.name, checkbox: nil)
        else { return }
        let trimmed = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        database.renameCollection(id, to: trimmed)
        reloadCollections()
    }

    func confirmDeleteCollection(_ id: Int64) {
        guard let collection = collections.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = tr("Delete “%@”?", collection.name)
        alert.informativeText = tr("Only the collection is removed. The %@ photos stay on disk untouched.", collection.paths.count)
        alert.addButton(withTitle: tr("Delete"))
        alert.addButton(withTitle: tr("Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        database.deleteCollection(id)
        if targetCollectionID == id { targetCollectionID = nil }
        let wasActive = activeCollectionID == id
        reloadCollections()
        if wasActive { returnToFolder() }
    }

    func addBatch(to id: Int64) {
        add(paths: batchPhotos.map(\.filePath), to: id)
    }

    func add(paths: [String], to id: Int64) {
        guard !paths.isEmpty, let index = collections.firstIndex(where: { $0.id == id }) else { return }
        database.write { $0.addToCollection(id, paths: paths) }
        var next = collections
        let before = next[index].paths.count
        next[index].paths.formUnion(paths)
        collections = next
        let added = next[index].paths.count - before
        flashCopyNote(added == 0 ? tr("Already in “%@”", next[index].name) : tr("Added %@ to “%@”", added, next[index].name))
    }

    func remove(paths: [String], from id: Int64) {
        guard !paths.isEmpty, let index = collections.firstIndex(where: { $0.id == id }) else { return }
        database.write { $0.removeFromCollection(id, paths: paths) }
        var next = collections
        next[index].paths.subtract(paths)
        collections = next
        if activeCollectionID == id {
            let removed = Set(paths)
            let current = selectedVisibleIndex ?? 0
            let remaining = filteredPhotos.enumerated().filter { !removed.contains($0.element.id) }
            let upcoming = remaining.first { $0.offset > current }?.element ?? remaining.last?.element
            photos = photos.filter { !removed.contains($0.id) }
            checkedIDs = []
            selectedID = upcoming?.id
            if let upcoming { checkedIDs = [upcoming.id] }
        }
        flashCopyNote(tr("Removed %@ from “%@” (files untouched)", paths.count, next[index].name))
    }

    /// Delete key while viewing a collection.
    func removeBatchFromActiveCollection() {
        guard let id = activeCollectionID else { return }
        remove(paths: batchPhotos.map(\.filePath), from: id)
    }

    /// B: Lightroom's "Add to Target Collection" — toggles membership for the selection.
    func toggleTargetCollection() {
        let targets = batchPhotos
        guard !targets.isEmpty else { return }
        if targetCollection == nil {
            targetCollectionID = createCollection(named: tr("Quick Collection"))
        }
        guard let target = targetCollection else { return }
        let paths = targets.map(\.filePath)
        if paths.allSatisfy(target.paths.contains) {
            remove(paths: paths, from: target.id)
        } else {
            add(paths: paths, to: target.id)
        }
    }

    func setTargetCollection(_ id: Int64) {
        targetCollectionID = id
        if let name = targetCollection?.name { flashCopyNote(tr("Target collection: “%@” (B)", name)) }
    }

    func showTargetCollection() {
        if let id = targetCollectionID {
            openCollection(id)
        } else {
            flashCopyNote(tr("No target collection yet — press B to start one"))
        }
    }

    /// Turns an automatic group (in the current view) into a regular collection.
    func saveCategoryAsCollection(_ category: PhotoCategory) {
        let paths = photos.filter { $0.categories.contains(category) }.map(\.filePath)
        guard !paths.isEmpty else { return }
        let base = folderURL.map { "\($0.lastPathComponent) · " } ?? ""
        if let id = createCollection(named: base + category.title, paths: paths) {
            flashCopyNote(tr("Saved %@ photos to “%@”", paths.count, collections.first { $0.id == id }?.name ?? category.title))
        }
    }

    /// Drops onto a collection: dragging one photo of a multi-selection brings the whole selection;
    /// image files from Finder are accepted as well.
    func handleDrop(_ urls: [URL], onto id: Int64) -> Bool {
        let paths = urls.map(\.path)
        if checkedIDs.count > 1, paths.contains(where: checkedIDs.contains) {
            addBatch(to: id)
            return true
        }
        let images = urls.filter { ImageFormats.supportedExtensions.contains($0.pathExtension.lowercased()) }
        guard !images.isEmpty else { return false }
        add(paths: images.map(\.path), to: id)
        return true
    }

    private func promptForName(title: String, message: String?, defaultName: String, checkbox: String?) -> (name: String, checked: Bool)? {
        let alert = NSAlert()
        alert.messageText = title
        if let message { alert.informativeText = message }
        alert.addButton(withTitle: tr("OK"))
        alert.addButton(withTitle: tr("Cancel"))

        let field = NSTextField(string: defaultName)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        var toggle: NSButton?
        if let checkbox {
            let button = NSButton(checkboxWithTitle: checkbox, target: nil, action: nil)
            button.state = .on
            toggle = button
            let stack = NSStackView(views: [field, button])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            stack.frame = NSRect(x: 0, y: 0, width: 280, height: 54)
            alert.accessoryView = stack
        } else {
            alert.accessoryView = field
        }
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return (name, toggle?.state == .on)
    }
}
