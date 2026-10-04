import SwiftUI

struct BatchExportView: View {
    @ObservedObject var library: PhotoLibrary
    @ObservedObject var activity: LibraryActivity
    @Environment(\.dismiss) private var dismiss

    private var estimate = State(initialValue: tr("Estimating…"))
    private var estimateGeneration = State(initialValue: 0)

    private var settings: ExportSettings { library.exportSettings }
    private var reencodes: Bool { settings.format != .original }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Export %@ photos", library.batchPhotos.count))
                    .font(.title2.weight(.semibold))
                Text(tr("Originals are never modified. JPEG / HEIC / PNG / TIFF write new files; RAW is developed by macOS."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    label(tr("Format"))
                    Picker(tr("Format"), selection: $library.exportSettings.format) {
                        ForEach(ExportFormat.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 400)
                }

                GridRow {
                    label(tr("Size"))
                    sizeControls
                }

                if settings.resize, settings.sizeUnit.isPhysical {
                    GridRow {
                        label(tr("Resolution"))
                        HStack(spacing: 6) {
                            numberField($library.exportSettings.resolution, width: 70)
                            Text("ppi")
                                .foregroundStyle(.secondary)
                            Menu(tr("Presets")) {
                                ForEach([72.0, 150, 240, 300, 350], id: \.self) { ppi in
                                    Button(tr("%@ ppi", Int(ppi))) { library.exportSettings.resolution = ppi }
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        .disabled(!reencodes)
                    }
                }

                GridRow {
                    label(tr("Color"))
                    VStack(alignment: .leading, spacing: 4) {
                        Picker(tr("Color space"), selection: $library.exportSettings.colorSpace) {
                            ForEach(ExportColorSpace.allCases) { space in
                                Text(space.title).tag(space)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 360)
                        Text(settings.colorSpace.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!reencodes)
                }

                if settings.format.isLossy {
                    GridRow {
                        label(tr("Quality"))
                        HStack {
                            Slider(value: $library.exportSettings.quality, in: 0.4...1.0)
                                .frame(width: 300)
                            Text("\(Int((settings.quality * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }

                GridRow(alignment: .top) {
                    label(tr("Filename"))
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("{name}_{nnn}", text: $library.exportSettings.pattern)
                            .textFieldStyle(.roundedBorder)
                        Text(tr("Tokens: {name} {n} {nnn} {date} {camera}"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        ForEach(previewNames, id: \.self) { name in
                            Text(name)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !reencodes {
                Text(tr("Original copy keeps the files byte-for-byte, so size and color settings don’t apply."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Estimated output"))
                        .font(.subheadline.weight(.semibold))
                    Text(estimate.wrappedValue)
                        .font(.title3.monospacedDigit())
                    if let summary = sizeSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(tr("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(activity.isExporting ? tr("Exporting…") : tr("Export")) {
                    runExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(activity.isExporting || library.batchPhotos.isEmpty || !settings.isValid)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { refreshEstimate() }
        .onChange(of: library.exportSettings) { old, new in
            var a = old
            var b = new
            a.pattern = ""
            b.pattern = ""
            if a != b { refreshEstimate() }
        }
    }

    // MARK: - Size

    private var sizeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker(tr("Resize"), selection: $library.exportSettings.resize) {
                    Text(tr("Original size")).tag(false)
                    Text(tr("Long edge")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)

                if settings.resize {
                    numberField($library.exportSettings.sizeValue, width: 80)

                    Picker(tr("Unit"), selection: unitBinding) {
                        ForEach(SizeUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    Menu {
                        ForEach(settings.sizeUnit.presets, id: \.self) { value in
                            Button("\(SizeUnit.format(value)) \(settings.sizeUnit.symbol)") {
                                library.exportSettings.sizeValue = value
                            }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(tr("Common sizes"))
                }
            }
            if settings.resize, !settings.isValid {
                Text(tr("Enter a value greater than 0."))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .disabled(!reencodes)
    }

    /// Switching units keeps the same pixel size by converting the number.
    private var unitBinding: Binding<SizeUnit> {
        Binding(
            get: { library.exportSettings.sizeUnit },
            set: { unit in
                var next = library.exportSettings
                next.sizeValue = next.converted(to: unit, reference: library.batchPhotos.first)
                next.sizeUnit = unit
                library.exportSettings = next
            }
        )
    }

    private func numberField(_ value: Binding<Double>, width: CGFloat) -> some View {
        TextField("", value: value, format: .number.precision(.fractionLength(0...2)).grouping(.never))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private var sizeSummary: String? {
        guard reencodes, let sample = library.batchPhotos.first,
              let size = PhotoExporter.outputSize(for: sample, settings: settings) else { return nil }
        var text = tr("First photo: %@ × %@ px", size.0, size.1)
        let ppi = settings.resolution
        if settings.sizeUnit.isPhysical || ppi != 300, ppi > 0 {
            let unit = settings.sizeUnit.isPhysical ? settings.sizeUnit : .inches
            let w = Double(size.0) / ppi / unit.inches
            let h = Double(size.1) / ppi / unit.inches
            text += String(format: "  ·  %.1f × %.1f %@ @ %d ppi", w, h, unit.symbol, Int(ppi))
        }
        if let target = settings.longEdgePixels(for: sample),
           let width = sample.width, let height = sample.height, target > max(width, height) {
            text += tr("  ·  not upscaled")
        }
        text += "  ·  \(settings.colorSpace.title)"
        return text
    }

    private var previewNames: [String] {
        let ext = settings.format.fileExtension ?? (library.batchPhotos.first?.url.pathExtension ?? "jpg")
        return library.batchPhotos.prefix(3).enumerated().map { index, photo in
            NameTemplate.resolve(settings.pattern, photo: photo, index: index + 1, fileExtension: ext)
        }
    }

    private func refreshEstimate() {
        let photos = library.batchPhotos
        let current = settings
        guard current.isValid else {
            estimate.wrappedValue = "—"
            return
        }
        estimateGeneration.wrappedValue += 1
        let generation = estimateGeneration.wrappedValue
        estimate.wrappedValue = tr("Estimating…")
        Task {
            // Debounce typing and slider drags so only the final value is encoded.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard generation == estimateGeneration.wrappedValue else { return }
            let bytes = await Task.detached(priority: .userInitiated) {
                PhotoExporter.estimateBytes(for: photos, settings: current)
            }.value
            guard generation == estimateGeneration.wrappedValue else { return }
            estimate.wrappedValue = tr("≈ %@ for %@ files", ByteCount.string(bytes), photos.count)
        }
    }

    private func runExport() {
        let current = settings
        dismiss()
        DispatchQueue.main.async {
            library.exportBatch(current)
        }
    }
}
