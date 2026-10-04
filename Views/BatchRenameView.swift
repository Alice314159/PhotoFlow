import SwiftUI

struct BatchRenameView: View {
    @ObservedObject var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss

    private var pattern = State(initialValue: "{name}_{nnn}")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Rename %@ files", library.batchPhotos.count))
                .font(.title2.weight(.semibold))
            Text(tr("This only changes filenames on disk. Pixels and EXIF stay the same."))
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("{name}_{nnn}", text: pattern.projectedValue)
                .textFieldStyle(.roundedBorder)
            Text(tr("Tokens: {name} {n} {nnn} {date} {camera}"))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            GroupBox(tr("Preview")) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(previewRows.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(row.before)
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text(row.after)
                                .lineLimit(1)
                        }
                        .font(.caption.monospaced())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(tr("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("Rename")) {
                    library.renameBatch(pattern: pattern.wrappedValue)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var previewRows: [(before: String, after: String)] {
        library.batchPhotos.prefix(5).enumerated().map { index, photo in
            let after = NameTemplate.resolve(
                pattern.wrappedValue,
                photo: photo,
                index: index + 1,
                fileExtension: photo.url.pathExtension
            )
            return (photo.name, after)
        }
    }
}
