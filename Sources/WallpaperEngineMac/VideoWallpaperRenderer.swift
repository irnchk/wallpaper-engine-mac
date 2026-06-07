import AppKit
import AVFoundation
import QuartzCore
import WebKit
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
    func setAudioResponsiveEnabled(_ enabled: Bool)
    func updateAudioResponsiveLevel(_ level: AudioResponsiveLevel)
    func resetInteractiveObjectFrames()
}

@MainActor
final class ScenePackagePlaceholderRenderer: NSObject, WallpaperRenderer {
    let view: NSView

    init(project: WallpaperProject) {
        let containerView = NSView(frame: .zero)
        let stackView = NSStackView()
        let titleLabel = NSTextField(labelWithString: project.title)
        let messageLabel = NSTextField(labelWithString: "Scene package imported. Texture conversion is needed before this wallpaper can be rendered.")

        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.maximumNumberOfLines = 2
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail

        messageLabel.font = .systemFont(ofSize: 14, weight: .regular)
        messageLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        messageLabel.maximumNumberOfLines = 3
        messageLabel.alignment = .center
        messageLabel.lineBreakMode = .byWordWrapping

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(messageLabel)
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: 48),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -48),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.72),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.72)
        ])

        self.view = containerView
        super.init()
    }

    func start() {}

    func pause() {}

    func teardown() {
        view.removeFromSuperview()
    }

    func setMuted(_ muted: Bool) {}

    func setReleaseResourcesWhilePaused(_ enabled: Bool) {}

    func setInteractiveObjectsEnabled(_ enabled: Bool) {}

    func setAudioResponsiveEnabled(_ enabled: Bool) {}

    func updateAudioResponsiveLevel(_ level: AudioResponsiveLevel) {}

    func resetInteractiveObjectFrames() {}
}

@MainActor
final class VideoWallpaperRenderer: NSObject, WallpaperRenderer {
    let view: NSView

    private let playerLayer: AVPlayerLayer
    private let audioResponsiveView: AudioResponsiveOverlayView
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
        audioResponsiveEnabled: Bool,
        audioResponsiveStyle: AudioResponsiveOverlayStyle,
        frameProvider: @escaping (String) -> WallpaperInteractiveFrame?,
        onFrameChanged: @escaping (String, WallpaperInteractiveFrame) -> Void,
        onExitEditModeRequested: @escaping () -> Void,
        pauseTeardownDelay: TimeInterval = 60
    ) {
        let containerView = NSView(frame: .zero)
        let playerView = PlayerView(frame: .zero)
        let audioResponsiveView = AudioResponsiveOverlayView(frame: .zero)
        let overlayView = InteractiveOverlayView(frame: .zero)

        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor
        playerView.translatesAutoresizingMaskIntoConstraints = false
        audioResponsiveView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(playerView)
        containerView.addSubview(audioResponsiveView)
        containerView.addSubview(overlayView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            audioResponsiveView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            audioResponsiveView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            audioResponsiveView.topAnchor.constraint(equalTo: containerView.topAnchor),
            audioResponsiveView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.view = containerView
        self.playerLayer = playerView.playerLayer
        self.audioResponsiveView = audioResponsiveView
        self.overlayView = overlayView
        self.fileURL = fileURL
        self.muted = muted
        self.releaseResourcesWhilePaused = releaseResourcesWhilePaused
        self.pauseTeardownDelay = pauseTeardownDelay

        super.init()

        playerLayer.videoGravity = .resizeAspectFill
        audioResponsiveView.style = audioResponsiveStyle
        audioResponsiveView.isAudioResponsiveEnabled = audioResponsiveEnabled
        overlayView.objectInteractionEnabled = interactiveObjectsEnabled
        overlayView.onExitEditModeRequested = onExitEditModeRequested
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

    func setAudioResponsiveEnabled(_ enabled: Bool) {
        audioResponsiveView.isAudioResponsiveEnabled = enabled
    }

    func updateAudioResponsiveLevel(_ level: AudioResponsiveLevel) {
        audioResponsiveView.update(level: level.value)
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

@MainActor
final class ImageWallpaperRenderer: NSObject, WallpaperRenderer, WKNavigationDelegate {
    let view: NSView

    private let webView: WKWebView
    private let audioResponsiveView: AudioResponsiveOverlayView
    private let overlayView: InteractiveOverlayView

    init(
        project: WallpaperProject,
        fileURL: URL,
        interactiveObjectsEnabled: Bool,
        audioResponsiveEnabled: Bool,
        audioResponsiveStyle: AudioResponsiveOverlayStyle,
        frameProvider: @escaping (String) -> WallpaperInteractiveFrame?,
        onFrameChanged: @escaping (String, WallpaperInteractiveFrame) -> Void,
        onExitEditModeRequested: @escaping () -> Void
    ) {
        let containerView = NSView(frame: .zero)
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let audioResponsiveView = AudioResponsiveOverlayView(frame: .zero)
        let overlayView = InteractiveOverlayView(frame: .zero)

        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor
        webView.translatesAutoresizingMaskIntoConstraints = false
        audioResponsiveView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(webView)
        containerView.addSubview(audioResponsiveView)
        containerView.addSubview(overlayView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            audioResponsiveView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            audioResponsiveView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            audioResponsiveView.topAnchor.constraint(equalTo: containerView.topAnchor),
            audioResponsiveView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.view = containerView
        self.webView = webView
        self.audioResponsiveView = audioResponsiveView
        self.overlayView = overlayView

        super.init()

        webView.navigationDelegate = self
        webView.setTransparentBackgroundIfAvailable()
        audioResponsiveView.style = audioResponsiveStyle
        audioResponsiveView.isAudioResponsiveEnabled = audioResponsiveEnabled
        overlayView.objectInteractionEnabled = interactiveObjectsEnabled
        overlayView.onExitEditModeRequested = onExitEditModeRequested
        overlayView.configure(
            objects: project.interactiveObjects,
            projectRootURL: project.rootURL,
            frameProvider: frameProvider,
            onFrameChanged: onFrameChanged
        )
        loadImage(fileURL)
    }

    func start() {
        overlayView.start()
    }

    func pause() {
        overlayView.pause()
    }

    func teardown() {
        overlayView.teardown()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        view.removeFromSuperview()
    }

    func setMuted(_ muted: Bool) {}

    func setReleaseResourcesWhilePaused(_ enabled: Bool) {}

    func setInteractiveObjectsEnabled(_ enabled: Bool) {
        overlayView.objectInteractionEnabled = enabled
    }

    func setAudioResponsiveEnabled(_ enabled: Bool) {
        audioResponsiveView.isAudioResponsiveEnabled = enabled
    }

    func updateAudioResponsiveLevel(_ level: AudioResponsiveLevel) {
        audioResponsiveView.update(level: level.value)
    }

    func resetInteractiveObjectFrames() {
        overlayView.resetObjectFrames()
    }

    private func loadImage(_ fileURL: URL) {
        let source: String
        do {
            let data = try Data(contentsOf: fileURL)
            source = "data:\(mimeType(forImageURL: fileURL));base64,\(data.base64EncodedString())"
        } catch {
            source = ""
            NSLog("[WallpaperEngineMac ImageRenderer] failed to read %@: %@", fileURL.path, error.localizedDescription)
        }

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              overflow: hidden;
              background: #000;
            }
            img {
              display: block;
              width: 100%;
              height: 100%;
              object-fit: contain;
              object-position: center center;
              background: #000;
            }
          </style>
        </head>
        <body>
          <img src="\(source)" alt="">
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: fileURL.deletingLastPathComponent())
    }
}

@MainActor
final class WebWallpaperRenderer: NSObject, WallpaperRenderer, WKNavigationDelegate {
    let view: NSView

    private let webView: WKWebView
    private let audioResponsiveView: AudioResponsiveOverlayView
    private let overlayView: InteractiveOverlayView
    private var isAudioResponsiveEnabled: Bool

    init(
        project: WallpaperProject,
        fileURL: URL,
        interactiveObjectsEnabled: Bool,
        audioResponsiveEnabled: Bool,
        audioResponsiveStyle: AudioResponsiveOverlayStyle,
        frameProvider: @escaping (String) -> WallpaperInteractiveFrame?,
        onFrameChanged: @escaping (String, WallpaperInteractiveFrame) -> Void,
        onExitEditModeRequested: @escaping () -> Void
    ) {
        let containerView = NSView(frame: .zero)
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.enableLocalFileAccessIfAvailable()
        configuration.enableUniversalFileAccessIfAvailable()
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.wallpaperEngineWebAPIBridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let audioResponsiveView = AudioResponsiveOverlayView(frame: .zero)
        let overlayView = InteractiveOverlayView(frame: .zero)

        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor
        webView.translatesAutoresizingMaskIntoConstraints = false
        audioResponsiveView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(webView)
        containerView.addSubview(audioResponsiveView)
        containerView.addSubview(overlayView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            audioResponsiveView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            audioResponsiveView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            audioResponsiveView.topAnchor.constraint(equalTo: containerView.topAnchor),
            audioResponsiveView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.view = containerView
        self.webView = webView
        self.audioResponsiveView = audioResponsiveView
        self.overlayView = overlayView
        self.isAudioResponsiveEnabled = audioResponsiveEnabled

        super.init()

        webView.navigationDelegate = self
        webView.setTransparentBackgroundIfAvailable()
        audioResponsiveView.style = audioResponsiveStyle
        audioResponsiveView.isAudioResponsiveEnabled = audioResponsiveEnabled
        overlayView.objectInteractionEnabled = interactiveObjectsEnabled
        overlayView.onExitEditModeRequested = onExitEditModeRequested
        overlayView.configure(
            objects: project.interactiveObjects,
            projectRootURL: project.rootURL,
            frameProvider: frameProvider,
            onFrameChanged: onFrameChanged
        )
        webView.loadFileURL(fileURL, allowingReadAccessTo: project.rootURL)
    }

    func start() {
        overlayView.start()
    }

    func pause() {
        overlayView.pause()
    }

    func teardown() {
        overlayView.teardown()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        view.removeFromSuperview()
    }

    func setMuted(_ muted: Bool) {}

    func setReleaseResourcesWhilePaused(_ enabled: Bool) {}

    func setInteractiveObjectsEnabled(_ enabled: Bool) {
        overlayView.objectInteractionEnabled = enabled
    }

    func setAudioResponsiveEnabled(_ enabled: Bool) {
        isAudioResponsiveEnabled = enabled
        audioResponsiveView.isAudioResponsiveEnabled = enabled
        if !enabled {
            dispatchAudioLevelToWeb(0)
        }
    }

    func updateAudioResponsiveLevel(_ level: AudioResponsiveLevel) {
        audioResponsiveView.update(level: level.value)
        guard isAudioResponsiveEnabled else {
            return
        }
        dispatchAudioLevelToWeb(level.value)
    }

    func resetInteractiveObjectFrames() {
        overlayView.resetObjectFrames()
    }

    private func dispatchAudioLevelToWeb(_ level: Double) {
        let clampedLevel = min(max(level, 0), 1)
        webView.evaluateJavaScript(
            "window.__wallpaperEngineMacDispatchAudio && window.__wallpaperEngineMacDispatchAudio(\(clampedLevel));",
            completionHandler: nil
        )
    }

    private static let wallpaperEngineWebAPIBridgeScript = """
    (function() {
      if (window.__wallpaperEngineMacBridgeInstalled) {
        return;
      }
      window.__wallpaperEngineMacBridgeInstalled = true;
      var audioListeners = [];
      var lastLevel = 0;

      window.wallpaperRegisterAudioListener = function(callback) {
        if (typeof callback === "function" && audioListeners.indexOf(callback) === -1) {
          audioListeners.push(callback);
        }
      };

      window.wallpaperRegisterMediaPropertiesListener = function(callback) {
        if (typeof callback === "function") {
          callback({
            title: "",
            artist: "",
            albumTitle: "",
            albumArtist: "",
            albumCover: ""
          });
        }
      };

      window.wallpaperPropertyListener = window.wallpaperPropertyListener || {
        applyUserProperties: function() {}
      };

      function makeBins(level) {
        var bins = new Array(128);
        for (var i = 0; i < bins.length; i++) {
          var phase = i / bins.length;
          var lowBias = 1 - phase * 0.55;
          var shimmer = 0.74 + 0.26 * Math.sin((i * 0.37) + (level * 9));
          bins[i] = Math.max(0, Math.min(1, level * lowBias * shimmer));
        }
        return bins;
      }

      window.__wallpaperEngineMacDispatchAudio = function(level) {
        level = Math.max(0, Math.min(1, Number(level) || 0));
        lastLevel = (lastLevel * 0.68) + (level * 0.32);
        var bins = makeBins(lastLevel);
        for (var i = 0; i < audioListeners.length; i++) {
          try {
            audioListeners[i](bins);
          } catch (error) {
            console.error(error);
          }
        }
        window.dispatchEvent(new CustomEvent("wallpaper-engine-mac-audio", {
          detail: { level: lastLevel, bins: bins }
        }));
      };
    })();
    """
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

private func htmlAttributeEscaped(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

private func mimeType(forImageURL url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "gif":
        return "image/gif"
    case "jpg", "jpeg":
        return "image/jpeg"
    case "png":
        return "image/png"
    case "webp":
        return "image/webp"
    default:
        return "application/octet-stream"
    }
}

private extension WKWebView {
    func setTransparentBackgroundIfAvailable() {
        let selector = Selector(("setDrawsBackground:"))
        if responds(to: selector) {
            setValue(false, forKey: "drawsBackground")
        }
        if responds(to: Selector(("setUnderPageBackgroundColor:"))) {
            setValue(NSColor.clear, forKey: "underPageBackgroundColor")
        }
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private extension WKPreferences {
    func enableLocalFileAccessIfAvailable() {
        let selector = Selector(("setAllowFileAccessFromFileURLs:"))
        guard responds(to: selector) else {
            return
        }
        setValue(true, forKey: "allowFileAccessFromFileURLs")
    }
}

private extension WKWebViewConfiguration {
    func enableUniversalFileAccessIfAvailable() {
        let selector = Selector(("setAllowUniversalAccessFromFileURLs:"))
        guard responds(to: selector) else {
            return
        }
        setValue(true, forKey: "allowUniversalAccessFromFileURLs")
    }
}
