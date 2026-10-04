import AppKit

/// Panel visibility, full-screen preview, zoom, and skins.
extension PhotoLibrary {
    func toggleViewMode() {
        viewMode = viewMode == .loupe ? .grid : .loupe
    }

    func showInspector(_ tab: InspectorTab) {
        if showFilterPanel, inspectorTab == tab {
            showFilterPanel = false
        } else {
            inspectorTab = tab
            showFilterPanel = true
        }
    }

    /// Collapses every panel around the image, or restores the previous layout.
    func toggleAllPanels() {
        if anyPanelVisible {
            hideAllPanels()
        } else {
            showAllPanels()
        }
    }

    func hideAllPanels() {
        panelsBeforeFocus = [showSidebar, showFilterPanel, showFilmstrip, showInfoBar]
        setPanels([false, false, false, false])
    }

    func showAllPanels() {
        let saved = panelsBeforeFocus ?? []
        panelsBeforeFocus = nil
        if saved.count == 4, saved.contains(true) {
            setPanels(saved)
        } else {
            setPanels([true, true, true, true])
        }
    }

    private func setPanels(_ values: [Bool]) {
        isRestoringPanels = true
        showSidebar = values[0]
        showFilterPanel = values[1]
        showFilmstrip = values[2]
        showInfoBar = values[3]
        isRestoringPanels = false
        persistPanels()
    }

    // MARK: - Lightroom-style commands

    /// Tab: the left and right panels only, like Lightroom.
    func toggleSidePanels() {
        let show = !(showSidebar || showFilterPanel)
        showSidebar = show
        showFilterPanel = show
    }

    /// ⇧Tab: every panel including the top bar.
    func toggleEverything() {
        if anyPanelVisible || showTopBar {
            hideAllPanels()
            showTopBar = false
        } else {
            showAllPanels()
            showTopBar = true
        }
    }

    /// F: full-screen preview of the current photo; F or Esc returns.
    func togglePresentation() {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        if isPresenting, let saved = presentationSnapshot {
            isRestoringPanels = true
            showSidebar = saved.panels[0]
            showFilterPanel = saved.panels[1]
            showFilmstrip = saved.panels[2]
            showInfoBar = saved.panels[3]
            showTopBar = saved.topBar
            isRestoringPanels = false
            viewMode = saved.mode
            if !saved.wasFullScreen, window?.styleMask.contains(.fullScreen) == true {
                window?.toggleFullScreen(nil)
            }
            presentationSnapshot = nil
            isPresenting = false
            return
        }
        guard selectedPhoto != nil else { return }
        let wasFullScreen = window?.styleMask.contains(.fullScreen) == true
        presentationSnapshot = (
            [showSidebar, showFilterPanel, showFilmstrip, showInfoBar], showTopBar, viewMode, wasFullScreen
        )
        isRestoringPanels = true
        showSidebar = false
        showFilterPanel = false
        showFilmstrip = false
        showInfoBar = false
        showTopBar = false
        isRestoringPanels = false
        viewMode = .loupe
        isPresenting = true
        if !wasFullScreen { window?.toggleFullScreen(nil) }
    }

    func requestZoom(_ kind: ZoomCommand.Kind) {
        if viewMode == .grid {
            switch kind {
            case .zoomIn: adjustGridSize(by: 30)
            case .zoomOut: adjustGridSize(by: -30)
            case .fit, .actual, .toggle: viewMode = .loupe
            }
            return
        }
        browser.zoomCommand = ZoomCommand(kind: kind)
    }

    func adjustGridSize(by delta: Double) {
        gridThumbnailSize = min(max(gridThumbnailSize + delta, Self.gridSizeRange.lowerBound), Self.gridSizeRange.upperBound)
    }

    func cycleSkin(forward: Bool = true) {
        let all = AppSkin.allCases
        guard let index = all.firstIndex(of: skin) else { return }
        let next = (index + (forward ? 1 : all.count - 1)) % all.count
        skin = all[next]
        flashCopyNote(tr("Skin: %@", skin.title))
    }

    func persistPanels() {
        guard !isRestoringPanels else { return }
        UserDefaults.standard.set(
            [showSidebar, showFilterPanel, showFilmstrip, showInfoBar],
            forKey: Preferences.Key.panelVisibility
        )
    }

    func restorePanels() {
        guard let values = UserDefaults.standard.array(forKey: Preferences.Key.panelVisibility) as? [Bool],
              values.count == 4 else { return }
        isRestoringPanels = true
        showSidebar = values[0]
        showFilterPanel = values[1]
        showFilmstrip = values[2]
        showInfoBar = values[3]
        isRestoringPanels = false
    }
}
