import AppKit

/// Export, copy, and rename. Exports and copies write new files; rename only changes the filename.
extension PhotoLibrary {
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
        var pathUpdates: [(String, String)] = []

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
                if let index = photoIndex[photo.id] {
                    let oldPath = nextPhotos[index].filePath
                    nextPhotos[index].filePath = unique.path
                    let newPath = unique.path
                    pathUpdates.append((oldPath, newPath))
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
        if !pathUpdates.isEmpty {
            let updates = pathUpdates
            database.write { $0.updatePaths(updates) }
            database.waitForWrites()
        }
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
}
