import AppKit

final class DesktopWallpaperWindow: NSWindow {
    private let passiveLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    private let interactiveLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    private var objectInteractionEnabled = false

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        title = "WallpaperEngineMac Desktop Wallpaper"
        isReleasedWhenClosed = false
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
        canHide = false
        level = passiveLevel
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        let rootView = NSView(frame: screen.frame)
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.black.cgColor
        contentView = rootView
    }

    override var canBecomeKey: Bool {
        objectInteractionEnabled
    }

    override var canBecomeMain: Bool {
        objectInteractionEnabled
    }

    func move(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }

    func setObjectInteractionEnabled(_ enabled: Bool) {
        objectInteractionEnabled = enabled
        ignoresMouseEvents = !enabled
        acceptsMouseMovedEvents = enabled
        level = enabled ? interactiveLevel : passiveLevel

        if enabled {
            makeKeyAndOrderFront(nil)
        } else {
            resignKey()
            orderBack(nil)
        }
    }
}
