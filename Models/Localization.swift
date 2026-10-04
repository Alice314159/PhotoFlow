import Foundation

/// Interface language. English strings are the keys; Chinese lives in `L10n.chinese`.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case chinese

    var id: String { rawValue }

    /// Shown in its own language so it is readable whichever language is active.
    var title: String {
        switch self {
        case .system: tr("Follow System")
        case .english: "English"
        case .chinese: "简体中文"
        }
    }
}

enum L10n {
    /// Read from background tasks too (progress text), so access goes through a lock.
    static var language: AppLanguage {
        get { lock.withLock { storedLanguage } }
        set {
            lock.withLock { storedLanguage = newValue }
            applyToSystemMenus()
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedLanguage: AppLanguage = {
        let stored = UserDefaults.standard.string(forKey: Preferences.Key.language)
        return stored.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }()

    static var isChinese: Bool {
        switch language {
        case .chinese: true
        case .english: false
        case .system: systemLanguage.hasPrefix("zh")
        }
    }

    /// The user's global language; `Locale.preferredLanguages` would include this app's own override.
    private static let systemLanguage: String = {
        let global = CFPreferencesCopyValue(
            "AppleLanguages" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String]
        return global?.first ?? Locale.preferredLanguages.first ?? "en"
    }()

    /// Items AppKit adds itself (Edit, Window, Services…) follow `AppleLanguages`, read at launch.
    private static func applyToSystemMenus() {
        switch language {
        case .system: UserDefaults.standard.removeObject(forKey: Preferences.Key.appleLanguages)
        case .english: UserDefaults.standard.set(["en"], forKey: Preferences.Key.appleLanguages)
        case .chinese: UserDefaults.standard.set(["zh-Hans"], forKey: Preferences.Key.appleLanguages)
        }
    }
}

/// Localizes an English UI string. Each `%@` in the key is replaced, in order, by `args`;
/// a translation that reorders them uses `%1$@`, `%2$@`.
func tr(_ key: String, _ args: Any...) -> String {
    var text = L10n.isChinese ? (L10n.chinese[key] ?? key) : key
    if text.contains("$@") {
        for (index, arg) in args.enumerated() {
            text = text.replacingOccurrences(of: "%\(index + 1)$@", with: "\(arg)")
        }
        return text
    }
    for arg in args {
        guard let range = text.range(of: "%@") else { break }
        text.replaceSubrange(range, with: "\(arg)")
    }
    return text
}
