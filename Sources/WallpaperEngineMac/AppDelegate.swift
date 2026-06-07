import AppKit
import UniformTypeIdentifiers
import WallpaperEngineCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = AppPreferences()
    private let scanner = WallpaperLibraryScanner()
    private let powerManager = PowerManager()

    private var renderCoordinator: RenderCoordinator!
    private var statusItem: NSStatusItem!
    private var projects: [WallpaperProject] = []
    private var isUserPaused = false
    private var automaticSwitchTimer: Timer?

    private lazy var libraryWindowController: LibraryWindowController = {
        let controller = LibraryWindowController()
        controller.onImportRequested = { [weak self] in
            self?.importWallpaper()
        }
        controller.onApplyRequested = { [weak self] project in
            self?.apply(project)
        }
        controller.onSetLightRequested = { [weak self] project in
            self?.setLightWallpaper(project)
        }
        controller.onSetDarkRequested = { [weak self] project in
            self?.setDarkWallpaper(project)
        }
        controller.onRevealRequested = { project in
            NSWorkspace.shared.activateFileViewerSelecting([project.rootURL])
        }
        controller.onDeleteRequested = { [weak self] project in
            self?.deleteWallpaper(project)
        }
        return controller
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditingMainMenu()

        renderCoordinator = RenderCoordinator(preferences: preferences)
        renderCoordinator.onStatusChanged = { [weak self] in
            self?.rebuildMenu()
        }

        powerManager.onStateChanged = { [weak self] _ in
            self?.updatePauseReasons()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Wallpaper Engine Mac")
            button.imagePosition = .imageLeading
            button.title = "WE"
        }

        reloadLibrary(restoreSelection: true)
        renderCoordinator.start()
        powerManager.start()
        startAutomaticSwitching()
        applyAutomaticWallpaperIfNeeded()
        updatePauseReasons()
        rebuildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        automaticSwitchTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: .appleInterfaceThemeChanged,
            object: nil
        )
        renderCoordinator.clear()
    }

    private func reloadLibrary(restoreSelection: Bool = false) {
        do {
            projects = try scanner.scan(roots: preferences.libraryRoots)
            libraryWindowController.projects = projects

            if restoreSelection,
               preferences.autoSwitchMode == .off,
               let selectedPath = preferences.selectedWallpaperRootPath,
               let project = projects.first(where: { $0.rootURL.path == selectedPath && $0.isPlayableNow }) {
                try renderCoordinator.apply(project)
            }

            applyAutomaticWallpaperIfNeeded()
        } catch {
            presentError(error)
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Wallpaper Engine Mac", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let statusItem = NSMenuItem(title: renderCoordinator.statusDescription, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Show Library", action: #selector(showLibrary), keyEquivalent: "l", target: self))
        menu.addItem(NSMenuItem(title: "Import Folder or Video", action: #selector(importWallpaper), keyEquivalent: "i", target: self))
        menu.addItem(NSMenuItem(title: "Reload Library", action: #selector(reloadLibraryFromMenu), keyEquivalent: "r", target: self))

        let wallpapersMenu = NSMenu()
        for project in projects.prefix(40) {
            let item = NSMenuItem(title: projectMenuTitle(project), action: #selector(applyWallpaperFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = project.rootURL.path
            item.isEnabled = project.isPlayableNow
            wallpapersMenu.addItem(item)
        }

        if projects.isEmpty {
            let emptyItem = NSMenuItem(title: "No imported wallpapers", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            wallpapersMenu.addItem(emptyItem)
        }

        let wallpapersItem = NSMenuItem(title: "Wallpapers", action: nil, keyEquivalent: "")
        wallpapersItem.submenu = wallpapersMenu
        menu.addItem(wallpapersItem)

        let automationItem = NSMenuItem(title: "Automation", action: nil, keyEquivalent: "")
        automationItem.submenu = automationMenu()
        menu.addItem(automationItem)

        let interactiveObjectsItem = NSMenuItem(title: "Interactive Objects", action: nil, keyEquivalent: "")
        interactiveObjectsItem.submenu = interactiveObjectsMenu()
        menu.addItem(interactiveObjectsItem)

        let steamWorkshopItem = NSMenuItem(title: "Steam Workshop", action: nil, keyEquivalent: "")
        steamWorkshopItem.submenu = steamWorkshopMenu()
        menu.addItem(steamWorkshopItem)
        menu.addItem(.separator())

        menu.addItem(toggleItem(
            title: isUserPaused ? "Resume" : "Pause",
            action: #selector(toggleUserPause),
            keyEquivalent: "p",
            state: isUserPaused
        ))
        menu.addItem(toggleItem(
            title: "Mute Audio",
            action: #selector(toggleMute),
            state: preferences.isMuted
        ))
        menu.addItem(toggleItem(
            title: currentProject?.usesAudioResponsiveOverlay == true ? "Audio Responsive (Auto)" : "Audio Responsive",
            action: #selector(toggleAudioResponsive),
            state: preferences.audioResponsiveEnabled || currentProject?.usesAudioResponsiveOverlay == true
        ))
        menu.addItem(NSMenuItem(
            title: "Open Screen & System Audio Settings",
            action: #selector(openScreenAndSystemAudioSettings),
            keyEquivalent: "",
            target: self
        ))
        menu.addItem(toggleItem(
            title: "Pause on Battery",
            action: #selector(togglePauseOnBattery),
            state: preferences.pauseOnBattery
        ))
        menu.addItem(toggleItem(
            title: "Pause in Low Power Mode",
            action: #selector(togglePauseOnLowPowerMode),
            state: preferences.pauseOnLowPowerMode
        ))
        menu.addItem(toggleItem(
            title: "Release Decoder While Paused",
            action: #selector(toggleReleaseDecoderOnLongPause),
            state: preferences.releaseDecoderOnLongPause
        ))
        menu.addItem(NSMenuItem(title: "Clear Wallpaper", action: #selector(clearWallpaper), keyEquivalent: "", target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q", target: self))

        self.statusItem.menu = menu
    }

    private func automationMenu() -> NSMenu {
        let menu = NSMenu()

        let statusItem = NSMenuItem(title: "Mode: \(preferences.autoSwitchMode.menuTitle)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        for mode in WallpaperAutoSwitchMode.allCases {
            menu.addItem(autoSwitchModeItem(mode))
        }

        menu.addItem(.separator())

        let lightSlotItem = NSMenuItem(title: "Light/Day: \(slotTitle(preferences.lightWallpaperRootPath))", action: nil, keyEquivalent: "")
        lightSlotItem.isEnabled = false
        menu.addItem(lightSlotItem)

        let darkSlotItem = NSMenuItem(title: "Dark/Night: \(slotTitle(preferences.darkWallpaperRootPath))", action: nil, keyEquivalent: "")
        darkSlotItem.isEnabled = false
        menu.addItem(darkSlotItem)

        let scheduleItem = NSMenuItem(title: "Schedule: \(formattedTime(preferences.dayStartMinute))-\(formattedTime(preferences.nightStartMinute))", action: nil, keyEquivalent: "")
        scheduleItem.isEnabled = false
        menu.addItem(scheduleItem)
        menu.addItem(.separator())

        let setLightItem = NSMenuItem(title: "Set Current as Light/Day", action: #selector(setCurrentAsLightWallpaper), keyEquivalent: "", target: self)
        setLightItem.isEnabled = currentProject?.isPlayableNow == true
        menu.addItem(setLightItem)

        let setDarkItem = NSMenuItem(title: "Set Current as Dark/Night", action: #selector(setCurrentAsDarkWallpaper), keyEquivalent: "", target: self)
        setDarkItem.isEnabled = currentProject?.isPlayableNow == true
        menu.addItem(setDarkItem)

        menu.addItem(NSMenuItem(title: "Clear Light/Day Slot", action: #selector(clearLightWallpaper), keyEquivalent: "", target: self))
        menu.addItem(NSMenuItem(title: "Clear Dark/Night Slot", action: #selector(clearDarkWallpaper), keyEquivalent: "", target: self))

        return menu
    }

    private func steamWorkshopMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Open Wallpaper Engine Workshop",
            action: #selector(openSteamWorkshop),
            keyEquivalent: "",
            target: self
        ))
        menu.addItem(NSMenuItem(
            title: "Open Workshop Item...",
            action: #selector(openSteamWorkshopItem),
            keyEquivalent: "",
            target: self
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Import Local Workshop Folder",
            action: #selector(importLocalSteamWorkshopFolder),
            keyEquivalent: "",
            target: self
        ))
        menu.addItem(NSMenuItem(
            title: "Download Item with SteamCMD Login...",
            action: #selector(downloadSteamWorkshopItemWithSteamCMDLogin),
            keyEquivalent: "",
            target: self
        ))
        return menu
    }

    private func interactiveObjectsMenu() -> NSMenu {
        let menu = NSMenu()
        let project = currentProject
        let objectCount = project?.interactiveObjects.count ?? 0

        let statusItem = NSMenuItem(title: "Objects: \(objectCount)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let toggle = toggleItem(
            title: "Edit / Interact With Objects",
            action: #selector(toggleInteractiveObjects),
            state: preferences.interactiveObjectsEnabled
        )
        toggle.isEnabled = objectCount > 0
        menu.addItem(toggle)

        menu.addItem(.separator())

        let addImageItem = NSMenuItem(
            title: "Add Image Object to Current Wallpaper...",
            action: #selector(addInteractiveImageObject),
            keyEquivalent: "",
            target: self
        )
        addImageItem.isEnabled = project?.projectURL != nil
        menu.addItem(addImageItem)

        let addVideoItem = NSMenuItem(
            title: "Add Video Object to Current Wallpaper...",
            action: #selector(addInteractiveVideoObject),
            keyEquivalent: "",
            target: self
        )
        addVideoItem.isEnabled = project?.projectURL != nil
        menu.addItem(addVideoItem)

        let addLive2DItem = NSMenuItem(
            title: "Add Live2D Web Object...",
            action: #selector(addInteractiveLive2DObject),
            keyEquivalent: "",
            target: self
        )
        addLive2DItem.isEnabled = project?.projectURL != nil
        menu.addItem(addLive2DItem)

        let removeItem = NSMenuItem(title: "Remove Object", action: nil, keyEquivalent: "")
        removeItem.submenu = removeInteractiveObjectMenu(for: project)
        removeItem.isEnabled = objectCount > 0
        menu.addItem(removeItem)

        return menu
    }

    private func removeInteractiveObjectMenu(for project: WallpaperProject?) -> NSMenu {
        let menu = NSMenu()
        guard let project, !project.interactiveObjects.isEmpty else {
            let emptyItem = NSMenuItem(title: "No objects", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return menu
        }

        for object in project.interactiveObjects {
            let item = NSMenuItem(
                title: object.title ?? object.id,
                action: #selector(removeInteractiveObjectFromMenu(_:)),
                keyEquivalent: "",
                target: self
            )
            item.representedObject = object.id
            menu.addItem(item)
        }

        return menu
    }

    private func autoSwitchModeItem(_ mode: WallpaperAutoSwitchMode) -> NSMenuItem {
        let item = NSMenuItem(title: mode.menuTitle, action: #selector(setAutoSwitchModeFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = mode.rawValue
        item.state = preferences.autoSwitchMode == mode ? .on : .off
        return item
    }

    private func toggleItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        state: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.state = state ? .on : .off
        return item
    }

    private func projectMenuTitle(_ project: WallpaperProject) -> String {
        let suffix = project.usesAudioResponsiveOverlay ? " [Audio Responsive]" : ""
        if project.isPlayableNow {
            return project.title + suffix
        }
        return "\(project.title) (\(project.type.rawValue))" + suffix
    }

    private var currentProject: WallpaperProject? {
        guard let path = preferences.selectedWallpaperRootPath else {
            return nil
        }
        return project(rootPath: path)
    }

    private func project(rootPath: String?) -> WallpaperProject? {
        guard let rootPath else {
            return nil
        }
        return projects.first { $0.rootURL.path == rootPath }
    }

    private func slotTitle(_ rootPath: String?) -> String {
        guard let rootPath else {
            return "Not Set"
        }
        return project(rootPath: rootPath)?.title ?? "Missing"
    }

    private func formattedTime(_ minuteOfDay: Int) -> String {
        let clampedMinute = max(0, min((24 * 60) - 1, minuteOfDay))
        return String(format: "%02d:%02d", clampedMinute / 60, clampedMinute % 60)
    }

    @objc
    private func showLibrary() {
        libraryWindowController.projects = projects
        libraryWindowController.show()
    }

    @objc
    private func importWallpaper() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Import Wallpaper Engine Folder or Video"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else {
            return
        }

        let importedRoots = panel.urls.map(normalizedImportRoot)
        preferences.libraryRoots.appendUnique(contentsOf: importedRoots)
        reloadLibrary()
        rebuildMenu()
    }

    @objc
    private func reloadLibraryFromMenu() {
        reloadLibrary()
        rebuildMenu()
    }

    private func deleteWallpaper(_ project: WallpaperProject) {
        let targetURL = deletionTargetURL(for: project)
        guard confirmDelete(project: project, targetURL: targetURL) else {
            return
        }

        do {
            let isCurrentWallpaper = preferences.selectedWallpaperRootPath == project.rootURL.path
            if isCurrentWallpaper {
                preferences.selectedWallpaperRootPath = nil
                renderCoordinator.clear()
            }
            if preferences.lightWallpaperRootPath == project.rootURL.path {
                preferences.lightWallpaperRootPath = nil
            }
            if preferences.darkWallpaperRootPath == project.rootURL.path {
                preferences.darkWallpaperRootPath = nil
            }
            preferences.clearInteractiveObjectFrameOverrides(projectRootPath: project.rootURL.path)

            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: targetURL, resultingItemURL: &trashedURL)
            removeDeletedProjectFromLibraryRoots(project: project, deletedURL: targetURL)
            reloadLibrary()
            rebuildMenu()
        } catch {
            presentError(error)
        }
    }

    @objc
    private func applyWallpaperFromMenu(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              let project = projects.first(where: { $0.rootURL.path == path })
        else {
            return
        }

        apply(project)
    }

    @objc
    private func setAutoSwitchModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = WallpaperAutoSwitchMode(rawValue: rawValue)
        else {
            return
        }

        preferences.autoSwitchMode = mode
        applyAutomaticWallpaperIfNeeded()
        rebuildMenu()
    }

    @objc
    private func setCurrentAsLightWallpaper() {
        guard let project = currentProject else {
            return
        }
        setLightWallpaper(project)
    }

    @objc
    private func setCurrentAsDarkWallpaper() {
        guard let project = currentProject else {
            return
        }
        setDarkWallpaper(project)
    }

    @objc
    private func clearLightWallpaper() {
        preferences.lightWallpaperRootPath = nil
        rebuildMenu()
    }

    @objc
    private func clearDarkWallpaper() {
        preferences.darkWallpaperRootPath = nil
        rebuildMenu()
    }

    @objc
    private func toggleUserPause() {
        isUserPaused.toggle()
        updatePauseReasons()
        rebuildMenu()
    }

    @objc
    private func toggleMute() {
        preferences.isMuted.toggle()
        renderCoordinator.updateMuted()
        rebuildMenu()
    }

    @objc
    private func toggleAudioResponsive() {
        preferences.audioResponsiveEnabled.toggle()
        renderCoordinator.updateAudioResponsive()
        rebuildMenu()
    }

    @objc
    private func openScreenAndSystemAudioSettings() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SystemAudioCapture"),
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
        ].compactMap { $0 }

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }

    @objc
    private func togglePauseOnBattery() {
        preferences.pauseOnBattery.toggle()
        updatePauseReasons()
        rebuildMenu()
    }

    @objc
    private func togglePauseOnLowPowerMode() {
        preferences.pauseOnLowPowerMode.toggle()
        updatePauseReasons()
        rebuildMenu()
    }

    @objc
    private func toggleReleaseDecoderOnLongPause() {
        preferences.releaseDecoderOnLongPause.toggle()
        renderCoordinator.updateResourcePolicy()
        rebuildMenu()
    }

    @objc
    private func toggleInteractiveObjects() {
        if !preferences.interactiveObjectsEnabled,
           currentProject?.interactiveObjects.isEmpty != false {
            presentMessage(
                title: "No Interactive Objects",
                message: "Add an image object to the current wallpaper first."
            )
            return
        }

        preferences.interactiveObjectsEnabled.toggle()
        renderCoordinator.updateInteractiveObjects()
        rebuildMenu()
    }

    @objc
    private func addInteractiveImageObject() {
        guard let project = currentProject else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Add Image Object"
        panel.prompt = "Add"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK,
              let imageURL = panel.url
        else {
            return
        }

        do {
            try InteractiveProjectEditor.addImageObject(imageURL: imageURL, to: project)
            preferences.interactiveObjectsEnabled = true
            reloadLibrary()
            if let updatedProject = self.project(rootPath: project.rootURL.path) {
                apply(updatedProject, resetUserPause: false)
            }
            renderCoordinator.updateInteractiveObjects()
            rebuildMenu()
        } catch {
            presentError(error)
        }
    }

    @objc
    private func addInteractiveVideoObject() {
        guard let project = currentProject else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Add Video Object"
        panel.prompt = "Add"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]

        guard panel.runModal() == .OK,
              let videoURL = panel.url
        else {
            return
        }

        do {
            try InteractiveProjectEditor.addVideoObject(videoURL: videoURL, to: project)
            preferences.interactiveObjectsEnabled = true
            reloadAndReapply(projectRootPath: project.rootURL.path)
        } catch {
            presentError(error)
        }
    }

    @objc
    private func addInteractiveLive2DObject() {
        guard let project = currentProject else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Add Live2D Web Object"
        panel.message = "Choose the HTML entry file for a local Live2D Web/Cubism bundle."
        panel.prompt = "Add"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.html]

        guard panel.runModal() == .OK,
              let entryURL = panel.url
        else {
            return
        }

        do {
            try InteractiveProjectEditor.addLive2DWebObject(entryHTMLURL: entryURL, to: project)
            preferences.interactiveObjectsEnabled = true
            reloadAndReapply(projectRootPath: project.rootURL.path)
        } catch {
            presentError(error)
        }
    }

    @objc
    private func removeInteractiveObjectFromMenu(_ sender: NSMenuItem) {
        guard let project = currentProject,
              let objectID = sender.representedObject as? String
        else {
            return
        }

        do {
            try InteractiveProjectEditor.removeObject(objectID: objectID, from: project)
            preferences.clearInteractiveObjectFrameOverride(projectRootPath: project.rootURL.path, objectID: objectID)
            reloadLibrary()
            if let updatedProject = self.project(rootPath: project.rootURL.path) {
                preferences.interactiveObjectsEnabled = !updatedProject.interactiveObjects.isEmpty
                apply(updatedProject, resetUserPause: false)
            }
            renderCoordinator.updateInteractiveObjects()
            rebuildMenu()
        } catch {
            presentError(error)
        }
    }

    @objc
    private func resetInteractiveObjectPositions() {
        renderCoordinator.resetInteractiveObjectFramesForActiveProject()
        rebuildMenu()
    }

    @objc
    private func openSteamWorkshop() {
        SteamWorkshopSupport.openWorkshop()
    }

    @objc
    private func openSteamWorkshopItem() {
        guard let input = promptForText(
            title: "Open Workshop Item",
            message: "Paste a Steam Workshop URL or item ID.",
            placeholder: "https://steamcommunity.com/sharedfiles/filedetails/?id=..."
        ) else {
            return
        }

        do {
            try SteamWorkshopSupport.openWorkshopItem(idOrURL: input)
        } catch {
            presentError(error)
        }
    }

    @objc
    private func importLocalSteamWorkshopFolder() {
        if let workshopURL = SteamWorkshopSupport.existingWorkshopFolderURL() {
            preferences.libraryRoots.appendUnique(contentsOf: [workshopURL])
            reloadLibrary()
            rebuildMenu()
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Import Wallpaper Engine Workshop Folder"
        panel.message = "Choose the Steam workshop/content/431960 folder or any folder containing Wallpaper Engine project.json files."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK,
              let url = panel.url
        else {
            return
        }

        preferences.libraryRoots.appendUnique(contentsOf: [url.standardizedFileURL])
        reloadLibrary()
        rebuildMenu()
    }

    @objc
    private func downloadSteamWorkshopItemWithSteamCMDLogin() {
        guard let input = promptForText(
            title: "Download Workshop Item",
            message: "Paste a Steam Workshop URL or item ID. Use a Steam account that owns Wallpaper Engine. Credentials are passed to local SteamCMD only and are not saved.",
            placeholder: "published file ID"
        ), let account = promptForSteamCMDAccount() else {
            return
        }

        downloadSteamWorkshopItemWithSteamCMD(idOrURL: input, loginMode: .account(account))
    }

    private func downloadSteamWorkshopItemWithSteamCMD(
        idOrURL: String,
        loginMode: SteamWorkshopSupport.SteamCMDLoginMode
    ) {
        SteamWorkshopSupport.downloadItemWithSteamCMD(idOrURL: idOrURL, loginMode: loginMode) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                switch result {
                case let .success(itemURL):
                    self.preferences.libraryRoots.appendUnique(contentsOf: [itemURL.standardizedFileURL])
                    self.reloadLibrary()
                    self.rebuildMenu()
                    self.presentMessage(title: "Workshop Item Imported", message: itemURL.path)
                case let .failure(error):
                    self.presentError(error)
                }
            }
        }
    }

    @objc
    private func clearWallpaper() {
        preferences.autoSwitchMode = .off
        renderCoordinator.clear()
        rebuildMenu()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }

    private func apply(_ project: WallpaperProject, resetUserPause: Bool = true) {
        do {
            try renderCoordinator.apply(project)
            if resetUserPause {
                isUserPaused = false
            }
            updatePauseReasons()
            rebuildMenu()
        } catch {
            presentError(error)
        }
    }

    private func setLightWallpaper(_ project: WallpaperProject) {
        preferences.lightWallpaperRootPath = project.rootURL.path
        applyAutomaticWallpaperIfNeeded()
        rebuildMenu()
    }

    private func setDarkWallpaper(_ project: WallpaperProject) {
        preferences.darkWallpaperRootPath = project.rootURL.path
        applyAutomaticWallpaperIfNeeded()
        rebuildMenu()
    }

    private func startAutomaticSwitching() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: .appleInterfaceThemeChanged,
            object: nil
        )

        automaticSwitchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyAutomaticWallpaperIfNeeded()
            }
        }
        automaticSwitchTimer?.tolerance = 10
    }

    @objc
    private func systemAppearanceChanged() {
        applyAutomaticWallpaperIfNeeded()
        rebuildMenu()
    }

    private func applyAutomaticWallpaperIfNeeded() {
        guard let targetPath = automaticTargetRootPath(),
              let project = project(rootPath: targetPath),
              project.isPlayableNow,
              preferences.selectedWallpaperRootPath != project.rootURL.path
        else {
            return
        }

        apply(project, resetUserPause: false)
    }

    private func automaticTargetRootPath() -> String? {
        switch preferences.autoSwitchMode {
        case .off:
            return nil
        case .systemAppearance:
            return isSystemDarkAppearance ? preferences.darkWallpaperRootPath : preferences.lightWallpaperRootPath
        case .dayNightSchedule:
            return isDaytimeNow ? preferences.lightWallpaperRootPath : preferences.darkWallpaperRootPath
        }
    }

    private var isSystemDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var isDaytimeNow: Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minuteOfDay = ((components.hour ?? 0) * 60) + (components.minute ?? 0)
        let dayStart = preferences.dayStartMinute
        let nightStart = preferences.nightStartMinute

        if dayStart <= nightStart {
            return minuteOfDay >= dayStart && minuteOfDay < nightStart
        }
        return minuteOfDay >= dayStart || minuteOfDay < nightStart
    }

    private func updatePauseReasons() {
        var reasons: Set<PauseReason> = []
        let powerState = powerManager.state

        if isUserPaused {
            reasons.insert(.user)
        }
        if powerState.isScreenLocked {
            reasons.insert(.screenLocked)
        }
        if powerState.areDisplaysSleeping {
            reasons.insert(.displaySleep)
        }
        if preferences.pauseOnBattery, powerState.isOnBatteryPower {
            reasons.insert(.battery)
        }
        if preferences.pauseOnLowPowerMode, powerState.isLowPowerModeEnabled {
            reasons.insert(.lowPowerMode)
        }

        renderCoordinator.setGlobalPauseReasons(reasons)
    }

    private func normalizedImportRoot(_ url: URL) -> URL {
        if url.lastPathComponent == "project.json" {
            return url.deletingLastPathComponent().standardizedFileURL
        }
        return url.standardizedFileURL
    }

    private func deletionTargetURL(for project: WallpaperProject) -> URL {
        if project.projectURL == nil, let entryURL = project.entryURL {
            return entryURL.standardizedFileURL
        }
        return project.rootURL.standardizedFileURL
    }

    private func removeDeletedProjectFromLibraryRoots(project: WallpaperProject, deletedURL: URL) {
        let removablePaths = Set([
            deletedURL.standardizedFileURL.path,
            project.projectURL?.standardizedFileURL.path,
            project.entryURL?.standardizedFileURL.path,
            project.rootURL.standardizedFileURL.path
        ].compactMap { $0 })

        preferences.libraryRoots = preferences.libraryRoots.filter {
            !removablePaths.contains($0.standardizedFileURL.path)
        }
    }

    private func confirmDelete(project: WallpaperProject, targetURL: URL) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Delete Wallpaper?"
        alert.informativeText = """
        \(project.title) will be moved to the Trash.

        \(targetURL.path)
        """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentError(_ error: Error) {
        NSApp.presentError(error)
    }

    private func presentMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func promptForText(title: String, message: String, placeholder: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)

        let input = PromptTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        input.placeholderString = placeholder

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func promptForSteamCMDAccount() -> SteamWorkshopSupport.SteamCMDAccount? {
        NSApp.activate(ignoringOtherApps: true)

        let usernameField = PromptTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        usernameField.placeholderString = "Steam username"

        let passwordField = PromptSecureTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        passwordField.placeholderString = "Steam password"

        let steamGuardField = PromptTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        steamGuardField.placeholderString = "Steam Guard code (optional)"

        let stack = NSStackView(views: [
            label("Username"),
            usernameField,
            label("Password"),
            passwordField,
            label("Steam Guard"),
            steamGuardField
        ])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        stack.setFrameSize(NSSize(width: 420, height: 156))

        for view in stack.views {
            view.widthAnchor.constraint(equalToConstant: 420).isActive = true
        }

        let alert = NSAlert()
        alert.messageText = "SteamCMD Login"
        alert.informativeText = "Use an account that owns Wallpaper Engine. Credentials are passed to local SteamCMD for this download only and are not stored."
        alert.accessoryView = stack
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = usernameField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        let username = usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        let steamGuardCode = steamGuardField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !username.isEmpty, !password.isEmpty else {
            return nil
        }

        return SteamWorkshopSupport.SteamCMDAccount(
            username: username,
            password: password,
            steamGuardCode: steamGuardCode.isEmpty ? nil : steamGuardCode
        )
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func reloadAndReapply(projectRootPath: String) {
        reloadLibrary()
        if let updatedProject = self.project(rootPath: projectRootPath) {
            apply(updatedProject, resetUserPause: false)
        }
        renderCoordinator.updateInteractiveObjects()
        rebuildMenu()
    }

    private func installEditingMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Wallpaper Engine Mac")
        appMenu.addItem(NSMenuItem(title: "Quit Wallpaper Engine Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

private final class PromptTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased()
        else {
            return super.performKeyEquivalent(with: event)
        }

        let action: Selector?
        switch key {
        case "x":
            action = #selector(NSText.cut(_:))
        case "c":
            action = #selector(NSText.copy(_:))
        case "v":
            action = #selector(NSText.paste(_:))
        case "a":
            action = #selector(NSText.selectAll(_:))
        default:
            action = nil
        }

        guard let action else {
            return super.performKeyEquivalent(with: event)
        }

        return NSApp.sendAction(action, to: nil, from: self)
    }
}

private final class PromptSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased()
        else {
            return super.performKeyEquivalent(with: event)
        }

        let action: Selector?
        switch key {
        case "x":
            action = #selector(NSText.cut(_:))
        case "c":
            action = #selector(NSText.copy(_:))
        case "v":
            action = #selector(NSText.paste(_:))
        case "a":
            action = #selector(NSText.selectAll(_:))
        default:
            action = nil
        }

        guard let action else {
            return super.performKeyEquivalent(with: event)
        }

        return NSApp.sendAction(action, to: nil, from: self)
    }
}

private extension NSMenuItem {
    convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject?) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
    }
}

private extension Array where Element == URL {
    mutating func appendUnique(contentsOf urls: [URL]) {
        var paths = Set(map { $0.standardizedFileURL.path })
        for url in urls {
            let standardized = url.standardizedFileURL
            if paths.insert(standardized.path).inserted {
                append(standardized)
            }
        }
    }
}

private extension Notification.Name {
    static let appleInterfaceThemeChanged = Notification.Name("AppleInterfaceThemeChangedNotification")
}
