import AppKit
import AVFoundation
import QuartzCore

@MainActor
protocol WallpaperRenderer: AnyObject {
    var view: NSView { get }

    func start()
    func pause()
    func teardown()
    func setMuted(_ muted: Bool)
    func setReleaseResourcesWhilePaused(_ enabled: Bool)
}

@MainActor
final class VideoWallpaperRenderer: NSObject, WallpaperRenderer {
    let view: NSView

    private let playerLayer: AVPlayerLayer
    private let fileURL: URL
    private let pauseTeardownDelay: TimeInterval

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var pauseTeardownTimer: Timer?
    private var muted: Bool
    private var releaseResourcesWhilePaused: Bool
    private var resumeTime = CMTime.zero

    init(
        fileURL: URL,
        muted: Bool,
        releaseResourcesWhilePaused: Bool,
        pauseTeardownDelay: TimeInterval = 60
    ) {
        let playerView = PlayerView(frame: .zero)
        self.view = playerView
        self.playerLayer = playerView.playerLayer
        self.fileURL = fileURL
        self.muted = muted
        self.releaseResourcesWhilePaused = releaseResourcesWhilePaused
        self.pauseTeardownDelay = pauseTeardownDelay

        super.init()

        playerLayer.videoGravity = .resizeAspectFill
        rebuildPlayer()
    }

    func start() {
        pauseTeardownTimer?.invalidate()
        pauseTeardownTimer = nil
        if player == nil {
            rebuildPlayer()
        }
        player?.play()
    }

    func pause() {
        guard let player else {
            return
        }

        resumeTime = player.currentTime()
        player.pause()
        scheduleLongPauseTeardown()
    }

    func teardown() {
        pauseTeardownTimer?.invalidate()
        pauseTeardownTimer = nil
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
