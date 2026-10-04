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
        let known = photos.map { ($0.id, $0.url, $0.fileModificationDate) }
        Task { [weak self] in
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
            guard let self, !changed.isEmpty, !self.isLoading else { return }
            var next = self.photos
            var refreshed: [PhotoItem] = []
            for (id, date) in changed {
                guard let index = self.photoIndex[id] else { continue }
                next[index] = MetadataReader.read(into: next[index], modificationDate: date)
                refreshed.append(next[index])
            }
            guard !refreshed.isEmpty else { return }
            self.photos = next
            let rows = refreshed
            self.database.write { $0.saveMany(rows) }
        }
    }
}
