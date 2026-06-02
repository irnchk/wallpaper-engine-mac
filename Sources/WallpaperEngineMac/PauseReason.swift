import Foundation

enum PauseReason: String, CaseIterable {
    case user
    case occluded
    case screenLocked
    case displaySleep
    case battery
    case lowPowerMode

    var label: String {
        switch self {
        case .user:
            return "Paused"
        case .occluded:
            return "Covered"
        case .screenLocked:
            return "Screen Locked"
        case .displaySleep:
            return "Display Sleeping"
        case .battery:
            return "On Battery"
        case .lowPowerMode:
            return "Low Power Mode"
        }
    }
}
