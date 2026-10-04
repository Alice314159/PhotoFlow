import SwiftUI
struct FilterPanelView: View, Equatable {
    let library: PhotoLibrary
    @ObservedObject var filters: LibraryFilters

    private var gearQuery = State(initialValue: "")
    private var expandedBrands = State(initialValue: Set<String>())
    private var showAllBrands = State(initialValue: false)
    private var showAllLenses = State(initialValue: false)

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.library === rhs.library && lhs.filters === rhs.filters
    }

    init(library: PhotoLibrary) {
        self.library = library
        _filters = ObservedObject(wrappedValue: library.filters)
    }

    private var snap: LibraryFilters.Snapshot { filters.snapshot }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataGroup
                    exposureGroup
                    marksGroup
                }
                .padding(14)
            }

            Divider()
            FilterStatusBar(library: library, searchBox: library.searchBox, snap: snap)
        }
    }

    private var metadataGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            if snap.cameraFacets.count + snap.lensFacets.count > 4 {
                gearSearchField
            }
            if !snap.filter.selectedCategories.isEmpty || !snap.filter.selectedPlaces.isEmpty {
                sidebarSelectionSection
            }
            if snap.kindFacets.count > 1 {
                fileTypeSection
            }
            cameraSection
            lensSection
        }
    }

    /// Groups and places are chosen in the sidebar; this only shows that they are narrowing the results.
    private var sidebarSelectionSection: some View {
        let categories = PhotoCategory.allCases.filter { snap.filter.selectedCategories.contains($0) }
        let places = snap.filter.selectedPlaces.sorted()
        return FilterSection(tr("From Sidebar")) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(categories) { category in
                    removableChip(category.title, systemImage: category.systemImage) {
                        toggleSet(\.selectedCategories, category)
                    }
                }
                ForEach(places, id: \.self) { place in
                    removableChip(place, systemImage: "mappin.and.ellipse") {
                        toggleSet(\.selectedPlaces, place)
                    }
                }
            }
        } accessory: {
            clearLink {
                var next = library.filter
                next.selectedCategories = []
                next.selectedPlaces = []
                library.filter = next
            }
        }
    }

    private func removableChip(_ title: String, systemImage: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 9))
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 6)
            .frame(minHeight: 20)
            .background(snap.skin.palette.accent.opacity(0.22), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tr("Remove this filter"))
    }

    private var fileTypeSection: some View {
        let selected = snap.filter.selectedKinds
        return FilterSection(tr("File Type")) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(snap.kindFacets) { kind in
                    FacetRow(
                        title: kind.name,
                        count: kind.count,
                        state: selected.contains(kind.name) ? .on : .off,
                        action: { toggleSet(\.selectedKinds, kind.name) }
                    )
                }
            }
        } accessory: {
            if !selected.isEmpty {
                clearLink { toggleAll(\.selectedKinds) }
            }
        }
    }

    // MARK: - Camera / lens facets

    private var gearSearchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField(tr("Find camera or lens"), text: gearQuery.projectedValue)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !gearQuery.wrappedValue.isEmpty {
                Button {
                    gearQuery.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
    }

    private var query: String {
        gearQuery.wrappedValue.trimmingCharacters(in: .whitespaces)
    }

    private var cameraSection: some View {
        let filter = snap.filter
        let all = snap.cameraFacets
        let matching = query.isEmpty ? all : all.filter { facet in
            facet.brand.localizedCaseInsensitiveContains(query)
                || facet.models.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
        let limit = 5
        let shown = query.isEmpty && !showAllBrands.wrappedValue
            ? matching.enumerated().filter { index, facet in
                index < limit || filter.selectedBrands.contains(facet.brand)
                    || facet.models.contains { filter.selectedCameras.contains($0.name) }
            }.map(\.element)
            : matching

        return FilterSection(tr("Camera")) {
            if all.isEmpty {
                emptyText(tr("No camera metadata"))
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(shown) { facet in
                        brandRows(facet)
                    }
                    if query.isEmpty, matching.count > limit {
                        moreButton(showAll: showAllBrands, title: tr("Show all %@ brands", matching.count))
                    }
                    if shown.isEmpty {
                        emptyText(tr("No match"))
                    }
                }
            }
        } accessory: {
            if !filter.selectedBrands.isEmpty || !filter.selectedCameras.isEmpty {
                clearLink {
                    var next = library.filter
                    next.selectedBrands = []
                    next.selectedCameras = []
                    library.filter = next
                }
            }
        }
    }

    @ViewBuilder
    private func brandRows(_ facet: CameraFacet) -> some View {
        let expandable = facet.models.count > 1
        let expanded = expandable && (expandedBrands.wrappedValue.contains(facet.brand) || !query.isEmpty)

        FacetRow(
            title: facet.brand,
            subtitle: expandable ? nil : facet.models.first?.name,
            count: facet.count,
            state: brandState(facet),
            disclosure: expandable ? expanded : nil,
            onDisclose: {
                var next = expandedBrands.wrappedValue
                if next.contains(facet.brand) { next.remove(facet.brand) } else { next.insert(facet.brand) }
                expandedBrands.wrappedValue = next
            },
            action: { toggleBrand(facet) }
        )

        if expanded {
            let models = query.isEmpty || facet.brand.localizedCaseInsensitiveContains(query)
                ? facet.models
                : facet.models.filter { $0.name.localizedCaseInsensitiveContains(query) }
            ForEach(models) { model in
                FacetRow(
                    title: model.name,
                    count: model.count,
                    state: snap.filter.selectedBrands.contains(facet.brand)
                        || snap.filter.selectedCameras.contains(model.name) ? .on : .off,
                    indent: 22,
                    action: { toggleModel(model.name, of: facet) }
                )
            }
        }
    }

    private var lensSection: some View {
        let all = snap.lensFacets
        let matching = query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let limit = 6
        let selected = snap.filter.selectedLenses
        let shown = query.isEmpty && !showAllLenses.wrappedValue
            ? matching.enumerated().filter { $0.offset < limit || selected.contains($0.element.name) }.map(\.element)
            : matching

        return FilterSection(tr("Lens")) {
            if all.isEmpty {
                emptyText(tr("No lens metadata"))
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(shown) { lens in
                        FacetRow(
                            title: lens.name,
                            count: lens.count,
                            state: selected.contains(lens.name) ? .on : .off,
                            action: { toggleSet(\.selectedLenses, lens.name) }
                        )
                    }
                    if query.isEmpty, matching.count > limit {
                        moreButton(showAll: showAllLenses, title: tr("Show all %@ lenses", matching.count))
                    }
                    if shown.isEmpty {
                        emptyText(tr("No match"))
                    }
                }
            }
        } accessory: {
            if !selected.isEmpty {
                clearLink { toggleAll(\.selectedLenses) }
            }
        }
    }

    private func brandState(_ facet: CameraFacet) -> FacetRow.CheckState {
        if snap.filter.selectedBrands.contains(facet.brand) { return .on }
        let picked = facet.models.filter { snap.filter.selectedCameras.contains($0.name) }.count
        if picked == 0 { return .off }
        return picked == facet.models.count ? .on : .mixed
    }

    private func toggleBrand(_ facet: CameraFacet) {
        var next = library.filter
        let modelNames = Set(facet.models.map(\.name))
        if brandState(facet) == .on {
            next.selectedBrands.remove(facet.brand)
            next.selectedCameras.subtract(modelNames)
        } else {
            next.selectedBrands.insert(facet.brand)
            next.selectedCameras.subtract(modelNames)
        }
        library.filter = next
    }

    private func toggleModel(_ model: String, of facet: CameraFacet) {
        var next = library.filter
        let modelNames = Set(facet.models.map(\.name))
        if next.selectedBrands.contains(facet.brand) {
            // Unchecking one body of a fully-checked brand keeps the others.
            next.selectedBrands.remove(facet.brand)
            next.selectedCameras.formUnion(modelNames.subtracting([model]))
        } else if next.selectedCameras.contains(model) {
            next.selectedCameras.remove(model)
        } else {
            next.selectedCameras.insert(model)
            if modelNames.isSubset(of: next.selectedCameras) {
                next.selectedCameras.subtract(modelNames)
                next.selectedBrands.insert(facet.brand)
            }
        }
        library.filter = next
    }

    private func moreButton(showAll: State<Bool>, title: String) -> some View {
        Button {
            showAll.wrappedValue.toggle()
        } label: {
            Text(showAll.wrappedValue ? tr("Show fewer") : title)
                .font(.system(size: 11))
                .foregroundStyle(snap.skin.palette.accent)
                .padding(.leading, 22)
                .padding(.top, 3)
        }
        .buttonStyle(.plain)
    }

    private func clearLink(_ action: @escaping () -> Void) -> some View {
        Button(tr("Clear"), action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(snap.skin.palette.accent)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func toggleAll<T: Hashable>(_ keyPath: WritableKeyPath<FilterState, Set<T>>) {
        var next = library.filter
        next[keyPath: keyPath] = []
        library.filter = next
    }

    private var exposureGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            RangeFilterRow(
                title: tr("Shutter"),
                range: snap.bounds.shutter,
                selection: rangeBinding(\.shutter),
                usesLog: true,
                format: ExposureFormat.shutterLabel
            )
            RangeFilterRow(
                title: tr("Aperture"),
                range: snap.bounds.aperture,
                selection: rangeBinding(\.aperture),
                format: ExposureFormat.apertureLabel
            )
            RangeFilterRow(
                title: tr("ISO"),
                range: snap.bounds.iso,
                selection: rangeBinding(\.iso),
                usesLog: true,
                format: { "\(Int($0.rounded()))" }
            )
            RangeFilterRow(
                title: tr("Focal Length"),
                range: snap.bounds.focalLength,
                selection: rangeBinding(\.focalLength),
                format: ExposureFormat.focalLabel
            )
        }
    }

    private var marksGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            FilterSection(tr("Rating")) {
                HStack(spacing: 8) {
                    RatingStarsView(
                        rating: snap.filter.minimumRating,
                        size: 15,
                        interactive: true
                    ) { value in
                        library.filter.minimumRating = snap.filter.minimumRating == value ? 0 : value
                        library.filter.smartAlbum = library.filter.minimumRating == 0 ? .all : .rating(library.filter.minimumRating)
                    }
                    Text(snap.filter.minimumRating == 0 ? tr("Any") : "\(snap.filter.minimumRating)+")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            FilterSection(tr("Color")) {
                HStack(spacing: 8) {
                    ForEach(ColorLabel.assigned) { label in
                        let selected = snap.filter.selectedColors.contains(label)
                        Button {
                            toggleSet(\.selectedColors, label)
                        } label: {
                            ColorDot(label: label, isSelected: selected, size: 16)
                        }
                        .buttonStyle(.plain)
                        .help(snap.colorNames.name(for: label))
                    }
                }
            }

            FilterSection(tr("Pick")) {
                HStack(spacing: 6) {
                    ForEach([PickStatus.picked, .rejected, .none], id: \.self) { status in
                        FilterChip(
                            title: status.title,
                            systemImage: status.systemImage,
                            selected: snap.filter.selectedPicks.contains(status)
                        ) {
                            toggleSet(\.selectedPicks, status)
                        }
                    }
                }
            }
        }
    }

    private func rangeBinding(_ keyPath: WritableKeyPath<FilterState, ClosedRange<Double>?>) -> Binding<ClosedRange<Double>?> {
        Binding(
            get: { library.filter[keyPath: keyPath] },
            set: { library.filter[keyPath: keyPath] = $0 }
        )
    }

    private func toggleSet<T: Hashable>(_ keyPath: WritableKeyPath<FilterState, Set<T>>, _ value: T) {
        var next = library.filter
        if next[keyPath: keyPath].contains(value) {
            next[keyPath: keyPath].remove(value)
        } else {
            next[keyPath: keyPath].insert(value)
        }
        library.filter = next
    }
}

/// Footer only. Listens to the search box so Clear enables while typing, without rebuilding facets.
private struct FilterStatusBar: View {
    let library: PhotoLibrary
    @ObservedObject var searchBox: SearchBox
    let snap: LibraryFilters.Snapshot

    var body: some View {
        let searchActive = !searchBox.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let active = snap.filter.isActive || searchActive
        HStack {
            Text(active
                 ? tr("%@ shown", snap.visibleCount)
                 : tr("%@ photos", snap.photoCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(tr("Clear")) {
                library.clearFilters()
            }
            .disabled(!active)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
