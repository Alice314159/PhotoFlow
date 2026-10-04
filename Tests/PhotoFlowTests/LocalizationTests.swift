import Foundation
import Testing
@testable import PhotoFlow

/// `L10n.language` is global, so these run one at a time.
@Suite("Localization", .serialized)
struct LocalizationTests {
    /// Keys whose Chinese text is identical, so they are deliberately absent from the table.
    static let sameInBothLanguages: Set<String> = [
        "P", "U", "X", "RAW", "ISO", "PhotoFlow", "%@  B", "%@ ppi", "ISO %@", "JPEG %@%", "RAW · %@",
    ]
    /// Translated through a variable (`tr(name)`), so the source scan can't see them.
    static let dynamicKeys: Set<String> = [
        "Red", "Yellow", "Green", "Blue", "Purple", "Unknown camera", "Unknown lens",
    ]

    @Test func substitutesInOrderAndByPosition() {
        let saved = L10n.language
        defer { L10n.language = saved }

        L10n.language = .english
        #expect(tr("Analyzing %@ / %@", 3, 10) == "Analyzing 3 / 10")

        L10n.language = .chinese
        #expect(tr("Analyzing %@ / %@", 3, 10) == "正在分析 3 / 10")
        #expect(tr("Removed %@ from “%@” (files untouched)", 4, "旅行") == "已从“旅行”中移除 4 张（文件未改动）")
        #expect(tr("Not a key") == "Not a key")
    }

    @Test func categoryTitlesFollowLanguage() {
        let saved = L10n.language
        defer { L10n.language = saved }
        L10n.language = .chinese
        #expect(PhotoCategory.people.title == "人物")
        L10n.language = .english
        #expect(PhotoCategory.people.title == "People")
    }

    /// Every `tr("…")` in the app has a Chinese translation, and the table has no leftovers.
    @Test func everyKeyIsTranslated() throws {
        let used = try Self.keysInSources()
        let table = Set(L10n.chinese.keys)

        let missing = used.subtracting(table).subtracting(Self.sameInBothLanguages)
        #expect(missing.isEmpty, "Missing Chinese for: \(missing.sorted())")

        let unused = table.subtracting(used).subtracting(Self.dynamicKeys)
        #expect(unused.isEmpty, "Unused translations: \(unused.sorted())")
    }

    private static func keysInSources() throws -> Set<String> {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folders = ["Models", "Services", "ViewModels", "Views"]
        var files = [root.appendingPathComponent("PhotoFlowApp.swift")]
        for folder in folders {
            let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "swift", url.lastPathComponent != "Localization+Chinese.swift" { files.append(url) }
            }
        }
        // tr("…") calls, plus keys handed to a view that calls tr() itself.
        let pattern = try NSRegularExpression(pattern: #"(?:\btr\(|\bkey: )"((?:[^"\\]|\\.)*)""#)
        var keys = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                keys.insert(text[range].replacingOccurrences(of: #"\\"#, with: "\\").replacingOccurrences(of: #"\""#, with: "\""))
            }
        }
        return keys
    }
}
