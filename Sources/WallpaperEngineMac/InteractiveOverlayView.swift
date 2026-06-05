import AppKit
import AVFoundation
import WebKit
import WallpaperEngineCore

@MainActor
final class InteractiveOverlayView: NSView {
    private var objectViews: [InteractiveObjectView] = []
    private var frameProvider: ((String) -> WallpaperInteractiveFrame?)?
    private var onFrameChanged: ((String, WallpaperInteractiveFrame) -> Void)?

    var objectInteractionEnabled = false {
        didSet {
            for objectView in objectViews {
                objectView.objectInteractionEnabled = objectInteractionEnabled
            }
            updateEditModeChrome()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        updateEditModeChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(
        objects: [WallpaperInteractiveObject],
        projectRootURL: URL,
        frameProvider: @escaping (String) -> WallpaperInteractiveFrame?,
        onFrameChanged: @escaping (String, WallpaperInteractiveFrame) -> Void
    ) {
        self.frameProvider = frameProvider
        self.onFrameChanged = onFrameChanged

        for objectView in objectViews {
            objectView.removeFromSuperview()
        }
        objectViews.removeAll()

        for object in objects {
            guard let fileURL = object.fileURL(relativeTo: projectRootURL),
                  let contentView = contentView(for: object, fileURL: fileURL)
            else {
                continue
            }

            let objectView = InteractiveObjectView(
                object: object,
                contentView: contentView,
                normalizedFrame: sanitized(frameProvider(object.id) ?? object.frame),
                onFrameChanged: onFrameChanged
            )
            objectView.objectInteractionEnabled = objectInteractionEnabled
            objectViews.append(objectView)
            addSubview(objectView)
        }

        isHidden = objectViews.isEmpty
        updateEditModeChrome()
        needsLayout = true
    }

    func start() {
        for objectView in objectViews {
            objectView.start()
        }
    }

    func pause() {
        for objectView in objectViews {
            objectView.pause()
        }
    }

    func teardown() {
        for objectView in objectViews {
            objectView.teardown()
        }
        objectViews.removeAll()
    }

    func resetObjectFrames() {
        for objectView in objectViews {
            objectView.normalizedFrame = sanitized(objectView.object.frame)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        for objectView in objectViews where !objectView.isDragging {
            objectView.frame = rect(for: objectView.normalizedFrame, in: bounds)
        }
    }

    private func contentView(for object: WallpaperInteractiveObject, fileURL: URL) -> NSView? {
        if object.isImageLike {
            guard let image = NSImage(contentsOf: fileURL) else {
                return nil
            }
            let imageView = NSImageView()
            imageView.image = image
            imageView.imageAlignment = .alignCenter
            imageView.imageScaling = .scaleProportionallyUpOrDown
            return imageView
        }

        if object.isVideoLike {
            guard SupportedVideoFile.videoExtensions.contains(fileURL.pathExtension.lowercased()) else {
                return nil
            }
            return VideoObjectContentView(fileURL: fileURL)
        }

        if object.isLive2DLike {
            let ext = fileURL.pathExtension.lowercased()
            guard ext == "html" || ext == "htm" else {
                return nil
            }
            return Live2DWebObjectContentView(entryURL: fileURL)
        }

        return nil
    }

    private func rect(for normalizedFrame: WallpaperInteractiveFrame, in bounds: CGRect) -> CGRect {
        let frame = sanitized(normalizedFrame)
        let width = bounds.width * frame.width
        let height = bounds.height * frame.height
        let x = bounds.minX + bounds.width * frame.x
        let yFromTop = bounds.height * frame.y
        let y = bounds.maxY - yFromTop - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func updateEditModeChrome() {
        guard let layer else {
            return
        }

        if objectInteractionEnabled, !objectViews.isEmpty {
            layer.borderWidth = 2
            layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor
        } else {
            layer.borderWidth = 0
            layer.borderColor = NSColor.clear.cgColor
        }
    }
}

@MainActor
private protocol InteractiveObjectContentControlling: AnyObject {
    func start()
    func pause()
    func teardown()
}

@MainActor
private final class InteractiveObjectView: NSView {
    let object: WallpaperInteractiveObject

    var normalizedFrame: WallpaperInteractiveFrame
    var objectInteractionEnabled = false {
        didSet {
            updateVisualState()
        }
    }
    private(set) var isDragging = false

    private let contentView: NSView
    private let onFrameChanged: (String, WallpaperInteractiveFrame) -> Void
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    private var dragStartLocation = CGPoint.zero
    private var dragStartFrame = CGRect.zero

    init(
        object: WallpaperInteractiveObject,
        contentView: NSView,
        normalizedFrame: WallpaperInteractiveFrame,
        onFrameChanged: @escaping (String, WallpaperInteractiveFrame) -> Void
    ) {
        self.object = object
        self.contentView = contentView
        self.normalizedFrame = normalizedFrame
        self.onFrameChanged = onFrameChanged

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        layer?.cornerRadius = object.cornerRadius
        layer?.masksToBounds = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0
        layer?.shadowRadius = 0
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        alphaValue = max(0.05, min(object.opacity, 1))

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateVisualState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func start() {
        (contentView as? InteractiveObjectContentControlling)?.start()
    }

    func pause() {
        (contentView as? InteractiveObjectContentControlling)?.pause()
    }

    func teardown() {
        (contentView as? InteractiveObjectContentControlling)?.teardown()
        removeFromSuperview()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        self.trackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        guard objectInteractionEnabled else {
            return
        }
        isHovered = true
        updateVisualState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateVisualState()
    }

    override func mouseDown(with event: NSEvent) {
        guard objectInteractionEnabled else {
            return
        }
        isPressed = true
        isDragging = false
        dragStartLocation = superview?.convert(event.locationInWindow, from: nil) ?? .zero
        dragStartFrame = frame
        updateVisualState()
    }

    override func mouseDragged(with event: NSEvent) {
        guard objectInteractionEnabled, object.draggable, let superview else {
            return
        }

        isDragging = true
        let currentLocation = superview.convert(event.locationInWindow, from: nil)
        let dx = currentLocation.x - dragStartLocation.x
        let dy = currentLocation.y - dragStartLocation.y
        var nextFrame = dragStartFrame.offsetBy(dx: dx, dy: dy)
        nextFrame.origin.x = min(max(nextFrame.origin.x, superview.bounds.minX), superview.bounds.maxX - nextFrame.width)
        nextFrame.origin.y = min(max(nextFrame.origin.y, superview.bounds.minY), superview.bounds.maxY - nextFrame.height)
        frame = nextFrame
        normalizedFrame = normalized(frame: nextFrame, in: superview.bounds)
        onFrameChanged(object.id, normalizedFrame)
    }

    override func mouseUp(with event: NSEvent) {
        guard objectInteractionEnabled else {
            return
        }
        isPressed = false
        if isDragging {
            onFrameChanged(object.id, normalizedFrame)
        } else {
            flashClickFeedback()
        }
        isDragging = false
        updateVisualState()
    }

    private func normalized(frame: CGRect, in bounds: CGRect) -> WallpaperInteractiveFrame {
        guard bounds.width > 0, bounds.height > 0 else {
            return normalizedFrame
        }
        return sanitized(WallpaperInteractiveFrame(
            x: (frame.minX - bounds.minX) / bounds.width,
            y: (bounds.maxY - frame.maxY) / bounds.height,
            width: frame.width / bounds.width,
            height: frame.height / bounds.height
        ))
    }

    private func updateVisualState() {
        guard let layer else {
            return
        }

        if objectInteractionEnabled {
            layer.borderWidth = isPressed ? 3 : 2
            layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(isHovered ? 0.95 : 0.65).cgColor
            layer.shadowOpacity = isHovered || isPressed ? 0.28 : 0.16
            layer.shadowRadius = isHovered || isPressed ? 14 : 8
            layer.backgroundColor = NSColor.black.withAlphaComponent(isHovered || isPressed ? 0.2 : 0.12).cgColor
        } else {
            layer.borderWidth = 0
            layer.borderColor = NSColor.clear.cgColor
            layer.shadowOpacity = 0
            layer.shadowRadius = 0
            layer.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        }
    }

    private func flashClickFeedback() {
        guard objectInteractionEnabled else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            animator().alphaValue = max(0.35, alphaValue * 0.65)
        } completionHandler: { [weak self] in
            guard let self else {
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                self.animator().alphaValue = max(0.05, min(self.object.opacity, 1))
            }
        }
    }
}

@MainActor
private final class VideoObjectContentView: NSView, InteractiveObjectContentControlling {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    init(fileURL: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspectFill

        let player = AVQueuePlayer()
        let item = AVPlayerItem(url: fileURL)
        let looper = AVPlayerLooper(player: player, templateItem: item)
        player.actionAtItemEnd = .none
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        playerLayer.player = player
        self.player = player
        self.looper = looper
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func start() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func teardown() {
        player?.pause()
        player?.removeAllItems()
        playerLayer.player = nil
        looper = nil
        player = nil
    }
}

@MainActor
private final class Live2DWebObjectContentView: WKWebView, InteractiveObjectContentControlling {
    init(entryURL: URL) {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        super.init(frame: .zero, configuration: configuration)

        setValue(false, forKey: "drawsBackground")
        loadFileURL(entryURL, allowingReadAccessTo: entryURL.deletingLastPathComponent())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func start() {}

    func pause() {}

    func teardown() {
        stopLoading()
        loadHTMLString("", baseURL: nil)
    }
}

private func sanitized(_ frame: WallpaperInteractiveFrame) -> WallpaperInteractiveFrame {
    let width = min(max(frame.width, 0.02), 1)
    let height = min(max(frame.height, 0.02), 1)
    let x = min(max(frame.x, 0), 1 - width)
    let y = min(max(frame.y, 0), 1 - height)
    return WallpaperInteractiveFrame(x: x, y: y, width: width, height: height)
}
