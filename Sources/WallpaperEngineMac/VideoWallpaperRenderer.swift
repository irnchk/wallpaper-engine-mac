import AppKit
import AVFoundation
import QuartzCore
import WallpaperEngineCore

@MainActor
protocol WallpaperRenderer: AnyObject {
    var view: NSView { get }

    func start()
    func pause()
    func teardown()
    func setMuted(_ muted: Bool)
    func setReleaseResourcesWhilePaused(_ enabled: Bool)
    func setInteractiveObjectsEnabled(_ enabled: Bool)
    func resetInteractiveObjectFrames()
}

@MainActor
final class VideoWallpaperRenderer: NSObject, WallpaperRenderer {
    let view: NSView

    private let playerLayer: AVPlayerLayer
    private let overlayView: InteractiveOverlayView
    private let fileURL: URL
    private let pauseTeardownDelay: TimeInterval

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var pauseTeardownTimer: Timer?
    private var muted: Bool
    private var releaseResourcesWhilePaused: Bool
    private var resumeTime = CMTime.zero

    init(
        project: WallpaperProject,
        fileURL: URL,
        muted: Bool,
        releaseResourcesWhilePaused: Bool,
        interactiveObjectsEnabled: Bool,
        frameProvider: @escaping (String) -> WallpaperInteractiveFrame?,
        onFrameChanged: @escaping (String, WallpaperInteractiveFrame) -> Void,
        pauseTeardownDelay: TimeInterval = 60
    ) {
        let containerView = NSView(frame: .zero)
        let playerView = PlayerView(frame: .zero)
        let overlayView = InteractiveOverlayView(frame: .zero)

        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor
        playerView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(playerView)
        containerView.addSubview(overlayView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.view = containerView
        self.playerLayer = playerView.playerLayer
        self.overlayView = overlayView
        self.fileURL = fileURL
        self.muted = muted
        self.releaseResourcesWhilePaused = releaseResourcesWhilePaused
        self.pauseTeardownDelay = pauseTeardownDelay

        super.init()

        playerLayer.videoGravity = .resizeAspectFill
        overlayView.objectInteractionEnabled = interactiveObjectsEnabled
        overlayView.configure(
            objects: project.interactiveObjects,
            projectRootURL: project.rootURL,
            frameProvider: frameProvider,
            onFrameChanged: onFrameChanged
        )
        rebuildPlayer()
    }

    func start() {
        pauseTeardownTimer?.invalidate()
        pauseTeardownTimer = nil
        if player == nil {
            rebuildPlayer()
        }
        player?.play()
        overlayView.start()
    }

    func pause() {
        guard let player else {
            overlayView.pause()
            return
        }

        resumeTime = player.currentTime()
        player.pause()
        overlayView.pause()
        scheduleLongPauseTeardown()
    }

    func teardown() {
        pauseTeardownTimer?.invalidate()
        pauseTeardownTimer = nil
        overlayView.teardown()
        releasePlaybackResources()
        view.removeFromSuperview()
    }

    func setMuted(_ muted: Bool) {
        self.muted = muted
        player?.isMuted = muted
    }

    func setReleaseResourcesWhilePaused(_ enabled: Bool) {
        releaseResourcesWhilePaused = enabled
        if enabled, player?.rate == 0 {
            scheduleLongPauseTeardown()
        } else {
            pauseTeardownTimer?.invalidate()
            pauseTeardownTimer = nil
        }
    }

    func setInteractiveObjectsEnabled(_ enabled: Bool) {
        overlayView.objectInteractionEnabled = enabled
    }

    func resetInteractiveObjectFrames() {
        overlayView.resetObjectFrames()
    }

    @objc
    private func longPauseTeardownTimerFired() {
        guard player?.rate == 0 else {
            return
        }
        releasePlaybackResources()
    }

    private func rebuildPlayer() {
        let player = AVQueuePlayer()
        let item = AVPlayerItem(url: fileURL)
        let looper = AVPlayerLooper(player: player, templateItem: item)

        player.actionAtItemEnd = .none
        player.isMuted = muted
        player.preventsDisplaySleepDuringVideoPlayback = false
        playerLayer.player = player

        if resumeTime.isValid, resumeTime != .zero {
            player.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        self.player = player
        self.looper = looper
    }

    private func scheduleLongPauseTeardown() {
        pauseTeardownTimer?.invalidate()
        pauseTeardownTimer = nil

        guard releaseResourcesWhilePaused else {
            return
        }

        pauseTeardownTimer = Timer.scheduledTimer(
            timeInterval: pauseTeardownDelay,
            target: self,
            selector: #selector(longPauseTeardownTimerFired),
            userInfo: nil,
            repeats: false
        )
    }

    private func releasePlaybackResources() {
        resumeTime = player?.currentTime() ?? resumeTime
        player?.pause()
        player?.removeAllItems()
        playerLayer.player = nil
        looper = nil
        player = nil
    }
}

private final class PlayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
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
}
