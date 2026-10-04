import SwiftUI

struct ShortcutsView: View {
    @ObservedObject var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss
    private var query = State(initialValue: "")

    init(library: PhotoLibrary) {
        self.library = library
    }

    struct Shortcut: Identifiable {
        let keys: String
        let action: String
        var id: String { keys + action }
    }

    struct ShortcutGroup: Identifiable {
        let title: String
        let items: [Shortcut]
        var id: String { title }
    }

    /// Computed so the list follows the current interface language.
    static var groups: [ShortcutGroup] { [
        ShortcutGroup(title: tr("Views & Panels"), items: [
            Shortcut(keys: "G", action: tr("Grid")),
            Shortcut(keys: "E  ·  Return", action: tr("Loupe (from grid)")),
            Shortcut(keys: "F", action: tr("Full-screen preview (Esc to exit)")),
            Shortcut(keys: "Tab", action: tr("Toggle side panels")),
            Shortcut(keys: "⇧Tab", action: tr("Toggle all panels")),
            Shortcut(keys: "F5", action: tr("Top bar")),
            Shortcut(keys: "F6", action: tr("Filmstrip")),
            Shortcut(keys: "F7", action: tr("Library panel")),
            Shortcut(keys: "F8", action: tr("Inspector panel")),
            Shortcut(keys: "\\  ·  ⌘F", action: tr("Filter panel")),
            Shortcut(keys: "I", action: tr("Photo info")),
            Shortcut(keys: "'", action: tr("Info bar")),
        ]),
        ShortcutGroup(title: tr("Zoom"), items: [
            Shortcut(keys: "Z  ·  Space", action: tr("Toggle Fit / 1:1")),
            Shortcut(keys: "⌘=  /  ⌘−", action: tr("Zoom in / out (grid: thumbnail size)")),
            Shortcut(keys: "⌘0", action: tr("Fit")),
            Shortcut(keys: "⌘1", action: tr("Actual pixels (100%)")),
            Shortcut(keys: "Scroll  ·  Pinch", action: tr("Zoom at cursor")),
        ]),
        ShortcutGroup(title: tr("Navigate & Select"), items: [
            Shortcut(keys: "←  →", action: tr("Previous / next photo")),
            Shortcut(keys: "↑  ↓", action: tr("Previous / next (loupe)")),
            Shortcut(keys: "Home  /  End", action: tr("First / last photo")),
            Shortcut(keys: "⌘-click  ·  ⇧-click", action: tr("Add to / extend selection")),
            Shortcut(keys: "⌘A", action: tr("Select all")),
            Shortcut(keys: "⌘D", action: tr("Select none")),
            Shortcut(keys: "Esc", action: tr("Keep only the current photo")),
        ]),
        ShortcutGroup(title: tr("Rate, Flag & Label"), items: [
            Shortcut(keys: "1 – 5  ·  0", action: tr("Star rating · clear")),
            Shortcut(keys: "[  /  ]", action: tr("Decrease / increase rating")),
            Shortcut(keys: "P  ·  X  ·  U", action: tr("Pick · Reject · Unflag")),
            Shortcut(keys: "`", action: tr("Toggle pick flag")),
            Shortcut(keys: "6  7  8  9  −", action: tr("Red · Yellow · Green · Blue · Purple")),
            Shortcut(keys: "⇧ + any of the above", action: tr("Apply, then go to next photo")),
            Shortcut(keys: "⌘Z  /  ⇧⌘Z", action: tr("Undo / redo marks")),
        ]),
        ShortcutGroup(title: tr("Collections & Groups"), items: [
            Shortcut(keys: "B", action: tr("Add to / remove from target collection")),
            Shortcut(keys: "⌘N", action: tr("New collection")),
            Shortcut(keys: "⌘B", action: tr("Show target collection")),
            Shortcut(keys: "⌫", action: tr("Remove from collection (files stay)")),
            Shortcut(keys: "Drag", action: tr("Drop photos onto a collection")),
            Shortcut(keys: "⌘-click group", action: tr("Combine auto groups or places")),
            Shortcut(keys: "鸟 上海 2024", action: tr("Search: all words must match")),
        ]),
        ShortcutGroup(title: tr("Files"), items: [
            Shortcut(keys: "⌘O", action: tr("Open Folder…")),
            Shortcut(keys: "⇧⌘E", action: tr("Export…")),
            Shortcut(keys: "⇧⌘S", action: tr("Save As…")),
            Shortcut(keys: "F2", action: tr("Rename…")),
            Shortcut(keys: "⌘C", action: tr("Copy files")),
            Shortcut(keys: "⌘E", action: tr("Edit in Preview")),
            Shortcut(keys: "⌘R", action: tr("Show in Finder")),
            Shortcut(keys: "⌘P", action: tr("Print")),
        ]),
        ShortcutGroup(title: tr("App"), items: [
            Shortcut(keys: "⌥⌘K  /  ⇧⌥⌘K", action: tr("Next / previous skin")),
            Shortcut(keys: "⌘,", action: tr("Settings")),
            Shortcut(keys: "⌘/", action: tr("This list")),
        ]),
    ] }

    private var filteredGroups: [ShortcutGroup] {
        let text = query.wrappedValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return Self.groups }
        return Self.groups.compactMap { group in
            let items = group.items.filter {
                $0.action.lowercased().contains(text) || $0.keys.lowercased().contains(text)
            }
            return items.isEmpty ? nil : ShortcutGroup(title: group.title, items: items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Keyboard Shortcuts"))
                        .font(.title2.weight(.semibold))
                    Text(tr("Modeled on Lightroom Classic and Photoshop."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField(tr("Search"), text: query.projectedValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            .padding(20)

            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 28, alignment: .top),
                                    GridItem(.flexible(), alignment: .top)],
                          alignment: .leading, spacing: 22) {
                    ForEach(filteredGroups) { group in
                        groupView(group)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button(tr("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 680, height: 560)
        .background(library.skin.palette.panel)
    }

    private func groupView(_ group: ShortcutGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(library.skin.palette.accent)
                .padding(.bottom, 2)
            ForEach(group.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.keys)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                        .frame(width: 130, alignment: .leading)
                    Text(item.action)
                        .font(.callout)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
