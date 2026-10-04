import SwiftUI

/// Inline rename for one color label, shown from the sidebar's right-click menu.
struct ColorLabelNameEditor: View {
    @ObservedObject var library: PhotoLibrary
    let label: ColorLabel
    let done: () -> Void
    private var text: State<String>

    init(library: PhotoLibrary, label: ColorLabel, done: @escaping () -> Void) {
        self.library = library
        self.label = label
        self.done = done
        text = State(initialValue: library.colorNames.name(for: label))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ColorDot(label: label, size: 12)
                Text(tr(label.defaultName))
                    .font(.headline)
            }
            TextField(tr(label.defaultName), text: text.projectedValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit(save)
            Text(tr("Suggested examples: Reject, Maybe, Selected, Published, Personal"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(tr("Reset")) {
                    library.colorNames.setName("", for: label)
                    done()
                }
                Spacer()
                Button(tr("Done"), action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(12)
    }

    private func save() {
        library.colorNames.setName(text.wrappedValue, for: label)
        done()
    }
}
