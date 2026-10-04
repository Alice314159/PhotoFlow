import Foundation

/// Security-scoped bookmarks for folders that collections may reach outside the last Open Folder.
enum FolderAccessStore {
    static func remember(_ url: URL) {
        let directory = url.hasDirectoryPath ? url.standardizedFileURL : url.deletingLastPathComponent().standardizedFileURL
        guard let data = try? directory.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        var store = load()
        store[directory.path] = data
        UserDefaults.standard.set(store, forKey: Preferences.Key.folderAccessBookmarks)
    }

    /// Starts access for every stored folder. Caller must `stopAccessingSecurityScopedResource` later.
    static func beginAccess() -> [URL] {
        var live: [URL] = []
        var store = load()
        var staleKeys: [String] = []
        for (path, data) in store {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                staleKeys.append(path)
                continue
            }
            if isStale, let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                store[path] = fresh
            }
            if url.startAccessingSecurityScopedResource() {
                live.append(url)
            }
        }
        for key in staleKeys { store.removeValue(forKey: key) }
        UserDefaults.standard.set(store, forKey: Preferences.Key.folderAccessBookmarks)
        return live
    }

    private static func load() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: Preferences.Key.folderAccessBookmarks) as? [String: Data] ?? [:]
    }
}
