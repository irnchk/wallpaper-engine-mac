import AppKit

final class DesktopWallpaperWindow: NSWindow {
    private let passiveLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    private let interactiveLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    private var objectInteractionEnabled = false

    var onCancelObjectInteraction: (() -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        title = "Wallpaper Engine Mac Desktop Wallpaper"
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

    override func keyDown(with event: NSEvent) {
        if objectInteractionEnabled, event.keyCode == 53 {
            onCancelObjectInteraction?()
            return
        }

        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if objectInteractionEnabled {
            onCancelObjectInteraction?()
            return
        }

        super.cancelOperation(sender)
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
