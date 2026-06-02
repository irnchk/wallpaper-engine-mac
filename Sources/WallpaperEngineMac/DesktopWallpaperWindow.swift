import AppKit

final class DesktopWallpaperWindow: NSWindow {
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
        canHide = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
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
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func move(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }
}
