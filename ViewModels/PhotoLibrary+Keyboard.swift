import AppKit

/// Lightroom-style single-key commands, handled before menus so bare keys work everywhere.
extension PhotoLibrary {
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, !isEditingText {
            // Handled here rather than as menu shortcuts so text fields keep ⌘C / ⌘A / ⌘Z.
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                copyBatchToPasteboard()
                return true
            case "a":
                selectAllVisible()
                return true
            case "z":
                undo()
                return true
            default:
                return false
            }
        }
        if flags == [.command, .shift], !isEditingText,
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            redo()
            return true
        }
        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
            return false
        }

        if isEditingText {
            // Esc / Return leave the search field so arrows page photos again.
            if event.keyCode == 53 || event.keyCode == 36 {
                resignTextFocus()
                return true
            }
            // An empty field has no caret to move, so ← → keep paging photos.
            if (event.keyCode == 123 || event.keyCode == 124), editingText.isEmpty {
                resignTextFocus()
            } else {
                return false
            }
        }

        let shift = flags.contains(.shift)
        switch event.keyCode {
        case 123:
            selectPrevious()
            return true
        case 124:
            selectNext()
            return true
        case 126 where viewMode == .loupe:
            selectPrevious()
            return true
        case 125 where viewMode == .loupe:
            selectNext()
            return true
        case 115:
            selectFirst()
            return true
        case 119:
            selectLast()
            return true
        case 36, 76:
            if viewMode == .grid { viewMode = .loupe }
            return true
        case 48:
            if shift { toggleEverything() } else { toggleSidePanels() }
            return true
        case 53:
            if isPresenting { togglePresentation() } else { clearChecked() }
            return true
        case 120:
            openRenameSheet()
            return true
        case 51 where activeCollectionID != nil, 117 where activeCollectionID != nil:
            removeBatchFromActiveCollection()
            return true
        case 96:
            showTopBar.toggle()
            return true
        case 97:
            showFilmstrip.toggle()
            return true
        case 98:
            showSidebar.toggle()
            return true
        case 100:
            showFilterPanel.toggle()
            return true
        default:
            break
        }

        // Lightroom: Shift + a marking key applies it and moves to the next photo.
        if shift, let mark = Self.shiftedMarks[event.keyCode] {
            markAndAdvance(mark)
            return true
        }

        let chars = (event.charactersIgnoringModifiers ?? "").lowercased()
        switch chars {
        case "1": setRating(1)
        case "2": setRating(2)
        case "3": setRating(3)
        case "4": setRating(4)
        case "5": setRating(5)
        case "0": setRating(0)
        case "p": setPick(.picked)
        case "x": setPick(.rejected)
        case "u": setPick(.none)
        case "`": togglePickFlag()
        case "b": toggleTargetCollection()
        case "6": setColor(.red)
        case "7": setColor(.yellow)
        case "8": setColor(.green)
        case "9": setColor(.blue)
        case "-": setColor(.purple)
        case "[": adjustRating(by: -1)
        case "]": adjustRating(by: 1)
        case "g": viewMode = .grid
        case "e": viewMode = .loupe
        case "z": requestZoom(.toggle)
        case " ":
            if viewMode == .loupe { requestZoom(.toggle) } else { viewMode = .loupe }
        case "f": togglePresentation()
        case "i": showInspector(.info)
        case "\\": showInspector(.filter)
        case "'": showInfoBar.toggle()
        default:
            return false
        }
        return true
    }

    private enum Mark {
        case rating(Int), pick(PickStatus), color(ColorLabel)
    }

    /// Physical key codes, so Shift doesn't turn "1" into "!".
    private static let shiftedMarks: [UInt16: Mark] = [
        29: .rating(0), 18: .rating(1), 19: .rating(2), 20: .rating(3), 21: .rating(4), 23: .rating(5),
        22: .color(.red), 26: .color(.yellow), 28: .color(.green), 25: .color(.blue), 27: .color(.purple),
        35: .pick(.picked), 7: .pick(.rejected), 32: .pick(.none),
    ]

    private func markAndAdvance(_ mark: Mark) {
        let before = selectedID
        switch mark {
        case .rating(let value): setRating(value)
        case .pick(let status): setPick(status)
        case .color(let color): setColor(color)
        }
        if selectedID == before, !isBatchMarking { selectNext() }
    }

    func resignTextFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// Installed once for the app's lifetime so view re-creation can never drop it.
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Sheets (export, rename, settings) and open panels keep their own keys.
            guard let self, let window = event.window, window.attachedSheet == nil,
                  window.sheetParent == nil, !(window is NSPanel) else {
                return event
            }
            return MainActor.assumeIsolated { self.handleKey(event) } ? nil : event
        }

        // SwiftUI focuses the search field when the window first becomes key,
        // which happens after onAppear; clear it so arrows page photos immediately.
        // Leaving full screen with the green button or Esc-by-system must also end the preview,
        // otherwise every panel stays hidden.
        fullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPresenting else { return }
                self.togglePresentation()
            }
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow, !(window is NSPanel), window.sheetParent == nil else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let id = ObjectIdentifier(window)
                guard !self.focusClearedWindows.contains(id) else { return }
                self.focusClearedWindows.insert(id)
                DispatchQueue.main.async {
                    if self.isEditingText, self.editingText.isEmpty {
                        window.makeFirstResponder(nil)
                    }
                }
            }
        }
    }

    private var editingText: String {
        let responder = NSApp.keyWindow?.firstResponder
        if let textView = responder as? NSTextView { return textView.string }
        if let field = responder as? NSTextField { return field.stringValue }
        return ""
    }

    private var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let field = responder as? NSTextField { return field.isEditable }
        if let textView = responder as? NSTextView {
            return textView.isEditable && textView.isFieldEditor
        }
        return false
    }
}
