import SwiftUI

struct TopBarView: View {
    @ObservedObject var library: PhotoLibrary

    var body: some View {
        HStack(spacing: 12) {
            sidebarToggle(
                "sidebar.left",
                isOn: library.showSidebar,
                help: library.showSidebar ? tr("Hide Library (F7)") : tr("Show Library (F7)")
            ) {
                library.showSidebar.toggle()
            }

            Text("PhotoFlow")
                .font(.headline)
                .tracking(0.3)

            if let collection = library.activeCollection {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.stack.fill")
                    Text(collection.name)
                        .lineLimit(1)
                    Button {
                        library.returnToFolder()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(tr("Back to folder"))
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(library.skin.palette.accent.opacity(0.22), in: Capsule())
            }

            searchField

            if library.isExporting {
                ProgressView()
                    .controlSize(.small)
                Text(tr("Exporting…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if library.viewMode == .grid {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 9))
                    Slider(value: $library.gridThumbnailSize, in: PhotoLibrary.gridSizeRange)
                        .controlSize(.mini)
                        .frame(width: 90)
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .help(tr("Thumbnail size (⌘= / ⌘−)"))
            }

            Picker(tr("Sort"), selection: $library.sort) {
                ForEach(PhotoSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help(tr("Sort order"))

            Picker(tr("View"), selection: $library.viewMode) {
                ForEach(LibraryViewMode.allCases) { mode in
                    Image(systemName: mode.systemImage)
                        .tag(mode)
                        .help("\(mode.title) (\(mode == .grid ? "G" : "E"))")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 80)

            Divider().frame(height: 18)

            panelsMenu

            skinMenu

            Button {
                library.showShortcuts = true
            } label: {
                Image(systemName: "keyboard")
            }
            .buttonStyle(.borderless)
            .help(tr("Keyboard shortcuts (⌘/)"))

            Button {
                library.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(tr("Settings (⌘,)"))

            Divider().frame(height: 18)

            sidebarToggle(
                "sidebar.right",
                isOn: library.showFilterPanel,
                badge: library.filter.activeCount,
                help: library.showFilterPanel
                    ? tr("Hide Inspector (F8)")
                    : tr("Show Inspector — Filter (\\ or ⌘F), Info (I)")
            ) {
                library.showFilterPanel.toggle()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(library.skin.palette.chrome)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(tr("Search: 鸟, 风景, 上海, 2024, Sony…"), text: $library.filter.searchText)
                .textFieldStyle(.plain)
                .onSubmit { library.resignTextFocus() }
                .help(tr("Search content (鸟, 狗, 海边, 风景, sunset), places (上海, Yosemite), folder or file names, camera and lens, or dates (2024-10, 2024年10月). Separate words with spaces to narrow down: “鸟 上海”."))
            if !library.filter.searchText.isEmpty {
                Button {
                    library.filter.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(library.skin.palette.search, in: RoundedRectangle(cornerRadius: 6))
        .frame(minWidth: 160, maxWidth: 300)
    }

    /// The same glyph as the panel's own hide button, highlighted while the panel is open.
    private func sidebarToggle(
        _ symbol: String,
        isOn: Bool,
        badge: Int = 0,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(isOn ? library.skin.palette.accent : Color.secondary)
                .frame(width: 26, height: 22)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 12, minHeight: 12)
                            .background(library.skin.palette.accent, in: Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(badge > 0 ? (badge == 1 ? tr("%@ — 1 filter active", help) : tr("%@ — %@ filters active", help, badge)) : help)
    }

    private var skinMenu: some View {
        Menu {
            Picker(tr("Skin"), selection: $library.skin) {
                ForEach(AppSkin.allCases) { skin in
                    Text(skin.title).tag(skin)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button(tr("Next Skin  ⌥⌘K")) { library.cycleSkin() }
            Divider()
            Picker(tr("Language"), selection: $library.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            Divider()
            Button(tr("More in Settings…")) { library.showSettings = true }
        } label: {
            Image(systemName: "paintpalette")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("Skin & Language"))
    }

    private var panelsMenu: some View {
        Menu {
            Toggle(tr("Top Bar  F5"), isOn: $library.showTopBar)
            Toggle(tr("Filmstrip  F6"), isOn: $library.showFilmstrip)
            Toggle(tr("Library  F7"), isOn: $library.showSidebar)
            Toggle(tr("Inspector  F8"), isOn: $library.showFilterPanel)
            Toggle(tr("Info Bar  '"), isOn: $library.showInfoBar)
            Divider()
            Button(tr("Toggle Side Panels  Tab")) { library.toggleSidePanels() }
            Button(tr("Toggle All Panels  ⇧Tab")) { library.toggleEverything() }
            Button(tr("Full-Screen Preview  F")) { library.togglePresentation() }
        } label: {
            Image(systemName: "rectangle.3.group")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("Panels"))
    }
}
