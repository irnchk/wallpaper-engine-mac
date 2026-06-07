import AppKit
import WallpaperEngineCore

@MainActor
final class RenderCoordinator {
    enum CoordinatorError: LocalizedError {
        case missingEntry(WallpaperProject)
        case unsupported(WallpaperProject)

        var errorDescription: String? {
            switch self {
            case let .missingEntry(project):
                return "Missing wallpaper file for \(project.title)."
            case let .unsupported(project):
                return "\(project.title) cannot be played yet. \(project.supportStatus.label)"
            }
        }
    }

    var onStatusChanged: (() -> Void)?

    private let preferences: AppPreferences
    private let audioLevelMonitor = AudioLevelMonitor()
    private var hosts: [CGDirectDisplayID: DesktopWallpaperHost] = [:]
    private var activeProject: WallpaperProject?
    private var globalPauseReasons: Set<PauseReason> = []

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    var statusDescription: String {
        guard let activeProject else {
            return "No wallpaper applied"
        }

        let audioSuffix = activeProject.usesAudioResponsiveOverlay || preferences.audioResponsiveEnabled
            ? " + Audio Responsive"
            : ""
        let reasons = effectivePauseReasons
        if reasons.isEmpty {
            return "Playing: \(activeProject.title)\(audioSuffix)"
        }

        let reasonText = reasons.map(\.label).sorted().joined(separator: ", ")
        return "Paused: \(reasonText)\(audioSuffix)"
    }

    private var effectivePauseReasons: Set<PauseReason> {
        var reasons = globalPauseReasons
        if hosts.values.contains(where: { !$0.isOccludedVisible }) {
            reasons.insert(.occluded)
        }
        return reasons
    }

    func start() {
        audioLevelMonitor.onLevelChanged = { [weak self] level in
            Task { @MainActor in
                self?.updateAudioResponsiveLevel(level)
            }
        }
        audioLevelMonitor.onError = { error in
            Task { @MainActor in
                NSApp.presentError(error)
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        rebuildScreens()
        updateAudioResponsive()
    }

    func apply(_ project: WallpaperProject) throws {
        guard project.isPlayableNow else {
            throw CoordinatorError.unsupported(project)
        }
        guard project.entryURL != nil else {
            throw CoordinatorError.missingEntry(project)
        }

        activeProject = project
        preferences.selectedWallpaperRootPath = project.rootURL.path
        rebuildScreens()
        updateAudioResponsive()
        updatePlayback()
        onStatusChanged?()
    }

    func clear() {
        activeProject = nil
        preferences.selectedWallpaperRootPath = nil
        teardownHosts()
        audioLevelMonitor.stop()
        onStatusChanged?()
    }

    func setGlobalPauseReasons(_ reasons: Set<PauseReason>) {
        globalPauseReasons = reasons
        updatePlayback()
        onStatusChanged?()
    }

    func updateMuted() {
        for host in hosts.values {
            host.renderer?.setMuted(preferences.isMuted)
        }
    }

    func updateResourcePolicy() {
        for host in hosts.values {
            host.renderer?.setReleaseResourcesWhilePaused(preferences.releaseDecoderOnLongPause)
        }
    }

    func updateInteractiveObjects() {
        for host in hosts.values {
            host.updateObjectInteractionEnabled()
        }
    }

    func updateAudioResponsive() {
        for host in hosts.values {
            host.updateAudioResponsiveEnabled()
        }

        if hosts.values.contains(where: \.isAudioResponsiveEnabled) {
            audioLevelMonitor.start()
        } else {
            audioLevelMonitor.stop()
            updateAudioResponsiveLevel(AudioResponsiveLevel(value: 0))
        }
    }

    func resetInteractiveObjectFramesForActiveProject() {
        guard let activeProject else {
            return
        }

        preferences.clearInteractiveObjectFrameOverrides(projectRootPath: activeProject.rootURL.path)
        for host in hosts.values where host.projectRootPath == activeProject.rootURL.path {
            host.renderer?.resetInteractiveObjectFrames()
        }
    }

    @objc
    private func screenParametersChanged() {
        rebuildScreens()
    }

    private func rebuildScreens() {
        guard let activeProject else {
            teardownHosts()
            audioLevelMonitor.stop()
            return
        }

        let currentIDs = Set(NSScreen.screens.compactMap(\.displayID))
        for (displayID, host) in hosts where !currentIDs.contains(displayID) {
            host.teardown()
            hosts.removeValue(forKey: displayID)
        }

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else {
                continue
            }

            if let host = hosts[displayID] {
                host.move(to: screen)
                if host.needsProjectReplacement(activeProject) {
                    do {
                        try host.replaceProject(
                            activeProject,
                            muted: preferences.isMuted,
                            releaseResourcesWhilePaused: preferences.releaseDecoderOnLongPause
                        )
                    } catch {
                        NSApp.presentError(error)
                    }
                } else {
                    host.renderer?.setReleaseResourcesWhilePaused(preferences.releaseDecoderOnLongPause)
                    host.updateAudioResponsiveEnabled()
                }
            } else {
                do {
                    hosts[displayID] = try DesktopWallpaperHost(
                        screen: screen,
                        project: activeProject,
                        preferences: preferences,
                        muted: preferences.isMuted,
                        releaseResourcesWhilePaused: preferences.releaseDecoderOnLongPause,
                        onOcclusionChanged: { [weak self] in
                            self?.updatePlayback()
                            self?.onStatusChanged?()
                        },
                        onInteractionEditingExited: { [weak self] in
                            self?.onStatusChanged?()
                        }
                    )
                } catch {
                    NSApp.presentError(error)
                }
            }
        }

        updatePlayback()
    }

    private func updatePlayback() {
        let shouldPlayGlobally = globalPauseReasons.isEmpty
        for host in hosts.values {
            host.updatePlayback(shouldPlayGlobally: shouldPlayGlobally)
        }
    }

    private func teardownHosts() {
        for host in hosts.values {
            host.teardown()
        }
        hosts.removeAll()
    }

    private func updateAudioResponsiveLevel(_ level: AudioResponsiveLevel) {
        for host in hosts.values {
            host.renderer?.updateAudioResponsiveLevel(level)
        }
    }
}

@MainActor
private final class DesktopWallpaperHost {
    let window: DesktopWallpaperWindow
    var renderer: WallpaperRenderer?
    private let onOcclusionChanged: () -> Void
    private let onInteractionEditingExited: () -> Void
    private let preferences: AppPreferences
    private var project: WallpaperProject
    private(set) var projectRootPath: String
    private var projectHasInteractiveObjects: Bool

    var isOccludedVisible: Bool {
        window.occlusionState.contains(.visible)
    }

    init(
        screen: NSScreen,
        project: WallpaperProject,
        preferences: AppPreferences,
        muted: Bool,
        releaseResourcesWhilePaused: Bool,
        onOcclusionChanged: @escaping () -> Void,
        onInteractionEditingExited: @escaping () -> Void
    ) throws {
        guard let entryURL = project.entryURL else {
            throw RenderCoordinator.CoordinatorError.missingEntry(project)
        }

        self.window = DesktopWallpaperWindow(screen: screen)
        self.onOcclusionChanged = onOcclusionChanged
        self.onInteractionEditingExited = onInteractionEditingExited
        self.preferences = preferences
        self.project = project
        self.projectRootPath = project.rootURL.path
        self.projectHasInteractiveObjects = !project.interactiveObjects.isEmpty
        self.renderer = Self.makeRenderer(
            project: project,
            fileURL: entryURL,
            muted: muted,
            releaseResourcesWhilePaused: releaseResourcesWhilePaused,
            interactiveObjectsEnabled: objectInteractionEnabled(for: project),
            audioResponsiveEnabled: effectiveAudioResponsiveEnabled(for: project),
            frameProvider: { [preferences, projectRootPath = project.rootURL.path] objectID in
                preferences.interactiveObjectFrameOverride(projectRootPath: projectRootPath, objectID: objectID)
            },
            onFrameChanged: { [preferences, projectRootPath = project.rootURL.path] objectID, frame in
                preferences.setInteractiveObjectFrameOverride(frame, projectRootPath: projectRootPath, objectID: objectID)
            },
            onExitEditModeRequested: { [weak self] in
                self?.exitObjectInteractionEditing()
            }
        )

        window.onCancelObjectInteraction = { [weak self] in
            self?.exitObjectInteractionEditing()
        }
        installRendererView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )

        window.orderFrontRegardless()
        updateObjectInteractionEnabled()
    }

    func move(to screen: NSScreen) {
        window.move(to: screen)
    }

    func needsProjectReplacement(_ nextProject: WallpaperProject) -> Bool {
        project != nextProject
    }

    func replaceProject(
        _ project: WallpaperProject,
        muted: Bool,
        releaseResourcesWhilePaused: Bool
    ) throws {
        guard let entryURL = project.entryURL else {
            throw RenderCoordinator.CoordinatorError.missingEntry(project)
        }

        renderer?.teardown()
        renderer = Self.makeRenderer(
            project: project,
            fileURL: entryURL,
            muted: muted,
            releaseResourcesWhilePaused: releaseResourcesWhilePaused,
            interactiveObjectsEnabled: objectInteractionEnabled(for: project),
            audioResponsiveEnabled: effectiveAudioResponsiveEnabled(for: project),
            frameProvider: { [preferences, projectRootPath = project.rootURL.path] objectID in
                preferences.interactiveObjectFrameOverride(projectRootPath: projectRootPath, objectID: objectID)
            },
            onFrameChanged: { [preferences, projectRootPath = project.rootURL.path] objectID, frame in
                preferences.setInteractiveObjectFrameOverride(frame, projectRootPath: projectRootPath, objectID: objectID)
            },
            onExitEditModeRequested: { [weak self] in
                self?.exitObjectInteractionEditing()
            }
        )
        self.project = project
        projectRootPath = project.rootURL.path
        projectHasInteractiveObjects = !project.interactiveObjects.isEmpty
        installRendererView()
        updateObjectInteractionEnabled()
    }

    func updatePlayback(shouldPlayGlobally: Bool) {
        guard shouldPlayGlobally, isOccludedVisible else {
            renderer?.pause()
            return
        }
        renderer?.start()
    }

    func teardown() {
        NotificationCenter.default.removeObserver(self)
        renderer?.teardown()
        renderer = nil
        window.setObjectInteractionEnabled(false)
        window.orderOut(nil)
        window.close()
    }

    func updateObjectInteractionEnabled() {
        let enabled = preferences.interactiveObjectsEnabled && projectHasInteractiveObjects
        window.setObjectInteractionEnabled(enabled)
        renderer?.setInteractiveObjectsEnabled(enabled)
    }

    func updateAudioResponsiveEnabled() {
        renderer?.setAudioResponsiveEnabled(isAudioResponsiveEnabled)
    }

    var isAudioResponsiveEnabled: Bool {
        effectiveAudioResponsiveEnabled(for: project)
    }

    @objc
    private func occlusionChanged() {
        onOcclusionChanged()
    }

    private func installRendererView() {
        guard let contentView = window.contentView,
              let rendererView = renderer?.view
        else {
            return
        }

        rendererView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rendererView)
        NSLayoutConstraint.activate([
            rendererView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rendererView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rendererView.topAnchor.constraint(equalTo: contentView.topAnchor),
            rendererView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func objectInteractionEnabled(for project: WallpaperProject) -> Bool {
        preferences.interactiveObjectsEnabled && !project.interactiveObjects.isEmpty
    }

    private func effectiveAudioResponsiveEnabled(for project: WallpaperProject) -> Bool {
        preferences.audioResponsiveEnabled || project.usesAudioResponsiveOverlay
    }

    private func exitObjectInteractionEditing() {
        guard preferences.interactiveObjectsEnabled else {
            return
        }

        preferences.interactiveObjectsEnabled = false
        updateObjectInteractionEnabled()
        onInteractionEditingExited()
    }

    private static func makeRenderer(
        project: WallpaperProject,
        fileURL: URL,
        muted: Bool,
        releaseResourcesWhilePaused: Bool,
        interactiveObjectsEnabled: Bool,
        audioResponsiveEnabled: Bool,
        frameProvider: @escaping (String) -> WallpaperInteractiveFrame?,
        onFrameChanged: @escaping (String, WallpaperInteractiveFrame) -> Void,
        onExitEditModeRequested: @escaping () -> Void
    ) -> WallpaperRenderer {
        let packagedScene = ScenePackageSupport.renderableScene(for: project)
        let renderFileURL = packagedScene?.backgroundImageURL ?? fileURL
        let audioResponsiveStyle = packagedScene?.audioStyle ?? .systemDefault

        if SupportedWebFile.isKnownWebEntryFile(renderFileURL) {
            return WebWallpaperRenderer(
                project: project,
                fileURL: renderFileURL,
                interactiveObjectsEnabled: interactiveObjectsEnabled,
                audioResponsiveEnabled: audioResponsiveEnabled,
                audioResponsiveStyle: audioResponsiveStyle,
                frameProvider: frameProvider,
                onFrameChanged: onFrameChanged,
                onExitEditModeRequested: onExitEditModeRequested
            )
        }

        if SupportedStillOrAnimatedImageFile.isKnownImageFile(renderFileURL) {
            return ImageWallpaperRenderer(
                project: project,
                fileURL: renderFileURL,
                interactiveObjectsEnabled: interactiveObjectsEnabled,
                audioResponsiveEnabled: audioResponsiveEnabled,
                audioResponsiveStyle: audioResponsiveStyle,
                frameProvider: frameProvider,
                onFrameChanged: onFrameChanged,
                onExitEditModeRequested: onExitEditModeRequested
            )
        }

        if SupportedScenePackageFile.isKnownScenePackageFile(renderFileURL) {
            return ScenePackagePlaceholderRenderer(project: project)
        }

        return VideoWallpaperRenderer(
            project: project,
            fileURL: renderFileURL,
            muted: muted,
            releaseResourcesWhilePaused: releaseResourcesWhilePaused,
            interactiveObjectsEnabled: interactiveObjectsEnabled,
            audioResponsiveEnabled: audioResponsiveEnabled,
            audioResponsiveStyle: audioResponsiveStyle,
            frameProvider: frameProvider,
            onFrameChanged: onFrameChanged,
            onExitEditModeRequested: onExitEditModeRequested
        )
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
