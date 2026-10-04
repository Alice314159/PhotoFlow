import Foundation

/// Every UserDefaults key PhotoFlow uses. Changing a value here orphans the user's saved setting.
enum Preferences {
    enum Key {
        static let language = "appLanguage"
        static let skin = "appSkin"
        static let autoAdvanceOnPick = "autoAdvanceOnPick"
        static let autoAnalyze = "autoAnalyzeContent"
        static let lookUpPlaces = "lookUpPlaces"
        static let showTopBar = "showTopBar"
        static let panelVisibility = "panelVisibility"
        static let collapsedSidebarSections = "collapsedSidebarSections"
        static let gridThumbnailSize = "gridThumbnailSize"
        static let exportSettings = "exportSettings"
        static let colorLabelNames = "colorLabelNames"
        static let targetCollectionID = "targetCollectionID"
        static let lastFolderBookmark = "lastFolderBookmark"
        static let lastFolderPath = "lastFolderPath"
        static let folderAccessBookmarks = "folderAccessBookmarks"
        /// AppKit's own key; read at launch for the menus it builds itself.
        static let appleLanguages = "AppleLanguages"
    }

    /// A stored Bool, or `fallback` if the user never changed it.
    static func bool(_ key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? fallback : UserDefaults.standard.bool(forKey: key)
    }
}
