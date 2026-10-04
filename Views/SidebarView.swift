import SwiftUI

struct SidebarView: View, Equatable {
    let library: PhotoLibrary
    @ObservedObject var lists: LibraryLists
    private var showAllPlaces = State(initialValue: false)
    private var showAllGroups = State(initialValue: false)
    private var renamingColor = State<ColorLabel?>(initialValue: nil)

    private static let groupLimit = 6
    private static let placeLimit = 5

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.library === rhs.library && lhs.lists === rhs.lists
    }

    private var snap: LibraryLists.Snapshot { lists.snapshot }

    init(library: PhotoLibrary) {
        self.library = library
        _lists = ObservedObject(wrappedValue: library.lists)
    }

    var body: some View {
        List {
            foldersSection
            smartSection
            collectionsSection
            autoGroupsSection
            placesSection

            if snap.isLoading {
                Section {
                    ProgressView(snap.scanProgress)
                        .controlSize(.small)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(snap.skin.palette.panel)
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
    }

    private func expanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !snap.collapsed.contains(id) },
            set: { isExpanded in
                var sections = library.collapsedSidebarSections
                if isExpanded { sections.remove(id) } else { sections.insert(id) }
                library.collapsedSidebarSections = sections
            }
        )
    }

    // MARK: - Folders

    private var foldersSection: some View {
        Section(isExpanded: expanded("folders")) {
            if let name = snap.folderName {
                Button {
                    library.returnToFolder()
                } label: {
                    Label(name, systemImage: "folder.fill")
                        .fontWeight(snap.activeCollectionID == nil ? .semibold : .regular)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help(snap.activeCollectionID == nil ? (snap.folderPath ?? name) : tr("Back to this folder"))
            } else {
                Button {
                    library.chooseFolder()
                } label: {
                    Label(tr("Open Folder…"), systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text(tr("Folders"))
                Spacer()
                Menu {
                    Button(tr("Open Folder…")) { library.chooseFolder() }
                    Divider()
                    ForEach(quickFolders, id: \.path) { folder in
                        Button(folder.lastPathComponent) { library.openFolder(folder) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(tr("Open a folder (⌘O)"))
            }
        }
    }

    // MARK: - Smart

    private var smartSection: some View {
        Section(isExpanded: expanded("smart")) {
            smartRow(tr("All Photos"), album: .all, systemImage: "photo.on.rectangle")
            smartRow("★★★★★", album: .rating(5))
            smartRow("★★★★+", album: .rating(4))
            smartRow(tr("Picked"), album: .pick(.picked), systemImage: "flag.fill")
            smartRow(tr("Rejected"), album: .pick(.rejected), systemImage: "xmark.circle")
            colorRow
        } header: {
            Text(tr("Smart"))
        }
    }

    /// Color labels as named chips, two or three per line, so their meaning is visible without hovering.
    private var colorRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 4)], alignment: .leading, spacing: 4) {
            ForEach(ColorLabel.assigned) { label in
                colorChip(label)
            }
        }
        .padding(.vertical, 2)
    }

    private func colorChip(_ label: ColorLabel) -> some View {
        let isOn = snap.smartAlbum == .color(label)
        return Button {
            library.applySmartAlbum(.color(label))
        } label: {
            HStack(spacing: 4) {
                ColorDot(label: label, size: 9)
                Text(snap.colorNames.name(for: label))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Text("\(snap.markCounts.colors[label] ?? 0)")
                    .foregroundStyle(isOn ? Color.white.opacity(0.85) : .secondary)
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: isOn ? .semibold : .regular))
            .foregroundStyle(isOn ? Color.white : .primary)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.5)), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tr("Right-click to rename"))
        .contextMenu {
            Button(tr("Rename…")) { renamingColor.wrappedValue = label }
            if snap.colorNames.isCustom(label) {
                Button(tr("Reset Name")) { library.colorNames.setName("", for: label) }
            }
        }
        .popover(isPresented: Binding(
            get: { renamingColor.wrappedValue == label },
            set: { if !$0 { renamingColor.wrappedValue = nil } }
        ), arrowEdge: .trailing) {
            ColorLabelNameEditor(library: library, label: label) { renamingColor.wrappedValue = nil }
        }
    }

    // MARK: - Collections

    private var collectionsSection: some View {
        Section(isExpanded: expanded("collections")) {
            if snap.collections.isEmpty {
                Text(tr("⌘N to create, or press B to add to a Quick Collection. Drag photos onto a collection."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(snap.collections) { collection in
                collectionRow(collection)
            }
        } header: {
            HStack {
                Text(tr("Collections"))
                Spacer()
                Button {
                    library.promptNewCollection()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(tr("New collection (⌘N)"))
            }
        }
    }

    private func collectionRow(_ collection: PhotoCollection) -> some View {
        let isActive = snap.activeCollectionID == collection.id
        let isTarget = snap.targetCollectionID == collection.id
        return Button {
            library.openCollection(collection.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isActive ? "rectangle.stack.fill" : "rectangle.stack")
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(width: 16)
                Text(collection.name)
                    .lineLimit(1)
                if isTarget {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                        .help(tr("Target collection — B adds to it"))
                }
                Spacer()
                Text("\(collection.paths.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .fontWeight(isActive ? .semibold : .regular)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            library.handleDrop(urls, onto: collection.id)
        }
        .contextMenu {
            Button(tr("Open")) { library.openCollection(collection.id) }
            Button(tr("Add Selected Photos")) { library.addBatch(to: collection.id) }
                .disabled(library.batchPhotos.isEmpty)
            Button(isTarget ? tr("Target Collection ✓") : tr("Set as Target Collection (B)")) {
                library.setTargetCollection(collection.id)
            }
            .disabled(isTarget)
            Divider()
            Button(tr("Rename…")) { library.promptRenameCollection(collection.id) }
            Button(tr("Delete Collection…")) { library.confirmDeleteCollection(collection.id) }
        }
    }

    // MARK: - Automatic groups

    /// Groups ordered by size; selected groups always stay visible even when folded.
    private var visibleGroups: (shown: [PhotoCategory], hidden: Int) {
        let all = PhotoCategory.allCases
            .filter { (snap.categoryCounts[$0] ?? 0) > 0 }
            .sorted { (snap.categoryCounts[$0] ?? 0) > (snap.categoryCounts[$1] ?? 0) }
        guard !showAllGroups.wrappedValue, all.count > Self.groupLimit + 1 else { return (all, 0) }
        let top = all.prefix(Self.groupLimit)
        let shown = all.filter { top.contains($0) || snap.selectedCategories.contains($0) }
        return (shown, all.count - shown.count)
    }

    private var autoGroupsSection: some View {
        Section(isExpanded: expanded("groups")) {
            if snap.analysisTotal > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ProgressCount(progress: library.progress, key: "Analyzing %@ / %@", done: \.analysisDone, total: snap.analysisTotal)
                        Spacer()
                        Button {
                            library.cancelAnalysis()
                        } label: {
                            Image(systemName: "stop.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(tr("Stop analyzing"))
                    }
                    ProgressBar(progress: library.progress, done: \.analysisDone, total: snap.analysisTotal)
                }
            } else if snap.photoCount > 0, snap.categoryCounts.isEmpty, !snap.isLoading {
                Button {
                    library.startAnalysis()
                } label: {
                    Label(tr("Group by Content"), systemImage: "sparkles")
                }
                .buttonStyle(.plain)
                .help(tr("Detect people, sports, pets, nature… on this Mac. Nothing is uploaded."))
            }

            let groups = visibleGroups
            if !groups.shown.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(groups.shown) { category in
                        categoryChip(category)
                    }
                    if groups.hidden > 0 || showAllGroups.wrappedValue {
                        Button {
                            showAllGroups.wrappedValue.toggle()
                        } label: {
                            Text(showAllGroups.wrappedValue ? tr("Less") : tr("More +%@", groups.hidden))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 22)
                                .background(.quaternary.opacity(0.5), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack {
                Text(tr("Auto Groups"))
                Spacer()
                if !snap.selectedCategories.isEmpty {
                    Button(tr("Clear")) {
                        library.filter.selectedCategories = []
                        library.revealSelection()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
    }

    private func categoryChip(_ category: PhotoCategory) -> some View {
        let isOn = snap.selectedCategories.contains(category)
        return Button {
            library.selectCategory(category, additive: NSEvent.modifierFlags.contains(.command))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 10))
                    .foregroundStyle(isOn ? Color.white : category.tint)
                Text(category.title)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(snap.categoryCounts[category] ?? 0)")
                    .foregroundStyle(isOn ? Color.white.opacity(0.85) : .secondary)
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: isOn ? .semibold : .regular))
            .foregroundStyle(isOn ? Color.white : .primary)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.5)), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tr("⌘-click to combine groups"))
        .contextMenu {
            Button(isOn ? tr("Hide Group") : tr("Show Only This Group")) { library.selectCategory(category, additive: false) }
            Button(tr("Save as Collection")) { library.saveCategoryAsCollection(category) }
        }
    }

    // MARK: - Places

    @ViewBuilder
    private var placesSection: some View {
        if !snap.placeCounts.isEmpty || snap.placeLookupTotal > 0 {
            Section(isExpanded: expanded("places")) {
                if snap.placeLookupTotal > 0 {
                    HStack {
                        ProgressView().controlSize(.mini)
                        ProgressCount(progress: library.progress, key: "Naming places %@ / %@", done: \.placeLookupDone, total: snap.placeLookupTotal)
                    }
                }
                let limit = showAllPlaces.wrappedValue ? Int.max : Self.placeLimit
                ForEach(snap.placeCounts.prefix(limit)) { place in
                    placeRow(place)
                }
                if snap.placeCounts.count > Self.placeLimit {
                    Button(showAllPlaces.wrappedValue ? tr("Show fewer") : tr("Show all %@", snap.placeCounts.count)) {
                        showAllPlaces.wrappedValue.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text(tr("Places"))
                    Spacer()
                    if !snap.selectedPlaces.isEmpty {
                        Button(tr("Clear")) {
                            library.filter.selectedPlaces = []
                            library.revealSelection()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func placeRow(_ place: FacetCount) -> some View {
        let isOn = snap.selectedPlaces.contains(place.name)
        return Button {
            library.selectPlace(place.name, additive: NSEvent.modifierFlags.contains(.command))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.red.opacity(0.8))
                    .frame(width: 16)
                Text(place.name)
                    .lineLimit(1)
                Spacer()
                Text("\(place.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .fontWeight(isOn ? .semibold : .regular)
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
            .background(isOn ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tr("⌘-click to combine places"))
    }

    private var quickFolders: [URL] {
        let names: [FileManager.SearchPathDirectory] = [.picturesDirectory, .downloadsDirectory, .desktopDirectory]
        return names.compactMap { FileManager.default.urls(for: $0, in: .userDomainMask).first }
    }

    private func smartRow(_ title: String, album: SmartAlbum, systemImage: String? = nil) -> some View {
        Button {
            library.applySmartAlbum(album)
        } label: {
            HStack {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
                Spacer()
                Text(countText(for: album))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .fontWeight(snap.smartAlbum == album ? .semibold : .regular)
        }
        .buttonStyle(.plain)
    }

    private func countText(for album: SmartAlbum) -> String {
        switch album {
        case .all: "\(snap.photoCount)"
        case .rating(let value): "\(snap.markCounts.atLeast[min(max(value, 0), 5)])"
        case .color(let label): "\(snap.markCounts.colors[label] ?? 0)"
        case .pick(let status): "\(snap.markCounts.picks[status] ?? 0)"
        }
    }
}

/// Reads the fast-changing counter itself, so ticking progress doesn't redraw the sidebar.
private struct ProgressCount: View {
    @ObservedObject var progress: BackgroundProgress
    let key: String
    let done: KeyPath<BackgroundProgress, Int>
    let total: Int

    var body: some View {
        Text(tr(key, progress[keyPath: done], total))
            .font(.caption)
            .monospacedDigit()
    }
}

private struct ProgressBar: View {
    @ObservedObject var progress: BackgroundProgress
    let done: KeyPath<BackgroundProgress, Int>
    let total: Int

    var body: some View {
        ProgressView(value: Double(progress[keyPath: done]), total: Double(max(total, 1)))
            .controlSize(.small)
    }
}
