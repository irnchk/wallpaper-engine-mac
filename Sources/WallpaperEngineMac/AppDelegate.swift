import AppKit
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
        return controller
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        renderCoordinator = RenderCoordinator(preferences: preferences)
        renderCoordinator.onStatusChanged = { [weak self] in
            self?.rebuildMenu()
        }

        powerManager.onStateChanged = { [weak self] _ in
            self?.updatePauseReasons()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "WallpaperEngineMac")
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

        let titleItem = NSMenuItem(title: "WallpaperEngineMac", action: nil, keyEquivalent: "")
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
        if project.isPlayableNow {
            return project.title
        }
        return "\(project.title) (\(project.type.rawValue))"
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

    private func presentError(_ error: Error) {
        NSApp.presentError(error)
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
