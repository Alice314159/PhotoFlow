import AppKit

/// Ratings, color labels, and flags, with undo. Marks live in PhotoFlow's database, never in the files.
extension PhotoLibrary {
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

    private func update(_ id: String, mutate: (inout PhotoItem) -> Void) {
        guard let index = photoIndex[id] else { return }
        var next = photos
        recordUndo([next[index]])
        mutate(&next[index])
        markOnlyChange = [id]
        photos = next
        let photo = next[index]
        database.write { $0.save(photo) }
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
        markOnlyChange = changed.map(\.id)
        photos = next
        let rows = changed
        database.write { $0.saveMany(rows) }
        revealSelection()
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
        markOnlyChange = changed.map(\.id)
        photos = next
        // Save the current rows with restored marks, not the old snapshot (which may be stale or from another folder).
        let rows = changed
        database.write { $0.saveMany(rows) }
        revealSelection()
        return replaced
    }
}
