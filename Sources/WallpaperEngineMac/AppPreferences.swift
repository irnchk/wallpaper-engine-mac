import Foundation
import WallpaperEngineCore

enum WallpaperAutoSwitchMode: String, CaseIterable {
    case off
    case systemAppearance
    case dayNightSchedule

    var menuTitle: String {
        switch self {
        case .off:
            return "Off"
        case .systemAppearance:
            return "Follow System Appearance"
        case .dayNightSchedule:
            return "Follow Day/Night Schedule"
        }
    }
}

@MainActor
final class AppPreferences {
    private enum Key {
        static let libraryRoots = "libraryRoots"
        static let selectedWallpaperRootPath = "selectedWallpaperRootPath"
        static let lightWallpaperRootPath = "lightWallpaperRootPath"
        static let darkWallpaperRootPath = "darkWallpaperRootPath"
        static let autoSwitchMode = "autoSwitchMode"
        static let dayStartMinute = "dayStartMinute"
        static let nightStartMinute = "nightStartMinute"
        static let muted = "muted"
        static let audioResponsiveEnabled = "audioResponsiveEnabled"
        static let pauseOnBattery = "pauseOnBattery"
        static let pauseOnLowPowerMode = "pauseOnLowPowerMode"
        static let releaseDecoderOnLongPause = "releaseDecoderOnLongPause"
        static let interactiveObjectsEnabled = "interactiveObjectsEnabled"
        static let interactiveObjectFrameOverrides = "interactiveObjectFrameOverrides"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    var libraryRoots: [URL] {
        get {
            defaults.stringArray(forKey: Key.libraryRoots)?.map(URL.init(fileURLWithPath:)) ?? []
        }
        set {
            let uniquePaths = Array(Set(newValue.map { $0.standardizedFileURL.path })).sorted()
            defaults.set(uniquePaths, forKey: Key.libraryRoots)
        }
    }

    var selectedWallpaperRootPath: String? {
        get {
            defaults.string(forKey: Key.selectedWallpaperRootPath)
        }
        set {
            defaults.set(newValue, forKey: Key.selectedWallpaperRootPath)
        }
    }

    var lightWallpaperRootPath: String? {
        get {
            defaults.string(forKey: Key.lightWallpaperRootPath)
        }
        set {
            defaults.set(newValue, forKey: Key.lightWallpaperRootPath)
        }
    }

    var darkWallpaperRootPath: String? {
        get {
            defaults.string(forKey: Key.darkWallpaperRootPath)
        }
        set {
            defaults.set(newValue, forKey: Key.darkWallpaperRootPath)
        }
    }

    var autoSwitchMode: WallpaperAutoSwitchMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.autoSwitchMode),
                  let mode = WallpaperAutoSwitchMode(rawValue: rawValue)
            else {
                return .off
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.autoSwitchMode)
        }
    }

    var dayStartMinute: Int {
        get {
            defaults.integer(forKey: Key.dayStartMinute)
        }
        set {
            defaults.set(newValue, forKey: Key.dayStartMinute)
        }
    }

    var nightStartMinute: Int {
        get {
            defaults.integer(forKey: Key.nightStartMinute)
        }
        set {
            defaults.set(newValue, forKey: Key.nightStartMinute)
        }
    }

    var isMuted: Bool {
        get {
            defaults.bool(forKey: Key.muted)
        }
        set {
            defaults.set(newValue, forKey: Key.muted)
        }
    }

    var audioResponsiveEnabled: Bool {
        get {
            defaults.bool(forKey: Key.audioResponsiveEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.audioResponsiveEnabled)
        }
    }

    var pauseOnBattery: Bool {
        get {
            defaults.bool(forKey: Key.pauseOnBattery)
        }
        set {
            defaults.set(newValue, forKey: Key.pauseOnBattery)
        }
    }

    var pauseOnLowPowerMode: Bool {
        get {
            defaults.bool(forKey: Key.pauseOnLowPowerMode)
        }
        set {
            defaults.set(newValue, forKey: Key.pauseOnLowPowerMode)
        }
    }

    var releaseDecoderOnLongPause: Bool {
        get {
            defaults.bool(forKey: Key.releaseDecoderOnLongPause)
        }
        set {
            defaults.set(newValue, forKey: Key.releaseDecoderOnLongPause)
        }
    }

    var interactiveObjectsEnabled: Bool {
        get {
            defaults.bool(forKey: Key.interactiveObjectsEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.interactiveObjectsEnabled)
        }
    }

    func interactiveObjectFrameOverride(
        projectRootPath: String,
        objectID: String
    ) -> WallpaperInteractiveFrame? {
        interactiveObjectFrameOverrides.projects[projectRootPath]?[objectID]
    }

    func setInteractiveObjectFrameOverride(
        _ frame: WallpaperInteractiveFrame,
        projectRootPath: String,
        objectID: String
    ) {
        var store = interactiveObjectFrameOverrides
        var projectFrames = store.projects[projectRootPath] ?? [:]
        projectFrames[objectID] = frame
        store.projects[projectRootPath] = projectFrames
        interactiveObjectFrameOverrides = store
    }

    func clearInteractiveObjectFrameOverrides(projectRootPath: String) {
        var store = interactiveObjectFrameOverrides
        store.projects[projectRootPath] = nil
        interactiveObjectFrameOverrides = store
    }

    func clearInteractiveObjectFrameOverride(projectRootPath: String, objectID: String) {
        var store = interactiveObjectFrameOverrides
        store.projects[projectRootPath]?[objectID] = nil
        if store.projects[projectRootPath]?.isEmpty == true {
            store.projects[projectRootPath] = nil
        }
        interactiveObjectFrameOverrides = store
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.libraryRoots: [],
            Key.autoSwitchMode: WallpaperAutoSwitchMode.off.rawValue,
            Key.dayStartMinute: 6 * 60,
            Key.nightStartMinute: 18 * 60,
            Key.muted: true,
            Key.audioResponsiveEnabled: false,
            Key.pauseOnBattery: true,
            Key.pauseOnLowPowerMode: true,
            Key.releaseDecoderOnLongPause: true,
            Key.interactiveObjectsEnabled: false
        ])
    }

    private var interactiveObjectFrameOverrides: InteractiveObjectFrameOverrideStore {
        get {
            guard let data = defaults.data(forKey: Key.interactiveObjectFrameOverrides),
                  let store = try? JSONDecoder().decode(InteractiveObjectFrameOverrideStore.self, from: data)
            else {
                return InteractiveObjectFrameOverrideStore()
            }
            return store
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                return
            }
            defaults.set(data, forKey: Key.interactiveObjectFrameOverrides)
        }
    }
}

private struct InteractiveObjectFrameOverrideStore: Codable {
    var projects: [String: [String: WallpaperInteractiveFrame]] = [:]
}
