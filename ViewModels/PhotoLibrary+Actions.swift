import AppKit
import UniformTypeIdentifiers

/// Everyday file actions on the current selection: Save As, Mail, Share, Open With, Print…
/// None of them write to the original files.
extension PhotoLibrary {
    /// Right-clicking a photo outside the selection makes it the selection (Finder behaviour).
    func focusContext(on photo: PhotoItem) {
        guard !checkedIDs.contains(photo.id) else { return }
        selectPhoto(photo, toggle: false, extend: false)
    }

    var batchByteCount: Int64 {
        batchPhotos.reduce(Int64(0)) { $0 + ($1.fileByteSize ?? 0) }
    }

    // MARK: - Save As

    /// One photo: pick name, folder and format. Several photos: the export sheet.
    func saveAs() {
        let items = batchPhotos
        guard let photo = items.first else {
            exportNote = tr("Select a photo first.")
            return
        }
        guard items.count == 1 else {
            openExportSheet()
            return
        }

        let panel = NSSavePanel()
        panel.title = tr("Save As")
        panel.prompt = tr("Save")
        panel.canCreateDirectories = true
        panel.directoryURL = photo.url.deletingLastPathComponent()

        let accessory = SaveAsAccessory(settings: exportSettings, originalExtension: photo.url.pathExtension)
        panel.accessoryView = accessory.view
        accessory.onChange = { [weak panel] format in
            guard let panel else { return }
            Self.configure(panel, format: format, photo: photo)
        }
        Self.configure(panel, format: exportSettings.format, photo: photo)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.standardizedFileURL.path != photo.url.standardizedFileURL.path else {
            exportNote = tr("PhotoFlow never overwrites the original. Choose another name or folder.")
            return
        }

        var settings = exportSettings
        settings.format = accessory.format
        isExporting = true
        Task.detached(priority: .userInitiated) { [self] in
            let note: String
            do {
                try PhotoExporter.write(photo, to: url, settings: settings)
                note = tr("Saved %@.", url.lastPathComponent)
            } catch {
                note = tr("Save failed: %@", error.localizedDescription)
            }
            await MainActor.run {
                self.isExporting = false
                self.exportNote = note
            }
        }
    }

    private static func configure(_ panel: NSSavePanel, format: ExportFormat, photo: PhotoItem) {
        let ext = format.fileExtension ?? photo.url.pathExtension
        let stem = (photo.name as NSString).deletingPathExtension
        let currentStem = panel.nameFieldStringValue.isEmpty
            ? "\(stem)-copy"
            : (panel.nameFieldStringValue as NSString).deletingPathExtension
        if let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = "\(currentStem).\(ext)"
    }

    // MARK: - Mail & share

    /// Opens a new Mail message with the photos attached, optionally as smaller JPEGs.
    func emailBatch(resized: Bool) {
        let items = batchPhotos
        guard !items.isEmpty else { return }

        guard let service = NSSharingService(named: .composeEmail) else {
            exportNote = tr("Mail is not available.")
            return
        }
        service.subject = items.count == 1 ? items[0].name : tr("%@ photos", items.count)

        guard resized else {
            service.perform(withItems: items.map(\.url))
            return
        }

        isExporting = true
        Task.detached(priority: .userInitiated) { [self] in
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("PhotoFlow-Mail", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            var settings = ExportSettings()
            settings.format = .jpeg
            settings.quality = 0.82
            settings.resize = true
            settings.sizeValue = 2048
            settings.sizeUnit = .pixels
            settings.colorSpace = .sRGB
            let urls: [URL]
            do {
                _ = try PhotoExporter.export(items, to: folder, settings: settings)
                urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            } catch {
                urls = []
            }
            await MainActor.run {
                self.isExporting = false
                if urls.isEmpty {
                    self.exportNote = tr("Could not prepare photos for Mail.")
                } else {
                    service.perform(withItems: urls.sorted { $0.lastPathComponent < $1.lastPathComponent })
                }
            }
        }
    }

    // MARK: - Pasteboard

    func copyImageToPasteboard() {
        guard let photo = batchPhotos.first, let image = NSImage(contentsOf: photo.url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        flashCopyNote(tr("Copied image"))
    }

    func copyPathsToPasteboard() {
        let paths = batchPhotos.map(\.filePath)
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
        flashCopyNote(paths.count == 1 ? tr("Copied path") : tr("Copied %@ paths", paths.count))
    }

    func flashCopyNote(_ note: String) {
        copyNote = note
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.copyNote == note { self?.copyNote = nil }
        }
    }

    // MARK: - Open / reveal / desktop / print

    func openInPreview() {
        let urls = batchPhotos.map(\.url)
        guard !urls.isEmpty,
              let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
    }

    func openWithDefaultApp() {
        for url in batchPhotos.map(\.url) {
            NSWorkspace.shared.open(url)
        }
    }

    func revealBatchInFinder() {
        let urls = batchPhotos.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// NSOpenPanel for a parent folder of an inaccessible collection photo.
    func grantFolderAccess(for photo: PhotoItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = photo.url.deletingLastPathComponent()
        panel.prompt = tr("Open")
        panel.message = tr("Allow PhotoFlow to read photos in this folder. Files are never modified.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rememberFolderAccess(url)
        if url.startAccessingSecurityScopedResource() {
            extraFolderAccess.append(url)
        }
        if let id = activeCollectionID {
            openCollection(id)
        } else {
            refreshChangedFiles()
        }
    }

    func setDesktopPicture() {
        guard let photo = batchPhotos.first else { return }
        do {
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(photo.url, for: screen, options: [:])
            }
            flashCopyNote(tr("Desktop picture set"))
        } catch {
            exportNote = tr("Could not set desktop picture: %@", error.localizedDescription)
        }
    }

    func printSelected() {
        guard let photo = batchPhotos.first, let image = NSImage(contentsOf: photo.url) else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        let pixelSize = image.representations.first.map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? image.size
        info.orientation = pixelSize.width > pixelSize.height ? .landscape : .portrait

        let page = info.imageablePageBounds.size
        let view = NSImageView(frame: NSRect(origin: .zero, size: page))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = photo.name
        operation.run()
    }
}

/// "Format" pop-up shown at the bottom of the Save As panel.
@MainActor
private final class SaveAsAccessory: NSObject {
    let view: NSView
    private let popup: NSPopUpButton
    private(set) var format: ExportFormat
    var onChange: ((ExportFormat) -> Void)?

    init(settings: ExportSettings, originalExtension: String) {
        format = settings.format
        popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for item in ExportFormat.allCases {
            let title = item == .original ? tr("Original (%@, exact copy)", originalExtension.uppercased()) : item.title
            popup.addItem(withTitle: title)
        }
        popup.selectItem(at: ExportFormat.allCases.firstIndex(of: format) ?? 0)

        let label = NSTextField(labelWithString: tr("Format:"))
        var parts: [String] = [
            settings.resize
                ? tr("%@ %@ long edge", SizeUnit.format(settings.sizeValue), settings.sizeUnit.symbol)
                : tr("original size")
        ]
        parts.append(settings.colorSpace.title)
        parts.append(tr("JPEG %@%", Int((settings.quality * 100).rounded())))
        let hint = NSTextField(labelWithString: tr("Uses export settings: ") + parts.joined(separator: " · "))
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor

        let row = NSStackView(views: [label, popup])
        row.orientation = .horizontal
        row.spacing = 8
        let stack = NSStackView(views: [row, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        container.frame.size = stack.fittingSize
        view = container
        super.init()

        popup.target = self
        popup.action = #selector(changed)
    }

    @objc private func changed() {
        format = ExportFormat.allCases[max(popup.indexOfSelectedItem, 0)]
        onChange?(format)
    }
}
