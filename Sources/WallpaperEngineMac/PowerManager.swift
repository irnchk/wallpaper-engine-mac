import AppKit
import IOKit.ps

@MainActor
final class PowerManager: NSObject {
    struct State: Equatable {
        var isScreenLocked = false
        var areDisplaysSleeping = false
        var isOnBatteryPower = false
        var isLowPowerModeEnabled = false
    }

    var onStateChanged: ((State) -> Void)?

    private(set) var state = State()
    private var pollTimer: Timer?
    private var powerSourceRunLoopSource: CFRunLoopSource?

    func start() {
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(displaysDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(displaysDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenDidLock),
            name: Notification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(processPowerStateChanged),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )

        installPowerSourceCallback()
        pollTimer = Timer.scheduledTimer(
            timeInterval: 30,
            target: self,
            selector: #selector(refreshPowerState),
            userInfo: nil,
            repeats: true
        )
        refreshPowerState()
    }

    deinit {
        pollTimer?.invalidate()
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc
    private func displaysDidSleep() {
        updateState { $0.areDisplaysSleeping = true }
    }

    @objc
    private func displaysDidWake() {
        updateState { $0.areDisplaysSleeping = false }
    }

    @objc
    private func screenDidLock() {
        updateState { $0.isScreenLocked = true }
    }

    @objc
    private func screenDidUnlock() {
        updateState { $0.isScreenLocked = false }
    }

    @objc
    private func processPowerStateChanged() {
        refreshPowerState()
    }

    @objc
    private func refreshPowerState() {
        updateState {
            $0.isOnBatteryPower = PowerManager.readOnBatteryPower()
            $0.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func updateState(_ mutate: (inout State) -> Void) {
        var newState = state
        mutate(&newState)
        guard newState != state else {
            return
        }

        state = newState
        onStateChanged?(newState)
    }

    private func installPowerSourceCallback() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else {
                return
            }
            let manager = Unmanaged<PowerManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                manager.refreshPowerState()
            }
        }, context)?.takeRetainedValue() else {
            return
        }

        powerSourceRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private nonisolated static func readOnBatteryPower() -> Bool {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as NSArray

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)
                .takeUnretainedValue() as? [String: Any],
                let state = description[kIOPSPowerSourceStateKey] as? String
            else {
                continue
            }

            if state == kIOPSBatteryPowerValue {
                return true
            }
        }

        return false
    }
}
