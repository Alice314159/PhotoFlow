import SwiftUI

struct SettingsView: View {
    @ObservedObject var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        ScrollView {
            content
                .padding(24)
        }
        .frame(width: 660, height: 560)
        .preferredColorScheme(library.skin.colorScheme)
        .tint(library.skin.palette.accent)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr("Settings"))
                .font(.title2.weight(.semibold))

            Picker(tr("Language"), selection: $library.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Text(tr("Menus and panels switch immediately. Items macOS adds itself (Edit, Window) follow after a relaunch."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle(tr("After Pick or Reject, go to the next photo"), isOn: $library.autoAdvanceOnPick)
            Text(tr("Makes P / X culling almost mouse-free: mark, then the next frame is already up."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(tr("Group photos by content automatically"), isOn: $library.autoAnalyze)
            Text(tr("People, sports, pets, birds, nature, food… detected with Apple Vision on this Mac. Nothing is uploaded and files are never changed; results live in PhotoFlow’s database."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(tr("Look up place names for photos with GPS"), isOn: $library.lookUpPlaces)
            Text(tr("Sends only the coordinates to Apple’s map service to get names like “上海市 · 外滩” for searching and the Places list. Photos without GPS can be tagged by hand (right-click ▸ Set Location…)."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text(tr("Skin"))
                    .font(.headline)
                Spacer()
                Text(tr("⌥⌘K next  ·  ⇧⌥⌘K previous"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(tr("Applies to chrome, panels, and the image canvas. Original photos are unchanged."))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(SkinFamily.allCases) { family in
                VStack(alignment: .leading, spacing: 8) {
                    Text(family.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(AppSkin.allCases.filter { $0.family == family }) { skin in
                            Button {
                                library.skin = skin
                            } label: {
                                SkinPreviewSwatch(skin: skin, isSelected: library.skin == skin)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button(tr("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
