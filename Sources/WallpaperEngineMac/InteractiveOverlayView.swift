import AppKit
import AVFoundation
import WebKit
import WallpaperEngineCore

@MainActor
final class InteractiveOverlayView: NSView {
    private var objectViews: [InteractiveObjectView] = []
    private var frameProvider: ((String) -> WallpaperInteractiveFrame?)?
    private var onFrameChanged: ((String, WallpaperInteractiveFrame) -> Void)?

    var onExitEditModeRequested: (() -> Void)?

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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard objectInteractionEnabled else {
            return
        }
        onExitEditModeRequested?()
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
        layer?.backgroundColor = objectBackgroundColor(isHighlighted: false)
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
            layer.backgroundColor = objectBackgroundColor(isHighlighted: isHovered || isPressed)
        } else {
            layer.borderWidth = 0
            layer.borderColor = NSColor.clear.cgColor
            layer.shadowOpacity = 0
            layer.shadowRadius = 0
            layer.backgroundColor = objectBackgroundColor(isHighlighted: false)
        }
    }

    private func objectBackgroundColor(isHighlighted: Bool) -> CGColor {
        if object.isLive2DLike {
            return NSColor.clear.cgColor
        }
        return NSColor.black.withAlphaComponent(isHighlighted ? 0.2 : 0.12).cgColor
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
private final class Live2DWebObjectContentView: NSView, InteractiveObjectContentControlling, WKNavigationDelegate, WKScriptMessageHandler {
    private static let messageHandlerName = "wallpaperEngineLive2D"
    private static let bundleScheme = "wallpaper-object"

    private let entryURL: URL
    private let bundleSchemeHandler: LocalBundleURLSchemeHandler
    private let webView: WKWebView
    private let statusLabel = NSTextField(labelWithString: "Loading Live2D...")
    private var hasRemovedMessageHandler = false
    private var hasReportedProblem = false

    init(entryURL: URL) {
        self.entryURL = entryURL
        self.bundleSchemeHandler = LocalBundleURLSchemeHandler(rootURL: entryURL.deletingLastPathComponent())
        self.webView = WKWebView(
            frame: .zero,
            configuration: Self.makeConfiguration(schemeHandler: bundleSchemeHandler)
        )

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.setTransparentBackgroundIfAvailable()
        webView.configuration.userContentController.add(self, name: Self.messageHandlerName)

        statusLabel.textColor = .white
        statusLabel.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        statusLabel.drawsBackground = true
        statusLabel.isBezeled = false
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3

        webView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),

            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        loadEntry()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func start() {}

    func pause() {}

    func teardown() {
        removeMessageHandlerIfNeeded()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(Self.transparentDocumentScript, completionHandler: nil)
        if !hasReportedProblem {
            statusLabel.isHidden = true
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showLoadFailure(error)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName else {
            return
        }

        let messageText: String
        if let body = message.body as? [String: Any],
           let rawMessage = body["message"] as? String,
           !rawMessage.isEmpty {
            messageText = rawMessage
        } else {
            messageText = "\(message.body)"
        }

        NSLog("[WallpaperEngineMac Live2D] %@", messageText)
        hasReportedProblem = true
        statusLabel.stringValue = "Live2D script error:\n\(messageText)"
        statusLabel.isHidden = false
    }

    private func loadEntry() {
        hasReportedProblem = false
        statusLabel.stringValue = "Loading Live2D..."
        statusLabel.isHidden = false
        let entryName = entryURL.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entryURL.lastPathComponent
        guard let url = URL(string: "\(Self.bundleScheme)://bundle/\(entryName)") else {
            showLoadFailure(LocalBundleURLSchemeHandler.HandlerError.invalidURL)
            return
        }
        webView.load(URLRequest(url: url))
    }

    private func showLoadFailure(_ error: Error) {
        NSLog("[WallpaperEngineMac Live2D] load failed for %@: %@", entryURL.path, error.localizedDescription)
        hasReportedProblem = true
        statusLabel.stringValue = "Live2D load failed:\n\(error.localizedDescription)"
        statusLabel.isHidden = false
    }

    private func removeMessageHandlerIfNeeded() {
        guard !hasRemovedMessageHandler else {
            return
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
        hasRemovedMessageHandler = true
    }

    private static func makeConfiguration(schemeHandler: LocalBundleURLSchemeHandler) -> WKWebViewConfiguration {
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: """
            (function() {
              function send(value) {
                try {
                  var text = value && (value.stack || value.message) ? (value.stack || value.message) : String(value);
                  window.webkit.messageHandlers.\(messageHandlerName).postMessage({ message: text });
                } catch (_) {}
              }

              window.addEventListener("error", function(event) {
                send(event.error || event.message || "Unknown script error");
              });
              window.addEventListener("unhandledrejection", function(event) {
                send(event.reason || "Unhandled promise rejection");
              });

              var originalError = console.error;
              console.error = function() {
                send(Array.prototype.slice.call(arguments).map(String).join(" "));
                if (originalError) {
                  originalError.apply(console, arguments);
                }
              };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        contentController.addUserScript(WKUserScript(
            source: transparentDocumentScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.enableLocalFileAccessIfAvailable()
        configuration.enableUniversalFileAccessIfAvailable()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: bundleScheme)
        return configuration
    }

    private static let transparentDocumentScript = """
    (function() {
      function installStyle() {
        try {
          var id = "wallpaper-engine-transparent-live2d-style";
          if (!document.getElementById(id)) {
            var style = document.createElement("style");
            style.id = id;
            style.textContent = [
              "html, body { background: transparent !important; background-color: transparent !important; margin: 0 !important; overflow: hidden !important; }",
              "canvas, #canvas, .canvas { background: transparent !important; background-color: transparent !important; }",
              "#live2d, .live2d, .live2d-container, .pixi-live2d-display { background: transparent !important; background-color: transparent !important; }"
            ].join("\\n");
            (document.head || document.documentElement).appendChild(style);
          }
          if (document.documentElement) {
            document.documentElement.style.background = "transparent";
            document.documentElement.style.backgroundColor = "transparent";
          }
          if (document.body) {
            document.body.style.background = "transparent";
            document.body.style.backgroundColor = "transparent";
          }
          var canvases = document.getElementsByTagName("canvas");
          for (var i = 0; i < canvases.length; i++) {
            canvases[i].style.background = "transparent";
            canvases[i].style.backgroundColor = "transparent";
          }
        } catch (_) {}
      }

      function patchPixi(pixi) {
        if (!pixi || pixi.__wallpaperEngineTransparentPatch) {
          return;
        }
        try {
          pixi.__wallpaperEngineTransparentPatch = true;
          if (typeof pixi.Application === "function") {
            var OriginalApplication = pixi.Application;
            var TransparentApplication = function(options) {
              options = options || {};
              options.transparent = true;
              options.backgroundAlpha = 0;
              var app = new OriginalApplication(options);
              try {
                if (app.renderer) {
                  app.renderer.backgroundAlpha = 0;
                  app.renderer.transparent = true;
                  if (app.renderer.background) {
                    app.renderer.background.alpha = 0;
                  }
                }
              } catch (_) {}
              return app;
            };
            TransparentApplication.prototype = OriginalApplication.prototype;
            Object.setPrototypeOf(TransparentApplication, OriginalApplication);
            pixi.Application = TransparentApplication;
          }

          if (typeof pixi.autoDetectRenderer === "function") {
            var originalAutoDetectRenderer = pixi.autoDetectRenderer;
            pixi.autoDetectRenderer = function(options) {
              options = options || {};
              options.transparent = true;
              options.backgroundAlpha = 0;
              return originalAutoDetectRenderer.call(this, options);
            };
          }
        } catch (_) {}
      }

      try {
        var pixiValue = window.PIXI;
        var descriptor = Object.getOwnPropertyDescriptor(window, "PIXI");
        if (!descriptor || descriptor.configurable) {
          Object.defineProperty(window, "PIXI", {
            configurable: true,
            get: function() { return pixiValue; },
            set: function(value) {
              pixiValue = value;
              patchPixi(value);
            }
          });
          if (pixiValue) {
            patchPixi(pixiValue);
          }
        }
      } catch (_) {}

      installStyle();
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", installStyle);
      }
      window.addEventListener("load", function() {
        installStyle();
        patchPixi(window.PIXI);
      });
      setInterval(function() {
        installStyle();
        patchPixi(window.PIXI);
      }, 500);
    })();
    """
}

private final class LocalBundleURLSchemeHandler: NSObject, WKURLSchemeHandler {
    enum HandlerError: LocalizedError {
        case invalidURL
        case blockedPath
        case missingFile(URL)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid Live2D bundle URL."
            case .blockedPath:
                return "Blocked Live2D bundle path."
            case let .missingFile(url):
                return "Missing Live2D bundle file: \(url.lastPathComponent)"
            }
        }
    }

    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            let fileURL = try fileURL(for: urlSchemeTask.request.url)
            let data = try localOnlyTransparentData(for: fileURL)
            let response = URLResponse(
                url: urlSchemeTask.request.url ?? fileURL,
                mimeType: live2DMimeType(for: fileURL),
                expectedContentLength: data.count,
                textEncodingName: textEncodingName(for: fileURL)
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func fileURL(for url: URL?) throws -> URL {
        guard let url else {
            throw HandlerError.invalidURL
        }

        let decodedPath = url.path.removingPercentEncoding ?? url.path
        let relativePath = decodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let resolvedRelativePath = relativePath.isEmpty ? "index.html" : relativePath
        guard !resolvedRelativePath.split(separator: "/").contains("..") else {
            throw HandlerError.blockedPath
        }

        let fileURL = rootURL.appendingPathComponent(resolvedRelativePath).standardizedFileURL
        let rootPath = rootURL.path
        guard fileURL.path == rootPath || fileURL.path.hasPrefix(rootPath + "/") else {
            throw HandlerError.blockedPath
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw HandlerError.missingFile(fileURL)
        }
        return fileURL
    }

    private func localOnlyTransparentData(for fileURL: URL) throws -> Data {
        let data = try Data(contentsOf: fileURL)
        guard ["html", "htm"].contains(fileURL.pathExtension.lowercased()),
              var html = String(data: data, encoding: .utf8)
        else {
            return data
        }

        let injection = """
        <meta http-equiv="Content-Security-Policy" content="default-src 'self' wallpaper-object: data: blob: 'unsafe-inline' 'unsafe-eval'; img-src 'self' wallpaper-object: data: blob:; media-src 'self' wallpaper-object: data: blob:; connect-src 'self' wallpaper-object: data: blob:; font-src 'self' wallpaper-object: data: blob:; style-src 'self' wallpaper-object: data: blob: 'unsafe-inline'; script-src 'self' wallpaper-object: data: blob: 'unsafe-inline' 'unsafe-eval'; worker-src 'self' wallpaper-object: blob:; child-src 'self' wallpaper-object: blob:;">
        <style id="wallpaper-engine-live2d-html-transparency">
        html, body, canvas, #live2d, .live2d, .live2d-container, .pixi-live2d-display {
          background: transparent !important;
          background-color: transparent !important;
        }
        html, body {
          margin: 0 !important;
          overflow: hidden !important;
        }
        </style>
        """

        if let headRange = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            html.insert(contentsOf: injection, at: headRange.upperBound)
        } else {
            html = injection + html
        }

        return Data(html.utf8)
    }
}

private func live2DMimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "html", "htm":
        return "text/html"
    case "css":
        return "text/css"
    case "js":
        return "application/javascript"
    case "json":
        return "application/json"
    case "moc", "moc3", "mtn":
        return "application/octet-stream"
    case "png":
        return "image/png"
    case "jpg", "jpeg":
        return "image/jpeg"
    case "gif":
        return "image/gif"
    case "webp":
        return "image/webp"
    case "wasm":
        return "application/wasm"
    case "mp3":
        return "audio/mpeg"
    case "wav":
        return "audio/wav"
    default:
        return "application/octet-stream"
    }
}

private func textEncodingName(for url: URL) -> String? {
    switch url.pathExtension.lowercased() {
    case "html", "htm", "js", "json", "css":
        return "utf-8"
    default:
        return nil
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

private func sanitized(_ frame: WallpaperInteractiveFrame) -> WallpaperInteractiveFrame {
    let width = min(max(frame.width, 0.02), 1)
    let height = min(max(frame.height, 0.02), 1)
    let x = min(max(frame.x, 0), 1 - width)
    let y = min(max(frame.y, 0), 1 - height)
    return WallpaperInteractiveFrame(x: x, y: y, width: width, height: height)
}
