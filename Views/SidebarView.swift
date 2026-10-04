import SwiftUI

struct SidebarView: View {
    @ObservedObject var library: PhotoLibrary
    private var showAllPlaces = State(initialValue: false)
    private var showAllGroups = State(initialValue: false)

    private static let groupLimit = 6
    private static let placeLimit = 5

    init(library: PhotoLibrary) {
        self.library = library
    }

    var body: some View {
        List {
            foldersSection
            smartSection
            collectionsSection
            autoGroupsSection
            placesSection

            if library.isLoading {
                Section {
                    ProgressView(library.scanProgress)
                        .controlSize(.small)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(library.skin.palette.panel)
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
    }

    private func expanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !library.collapsedSidebarSections.contains(id) },
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
            if let folder = library.folderURL {
                Button {
                    library.returnToFolder()
                } label: {
                    Label(folder.lastPathComponent, systemImage: "folder.fill")
                        .fontWeight(library.activeCollectionID == nil ? .semibold : .regular)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help(library.activeCollectionID == nil ? folder.path : tr("Back to this folder"))
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

    /// All color labels on one line instead of five rows.
    private var colorRow: some View {
        HStack(spacing: 10) {
            ForEach(ColorLabel.assigned) { label in
                Button {
                    library.applySmartAlbum(.color(label))
                } label: {
                    VStack(spacing: 2) {
                        ColorDot(label: label, isSelected: library.filter.smartAlbum == .color(label), size: 12)
                        Text("\(library.colorCount(label))")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(library.colorNames.name(for: label))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Collections

    private var collectionsSection: some View {
        Section(isExpanded: expanded("collections")) {
            if library.collections.isEmpty {
                Text(tr("⌘N to create, or press B to add to a Quick Collection. Drag photos onto a collection."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(library.collections) { collection in
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
        let isActive = library.activeCollectionID == collection.id
        let isTarget = library.targetCollectionID == collection.id
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
            .filter { (library.categoryCounts[$0] ?? 0) > 0 }
            .sorted { (library.categoryCounts[$0] ?? 0) > (library.categoryCounts[$1] ?? 0) }
        guard !showAllGroups.wrappedValue, all.count > Self.groupLimit + 1 else { return (all, 0) }
        let top = all.prefix(Self.groupLimit)
        let shown = all.filter { top.contains($0) || library.filter.selectedCategories.contains($0) }
        return (shown, all.count - shown.count)
    }

    private var autoGroupsSection: some View {
        Section(isExpanded: expanded("groups")) {
            if library.isAnalyzing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tr("Analyzing %@ / %@", library.analysisDone, library.analysisTotal))
                            .font(.caption)
                            .monospacedDigit()
                        Spacer()
                        Button {
                            library.cancelAnalysis()
                        } label: {
                            Image(systemName: "stop.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(tr("Stop analyzing"))
                    }
                    ProgressView(value: Double(library.analysisDone), total: Double(max(library.analysisTotal, 1)))
                        .controlSize(.small)
                }
            } else if !library.photos.isEmpty, library.categoryCounts.isEmpty, !library.isLoading {
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
                if !library.filter.selectedCategories.isEmpty {
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
        let isOn = library.filter.selectedCategories.contains(category)
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
                Text("\(library.categoryCounts[category] ?? 0)")
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
        if !library.placeCounts.isEmpty || library.isLookingUpPlaces {
            Section(isExpanded: expanded("places")) {
                if library.isLookingUpPlaces {
                    HStack {
                        ProgressView().controlSize(.mini)
                        Text(tr("Naming places %@ / %@", library.placeLookupDone, library.placeLookupTotal))
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                let limit = showAllPlaces.wrappedValue ? Int.max : Self.placeLimit
                ForEach(library.placeCounts.prefix(limit)) { place in
                    placeRow(place)
                }
                if library.placeCounts.count > Self.placeLimit {
                    Button(showAllPlaces.wrappedValue ? tr("Show fewer") : tr("Show all %@", library.placeCounts.count)) {
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
                    if !library.filter.selectedPlaces.isEmpty {
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
        let isOn = library.filter.selectedPlaces.contains(place.name)
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
            .fontWeight(library.filter.smartAlbum == album ? .semibold : .regular)
        }
        .buttonStyle(.plain)
    }

    private func countText(for album: SmartAlbum) -> String {
        switch album {
        case .all: "\(library.photos.count)"
        case .rating(let value): "\(library.photos.filter { $0.rating >= value }.count)"
        case .color(let label): "\(library.colorCount(label))"
        case .pick(let status): "\(library.photos.filter { $0.pickStatus == status }.count)"
        }
    }
}
