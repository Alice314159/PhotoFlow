import AppKit

/// Opening folders and reading photo metadata into the library.
extension PhotoLibrary {
    func openFolder(_ url: URL) {
        loadTask?.cancel()
        cancelAnalysis()
        cancelLocationIndexing()
        activeCollectionID = nil
        stopAccessingFolder()

        let accessed = url.startAccessingSecurityScopedResource()
        if accessed { folderAccess = url }
        rememberFolderAccess(url)

        folderURL = url
        persistBookmark(url)
        deferFacetRebuild = false
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
            database.waitForWrites()
            return (database.annotations(for: paths), database.analyses(for: paths), database.locations(for: paths))
        }.value
        if Task.isCancelled { return }

        let reader = Task.detached(priority: .userInitiated) { [self] () -> ([PhotoItem], Set<String>)? in
            var items: [PhotoItem] = []
            var dirty: Set<String> = []
            items.reserveCapacity(scanned.count)
            let batch = scanned.count > 2000 ? 400 : 150

            for (index, file) in scanned.enumerated() {
                if Task.isCancelled { return nil }

                let assembled = assemblePhoto(file: file, stored: stored, analyses: analyses, locations: locations)
                items.append(assembled.item)
                if assembled.dirty { dirty.insert(assembled.item.id) }

                if index % batch == 0 || index == scanned.count - 1 {
                    let snapshot = items
                    let progress = tr("Reading %@ / %@", index + 1, scanned.count)
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.deferFacetRebuild = true
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
        guard let (loaded, dirty) = result, !Task.isCancelled else {
            deferFacetRebuild = false
            return
        }

        // Marks set while the folder was still loading live only in `photos`; keep them.
        let items = keepingCurrentMarks(loaded)
        deferFacetRebuild = false
        photos = items
        if !dirty.isEmpty {
            let refreshed = items.filter { dirty.contains($0.id) }
            database.write { $0.saveMany(refreshed) }
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

    /// Photos edited in another app (⌘E opens Preview) get fresh metadata and thumbnails
    /// as soon as PhotoFlow is active again.
    func observeAppActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshChangedFiles() }
        }
    }

    func refreshChangedFiles() {
        guard !isLoading, !photos.isEmpty else { return }
        if let folder = folderURL, activeCollectionID == nil {
            Task { [weak self] in
                await self?.refreshFolderContents(folder)
            }
        } else {
            Task { [weak self] in
                await self?.refreshKnownMtimes()
            }
        }
    }

    /// Re-scan the open folder so Finder add/delete/edit shows up without reopening.
    private func refreshFolderContents(_ folder: URL) async {
        let scanned = await Task.detached(priority: .utility) { [scanner] in
            scanner.scan(folder: folder)
        }.value
        guard folderURL?.path == folder.path, !isLoading, activeCollectionID == nil else { return }

        let diff = FolderDiff.between(known: photos, scanned: scanned)
        guard !diff.isEmpty else { return }
        let added = diff.added
        let removed = diff.removedIDs
        let staleDates = diff.staleDates
        let found = Set(scanned.map(\.url.path))

        var next = photos.filter { found.contains($0.id) }
        var dirty: [PhotoItem] = []
        for (id, date) in staleDates where found.contains(id) {
            guard let index = next.firstIndex(where: { $0.id == id }) else { continue }
            next[index] = MetadataReader.read(into: next[index], modificationDate: date)
            dirty.append(next[index])
        }

        if !added.isEmpty {
            let (hydrated, newDirty) = await hydrate(added)
            next.append(contentsOf: hydrated)
            dirty.append(contentsOf: newDirty)
            next.sort {
                $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
        }

        if !removed.isEmpty {
            let gone = Set(removed)
            checkedIDs.subtract(gone)
            if let selectedID, gone.contains(selectedID) {
                self.selectedID = nil
            }
        }

        photos = next
        if selectedID == nil { revealSelection() }
        if !dirty.isEmpty {
            let rows = dirty
            database.write { $0.saveMany(rows) }
        }
        if !added.isEmpty || !removed.isEmpty {
            bounds = FilterBounds.from(photos: next)
        }
        if !added.isEmpty {
            startLocationIndexing()
            if autoAnalyze { startAnalysis() }
        }
    }

    private func refreshKnownMtimes() async {
        let known = photos.map { ($0.id, $0.url, $0.fileModificationDate) }
        let changed = await Task.detached(priority: .utility) { () -> [String: Date] in
            var result: [String: Date] = [:]
            for (id, url, date) in known {
                guard let current = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                else { continue }
                if let date, abs(date.timeIntervalSince(current)) <= 1 { continue }
                result[id] = current
            }
            return result
        }.value
        guard !changed.isEmpty, !isLoading else { return }
        var next = photos
        var refreshed: [PhotoItem] = []
        for (id, date) in changed {
            guard let index = photoIndex[id] else { continue }
            next[index] = MetadataReader.read(into: next[index], modificationDate: date)
            refreshed.append(next[index])
        }
        guard !refreshed.isEmpty else { return }
        photos = next
        let rows = refreshed
        database.write { $0.saveMany(rows) }
    }

    /// Marks, EXIF, stored groups and places for a small set of newly appeared files.
    private func hydrate(_ scanned: [ScannedFile]) async -> ([PhotoItem], [PhotoItem]) {
        let paths = scanned.map(\.url.path)
        let (stored, analyses, locations) = await Task.detached { [database] in
            database.waitForWrites()
            return (database.annotations(for: paths), database.analyses(for: paths), database.locations(for: paths))
        }.value
        return await Task.detached(priority: .utility) {
            var items: [PhotoItem] = []
            var dirty: [PhotoItem] = []
            items.reserveCapacity(scanned.count)
            for file in scanned {
                let assembled = assemblePhoto(file: file, stored: stored, analyses: analyses, locations: locations)
                items.append(assembled.item)
                if assembled.dirty { dirty.append(assembled.item) }
            }
            return (items, dirty)
        }.value
    }
}

private func assemblePhoto(
    file: ScannedFile,
    stored: [String: PhotoItem],
    analyses: [String: PhotoDatabase.StoredAnalysis],
    locations: [String: PhotoDatabase.StoredLocation]
) -> (item: PhotoItem, dirty: Bool) {
    var item = stored[file.url.path] ?? PhotoItem(filePath: file.url.path)
    item.availability = file.availability
    var dirty = false
    if file.availability == .available {
        if MetadataReader.needsRefresh(existing: stored[file.url.path], modificationDate: file.modificationDate) {
            item = MetadataReader.read(into: item, modificationDate: file.modificationDate)
            item.availability = .available
            dirty = true
        } else {
            item.fileModificationDate = file.modificationDate
        }
        item.fileByteSize = file.fileSize
    }
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
    return (item, dirty)
}
