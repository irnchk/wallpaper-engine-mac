import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import WallpaperEngineCore

@MainActor
enum LockScreenSnapshotInstaller {
    struct Result {
        let snapshotURL: URL
        let lockScreenCacheURL: URL?
        let didSetDesktopWallpaper: Bool
    }

    enum InstallerError: LocalizedError {
        case missingPlayableEntry(WallpaperProject)
        case unsupportedSnapshotSource(WallpaperProject)
        case imageDecodeFailed(URL)
        case imageEncodeFailed(URL)
        case videoFrameExtractionFailed(URL, Error)
        case missingGeneratedUID
        case lockScreenInstallFailed(String)

        var errorDescription: String? {
            switch self {
            case let .missingPlayableEntry(project):
                return "Cannot create a lock screen snapshot because \(project.title) has no playable entry."
            case let .unsupportedSnapshotSource(project):
                return "Cannot create a lock screen snapshot for \(project.title). Web wallpapers need a still preview image first."
            case let .imageDecodeFailed(url):
                return "Could not decode a snapshot image from \(url.path)."
            case let .imageEncodeFailed(url):
                return "Could not write the lock screen snapshot to \(url.path)."
            case let .videoFrameExtractionFailed(url, error):
                return "Could not extract a video frame from \(url.path).\n\n\(error.localizedDescription)"
            case .missingGeneratedUID:
                return "Could not find the current user's macOS GeneratedUID for the lock screen cache."
            case let .lockScreenInstallFailed(output):
                return "macOS did not allow the lock screen snapshot to be installed.\n\n\(output)"
            }
        }
    }

    static func installSnapshot(for project: WallpaperProject) throws -> Result {
        let snapshotURL = try createSnapshot(for: project)
        let didSetDesktopWallpaper = setDesktopWallpaper(to: snapshotURL)
        let lockScreenCacheURL = try installLockScreenCache(from: snapshotURL)
        return Result(
            snapshotURL: snapshotURL,
            lockScreenCacheURL: lockScreenCacheURL,
            didSetDesktopWallpaper: didSetDesktopWallpaper
        )
    }

    private static func createSnapshot(for project: WallpaperProject) throws -> URL {
        guard let sourceURL = snapshotSourceURL(for: project) else {
            if project.entryURL == nil {
                throw InstallerError.missingPlayableEntry(project)
            }
            throw InstallerError.unsupportedSnapshotSource(project)
        }

        let cgImage: CGImage
        if SupportedVideoFile.videoExtensions.contains(sourceURL.pathExtension.lowercased()) {
            cgImage = try videoFrame(from: sourceURL)
        } else {
            cgImage = try imageFrame(from: sourceURL)
        }

        let outputURL = snapshotOutputURL(for: project)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw InstallerError.imageEncodeFailed(outputURL)
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw InstallerError.imageEncodeFailed(outputURL)
        }

        return outputURL
    }

    private static func snapshotSourceURL(for project: WallpaperProject) -> URL? {
        if let packagedScene = ScenePackageSupport.renderableScene(for: project) {
            return packagedScene.backgroundImageURL
        }

        if let entryURL = project.entryURL {
            if SupportedVideoFile.videoExtensions.contains(entryURL.pathExtension.lowercased())
                || SupportedStillOrAnimatedImageFile.isKnownImageFile(entryURL) {
                return entryURL
            }
        }

        if let previewURL = project.previewURL,
           SupportedStillOrAnimatedImageFile.isKnownImageFile(previewURL),
           FileManager.default.fileExists(atPath: previewURL.path) {
            return previewURL
        }

        return nil
    }

    private static func videoFrame(from url: URL) throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .positiveInfinity

        do {
            return try generator.copyCGImage(
                at: CMTime(seconds: 0.2, preferredTimescale: 600),
                actualTime: nil
            )
        } catch {
            throw InstallerError.videoFrameExtractionFailed(url, error)
        }
    }

    private static func imageFrame(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCache: true as CFBoolean
              ] as CFDictionary) else {
            throw InstallerError.imageDecodeFailed(url)
        }
        return image
    }

    private static func setDesktopWallpaper(to snapshotURL: URL) -> Bool {
        var didSetAnyScreen = false
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: false
        ]

        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(snapshotURL, for: screen, options: options)
                didSetAnyScreen = true
            } catch {
                NSLog("[WallpaperEngineMac LockScreen] failed to set desktop wallpaper: %@", error.localizedDescription)
            }
        }

        return didSetAnyScreen
    }

    private static func installLockScreenCache(from snapshotURL: URL) throws -> URL? {
        let generatedUID = try currentUserGeneratedUID()
        let lockScreenURL = URL(fileURLWithPath: "/Library/Caches/Desktop Pictures", isDirectory: true)
            .appendingPathComponent(generatedUID, isDirectory: true)
            .appendingPathComponent("lockscreen.png")

        let command = """
        set -e
        target_dir=/Library/Caches/Desktop\\ Pictures/\(shellQuoted(generatedUID))
        /bin/mkdir -p "$target_dir"
        /bin/cp \(shellQuoted(snapshotURL.path)) "$target_dir/lockscreen.png"
        /bin/chmod 644 "$target_dir/lockscreen.png"
        /usr/sbin/chown root:wheel "$target_dir/lockscreen.png" 2>/dev/null || true
        """

        try runPrivilegedShell(command)
        return lockScreenURL
    }

    private static func currentUserGeneratedUID() throws -> String {
        let command = """
        /usr/bin/dscl . -read /Users/$(/usr/bin/id -un) GeneratedUID | /usr/bin/awk '{print $2}'
        """
        let output = try runShell(command)
        let generatedUID = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !generatedUID.isEmpty else {
            throw InstallerError.missingGeneratedUID
        }
        return generatedUID
    }

    private static func snapshotOutputURL(for project: WallpaperProject) -> URL {
        applicationSupportURL()
            .appendingPathComponent("LockScreenSnapshots", isDirectory: true)
            .appendingPathComponent("\(safeFileName(project.title)).png")
    }

    private static func applicationSupportURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WallpaperEngineMac", isDirectory: true)
    }

    private static func runPrivilegedShell(_ command: String) throws {
        let script = "do shell script \(appleScriptLiteral(command)) with administrator privileges"
        let output = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", script]
        )
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            NSLog("[WallpaperEngineMac LockScreen] %@", output)
        }
    }

    private static func runShell(_ command: String) throws -> String {
        try runProcess(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", command]
        )
    }

    private static func runProcess(executableURL: URL, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw InstallerError.lockScreenInstallFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private static func safeFileName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let name = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Wallpaper Engine Mac Lock Screen" : name
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
