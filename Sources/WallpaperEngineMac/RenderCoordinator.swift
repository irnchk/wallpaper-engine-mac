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

        let reasons = effectivePauseReasons
        if reasons.isEmpty {
            return "Playing: \(activeProject.title)"
        }

        let reasonText = reasons.map(\.label).sorted().joined(separator: ", ")
        return "Paused: \(reasonText)"
    }

    private var effectivePauseReasons: Set<PauseReason> {
        var reasons = globalPauseReasons
        if hosts.values.contains(where: { !$0.isOccludedVisible }) {
            reasons.insert(.occluded)
        }
        return reasons
    }

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        rebuildScreens()
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
        updatePlayback()
        onStatusChanged?()
    }

    func clear() {
        activeProject = nil
        preferences.selectedWallpaperRootPath = nil
        teardownHosts()
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

    @objc
    private func screenParametersChanged() {
        rebuildScreens()
    }

    private func rebuildScreens() {
        guard let activeProject else {
            teardownHosts()
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
                if host.projectRootPath != activeProject.rootURL.path {
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
                }
            } else {
                do {
                    hosts[displayID] = try DesktopWallpaperHost(
                        screen: screen,
                        project: activeProject,
                        muted: preferences.isMuted,
                        releaseResourcesWhilePaused: preferences.releaseDecoderOnLongPause,
                        onOcclusionChanged: { [weak self] in
                            self?.updatePlayback()
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
}

@MainActor
private final class DesktopWallpaperHost {
    let window: DesktopWallpaperWindow
    var renderer: WallpaperRenderer?
    private let onOcclusionChanged: () -> Void
    private(set) var projectRootPath: String

    var isOccludedVisible: Bool {
        window.occlusionState.contains(.visible)
    }

    init(
        screen: NSScreen,
        project: WallpaperProject,
        muted: Bool,
        releaseResourcesWhilePaused: Bool,
        onOcclusionChanged: @escaping () -> Void
    ) throws {
        guard let entryURL = project.entryURL else {
            throw RenderCoordinator.CoordinatorError.missingEntry(project)
        }

        self.window = DesktopWallpaperWindow(screen: screen)
        self.onOcclusionChanged = onOcclusionChanged
        self.projectRootPath = project.rootURL.path
        self.renderer = VideoWallpaperRenderer(
            fileURL: entryURL,
            muted: muted,
            releaseResourcesWhilePaused: releaseResourcesWhilePaused
        )

        installRendererView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )

        window.orderFrontRegardless()
        window.orderBack(nil)
    }

    func move(to screen: NSScreen) {
        window.move(to: screen)
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
        renderer = VideoWallpaperRenderer(
            fileURL: entryURL,
            muted: muted,
            releaseResourcesWhilePaused: releaseResourcesWhilePaused
        )
        projectRootPath = project.rootURL.path
        installRendererView()
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
        window.orderOut(nil)
        window.close()
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
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
