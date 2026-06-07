import Foundation

public enum WallpaperType: String, Codable, Sendable {
    case video
    case web
    case scene
    case application
    case unknown

    public init(projectValue: String?) {
        guard let value = projectValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty
        else {
            self = .unknown
            return
        }
        self = WallpaperType(rawValue: value) ?? .unknown
    }
}

public enum WallpaperSupportStatus: Equatable, Sendable {
    case supported
    case needsTranscoding(String)
    case unsupported(String)

    public var isPlayableNow: Bool {
        if case .supported = self {
            return true
        }
        return false
    }

    public var label: String {
        switch self {
        case .supported:
            return "Supported"
        case let .needsTranscoding(reason):
            return "Needs Transcoding: \(reason)"
        case let .unsupported(reason):
            return "Unsupported: \(reason)"
        }
    }
}

public struct WallpaperProperty: Decodable, Equatable, Sendable {
    public let type: String?
    public let text: String?
    public let value: JSONValue?
    public let minimum: JSONValue?
    public let maximum: JSONValue?
    public let options: JSONValue?
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case value
        case minimum = "min"
        case maximum = "max"
        case options
    }

    public init(from decoder: Decoder) throws {
        self.raw = try JSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.value = try container.decodeIfPresent(JSONValue.self, forKey: .value)
        self.minimum = try container.decodeIfPresent(JSONValue.self, forKey: .minimum)
        self.maximum = try container.decodeIfPresent(JSONValue.self, forKey: .maximum)
        self.options = try container.decodeIfPresent(JSONValue.self, forKey: .options)
    }
}

public struct WallpaperInteractiveFrame: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct WallpaperInteractiveObject: Decodable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let title: String?
    public let fileName: String?
    public let frame: WallpaperInteractiveFrame
    public let opacity: Double
    public let cornerRadius: Double
    public let draggable: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case fileName = "file"
        case frame
        case opacity
        case cornerRadius
        case draggable
    }

    public var normalizedType: String {
        type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var isImageLike: Bool {
        ["image", "albumart", "album-art", "album_cover", "album-cover", "cover", "custom-image"].contains(normalizedType)
    }

    public var isVideoLike: Bool {
        ["video", "movie", "loop", "animated-video"].contains(normalizedType)
    }

    public var isLive2DLike: Bool {
        ["live2d", "live2d-web", "cubism", "cubism-web"].contains(normalizedType)
    }

    public func fileURL(relativeTo rootURL: URL) -> URL? {
        guard let fileName = fileName?.nilIfBlank else {
            return nil
        }
        return rootURL.appendingPathComponent(fileName).standardizedFileURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)?.nilIfBlank ?? UUID().uuidString
        self.type = try container.decodeIfPresent(String.self, forKey: .type)?.nilIfBlank ?? "image"
        self.title = try container.decodeIfPresent(String.self, forKey: .title)?.nilIfBlank
        self.fileName = try container.decodeIfPresent(String.self, forKey: .fileName)?.nilIfBlank
        self.frame = try container.decodeIfPresent(WallpaperInteractiveFrame.self, forKey: .frame) ?? WallpaperInteractiveFrame(
            x: 0.65,
            y: 0.25,
            width: 0.18,
            height: 0.18
        )
        self.opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        self.cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
        self.draggable = try container.decodeIfPresent(Bool.self, forKey: .draggable) ?? true
    }
}

public struct WallpaperProject: Identifiable, Equatable, Sendable {
    public let id: String
    public let rootURL: URL
    public let projectURL: URL?
    public let title: String
    public let type: WallpaperType
    public let fileName: String?
    public let entryURL: URL?
    public let previewURL: URL?
    public let properties: [String: WallpaperProperty]
    public let interactiveObjects: [WallpaperInteractiveObject]
    public let usesAudioResponsiveOverlay: Bool
    public let supportStatus: WallpaperSupportStatus

    public var isPlayableNow: Bool {
        supportStatus.isPlayableNow
    }

    public static func load(projectJSONURL: URL) throws -> WallpaperProject {
        let data = try Data(contentsOf: projectJSONURL)
        let project = try JSONDecoder().decode(ProjectJSON.self, from: data)
        let rawProject = try JSONDecoder().decode(JSONValue.self, from: data)
        let rootURL = projectJSONURL.deletingLastPathComponent()
        let type = WallpaperType(projectValue: project.type)
        let fileName = project.file?.nilIfBlank
        let previewURL = project.preview?.nilIfBlank.map { rootURL.appendingPathComponent($0) }
        let rawEntryURL = fileName.map { rootURL.appendingPathComponent($0) }
        let entryURL = playbackEntryURL(
            type: type,
            rawEntryURL: rawEntryURL,
            previewURL: previewURL,
            rootURL: rootURL
        )
        let title = project.title?.nilIfBlank ?? rootURL.lastPathComponent
        let supportStatus = supportStatusFor(type: type, entryURL: entryURL)
        let usesAudioResponsiveOverlay = detectsAudioResponsiveOverlay(in: rawProject)

        return WallpaperProject(
            id: rootURL.lastPathComponent,
            rootURL: rootURL.standardizedFileURL,
            projectURL: projectJSONURL.standardizedFileURL,
            title: title,
            type: type,
            fileName: fileName,
            entryURL: entryURL?.standardizedFileURL,
            previewURL: previewURL?.standardizedFileURL,
            properties: project.general?.properties ?? [:],
            interactiveObjects: project.interactive?.objects ?? [],
            usesAudioResponsiveOverlay: usesAudioResponsiveOverlay,
            supportStatus: supportStatus
        )
    }

    public static func directVideo(url: URL) -> WallpaperProject {
        let standardizedURL = url.standardizedFileURL
        return WallpaperProject(
            id: standardizedURL.path,
            rootURL: standardizedURL.deletingLastPathComponent(),
            projectURL: nil,
            title: standardizedURL.deletingPathExtension().lastPathComponent,
            type: .video,
            fileName: standardizedURL.lastPathComponent,
            entryURL: standardizedURL,
            previewURL: nil,
            properties: [:],
            interactiveObjects: [],
            usesAudioResponsiveOverlay: false,
            supportStatus: supportStatusFor(type: .video, entryURL: standardizedURL)
        )
    }

    private static func supportStatusFor(type: WallpaperType, entryURL: URL?) -> WallpaperSupportStatus {
        switch type {
        case .video:
            guard let entryURL else {
                return .unsupported("Missing video file")
            }
            let ext = entryURL.pathExtension.lowercased()
            if SupportedVideoFile.videoExtensions.contains(ext) {
                return .supported
            }
            if SupportedVideoFile.transcodableVideoExtensions.contains(ext) {
                return .needsTranscoding("Import-time mp4 cache is planned for .\(ext)")
            }
            return .unsupported("Unsupported video format .\(ext)")
        case .web:
            guard let entryURL else {
                return .unsupported("Missing web entry file")
            }
            if SupportedWebFile.isKnownWebEntryFile(entryURL),
               FileManager.default.fileExists(atPath: entryURL.path) {
                return .supported
            }
            return .unsupported("Unsupported web entry .\(entryURL.pathExtension.lowercased())")
        case .scene:
            guard let entryURL else {
                return .unsupported("Scene wallpaper does not contain a playable fallback")
            }
            if SupportedStillOrAnimatedImageFile.isKnownImageFile(entryURL) {
                return .supported
            }
            if SupportedScenePackageFile.isKnownScenePackageFile(entryURL),
               FileManager.default.fileExists(atPath: entryURL.path) {
                return .supported
            }
            return .unsupported("Scene wallpapers without image/GIF fallback are planned for later R&D")
        case .application:
            return .unsupported("Windows application wallpapers are out of scope")
        case .unknown:
            return .unsupported("Unknown Wallpaper Engine project type")
        }
    }

    private static func playbackEntryURL(
        type: WallpaperType,
        rawEntryURL: URL?,
        previewURL: URL?,
        rootURL: URL
    ) -> URL? {
        switch type {
        case .web:
            if let rawEntryURL,
               SupportedWebFile.isKnownWebEntryFile(rawEntryURL),
               FileManager.default.fileExists(atPath: rawEntryURL.path) {
                return rawEntryURL
            }

            let fallbackNames = [
                "index.html",
                "index.htm"
            ]
            return fallbackNames
                .map { rootURL.appendingPathComponent($0) }
                .first { SupportedWebFile.isKnownWebEntryFile($0) && FileManager.default.fileExists(atPath: $0.path) }
        case .scene:
            if let rawEntryURL,
               SupportedStillOrAnimatedImageFile.isKnownImageFile(rawEntryURL),
               FileManager.default.fileExists(atPath: rawEntryURL.path) {
                return rawEntryURL
            }

            if let packageURL = scenePackageURL(rawEntryURL: rawEntryURL, rootURL: rootURL) {
                return packageURL
            }

            if let previewURL,
               SupportedStillOrAnimatedImageFile.isKnownImageFile(previewURL),
               FileManager.default.fileExists(atPath: previewURL.path),
               isUsableSceneImageFallback(previewURL) {
                return previewURL
            }

            let fallbackNames = [
                "background.gif",
                "preview.gif",
                "background.png",
                "preview.png",
                "background.jpg",
                "preview.jpg"
            ]
            return fallbackNames
                .map { rootURL.appendingPathComponent($0) }
                .first {
                    SupportedStillOrAnimatedImageFile.isKnownImageFile($0)
                        && FileManager.default.fileExists(atPath: $0.path)
                        && isUsableSceneImageFallback($0)
                }
        default:
            return rawEntryURL
        }
    }

    private static func scenePackageURL(rawEntryURL: URL?, rootURL: URL) -> URL? {
        var candidates: [URL] = []

        if let rawEntryURL {
            candidates.append(rawEntryURL)
            candidates.append(rawEntryURL.deletingPathExtension().appendingPathExtension("pkg"))
        }

        candidates.append(rootURL.appendingPathComponent("scene.pkg"))

        if let packageURLs = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) {
            candidates.append(contentsOf: packageURLs.filter(SupportedScenePackageFile.isKnownScenePackageFile))
        }

        var seen = Set<String>()
        return candidates.first { url in
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else {
                return false
            }
            return SupportedScenePackageFile.isKnownScenePackageFile(url)
                && FileManager.default.fileExists(atPath: path)
        }
    }

    private static func isUsableSceneImageFallback(_ url: URL) -> Bool {
        guard let dimensions = imageDimensions(url) else {
            return true
        }

        let width = dimensions.width
        let height = dimensions.height
        guard width >= 480, height >= 270 else {
            return false
        }

        let aspectRatio = Double(width) / Double(height)
        return aspectRatio >= 1.2 && aspectRatio <= 4.2
    }

    private static func imageDimensions(_ url: URL) -> (width: Int, height: Int)? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count >= 10
        else {
            return nil
        }

        if data.starts(with: Data([0x47, 0x49, 0x46, 0x38])) {
            return (
                width: littleEndianUInt16(data, offset: 6),
                height: littleEndianUInt16(data, offset: 8)
            )
        }

        if data.starts(with: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
           data.count >= 24 {
            return (
                width: bigEndianInt32(data, offset: 16),
                height: bigEndianInt32(data, offset: 20)
            )
        }

        if data.starts(with: Data([0xFF, 0xD8])) {
            return jpegDimensions(data)
        }

        return nil
    }

    private static func jpegDimensions(_ data: Data) -> (width: Int, height: Int)? {
        var offset = 2
        while offset + 9 < data.count {
            guard data[offset] == 0xFF else {
                offset += 1
                continue
            }

            let marker = data[offset + 1]
            offset += 2

            if marker == 0xD9 || marker == 0xDA {
                return nil
            }
            if marker >= 0xD0 && marker <= 0xD7 {
                continue
            }
            guard offset + 2 <= data.count else {
                return nil
            }

            let segmentLength = bigEndianUInt16(data, offset: offset)
            guard segmentLength >= 2, offset + segmentLength <= data.count else {
                return nil
            }

            if isJPEGStartOfFrame(marker), offset + 7 < data.count {
                return (
                    width: bigEndianUInt16(data, offset: offset + 5),
                    height: bigEndianUInt16(data, offset: offset + 3)
                )
            }

            offset += segmentLength
        }

        return nil
    }

    private static func isJPEGStartOfFrame(_ marker: UInt8) -> Bool {
        switch marker {
        case 0xC0...0xC3, 0xC5...0xC7, 0xC9...0xCB, 0xCD...0xCF:
            return true
        default:
            return false
        }
    }

    private static func littleEndianUInt16(_ data: Data, offset: Int) -> Int {
        guard offset + 1 < data.count else {
            return 0
        }
        return Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private static func bigEndianUInt16(_ data: Data, offset: Int) -> Int {
        guard offset + 1 < data.count else {
            return 0
        }
        return (Int(data[offset]) << 8) | Int(data[offset + 1])
    }

    private static func bigEndianInt32(_ data: Data, offset: Int) -> Int {
        guard offset + 3 < data.count else {
            return 0
        }
        return (Int(data[offset]) << 24)
            | (Int(data[offset + 1]) << 16)
            | (Int(data[offset + 2]) << 8)
            | Int(data[offset + 3])
    }

    private static func detectsAudioResponsiveOverlay(in rawProject: JSONValue) -> Bool {
        searchableStrings(in: rawProject).contains(where: hasAudioResponsiveHint)
    }

    private static func searchableStrings(in value: JSONValue) -> [String] {
        switch value {
        case let .string(string):
            return [string]
        case let .number(number):
            return [String(number)]
        case let .bool(bool):
            return [String(bool)]
        case let .array(values):
            return values.flatMap(searchableStrings)
        case let .object(object):
            return object.flatMap { key, value in
                [key] + searchableStrings(in: value)
            }
        case .null:
            return []
        }
    }

    private static func hasAudioResponsiveHint(_ rawText: String) -> Bool {
        let lower = rawText.lowercased()
        let spaced = lower
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
        let compact = spaced.replacingOccurrences(of: " ", with: "")

        let compactHints = [
            "audioresponsive",
            "audioreactive",
            "musicresponsive",
            "musicreactive",
            "soundresponsive",
            "soundreactive",
            "audiovisualizer",
            "musicvisualizer",
            "soundvisualizer",
            "audioprocessing",
            "audiofft"
        ]
        if compactHints.contains(where: compact.contains) {
            return true
        }

        let audioNouns = ["audio", "music", "sound"]
        let reactiveTerms = [
            "responsive",
            "reactive",
            "visualizer",
            "spectrum",
            "equalizer",
            "fft",
            "frequency",
            "bass",
            "treble",
            "beat",
            "pulse",
            "wave"
        ]

        if audioNouns.contains(where: { spaced.contains($0) }),
           reactiveTerms.contains(where: { spaced.contains($0) }) {
            return true
        }

        return ["visualizer", "spectrum analyzer", "fft"].contains { spaced.contains($0) }
    }
}

public enum SupportedVideoFile {
    public static let videoExtensions: Set<String> = ["mp4", "m4v", "mov"]
    public static let transcodableVideoExtensions: Set<String> = ["webm"]

    public static func isKnownVideoFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return videoExtensions.contains(ext) || transcodableVideoExtensions.contains(ext)
    }
}

public enum SupportedStillOrAnimatedImageFile {
    public static let imageExtensions: Set<String> = ["gif", "jpg", "jpeg", "png", "webp"]

    public static func isKnownImageFile(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }
}

public enum SupportedWebFile {
    public static let webEntryExtensions: Set<String> = ["html", "htm"]

    public static func isKnownWebEntryFile(_ url: URL) -> Bool {
        webEntryExtensions.contains(url.pathExtension.lowercased())
    }
}

public enum SupportedScenePackageFile {
    public static let packageExtensions: Set<String> = ["pkg"]

    public static func isKnownScenePackageFile(_ url: URL) -> Bool {
        packageExtensions.contains(url.pathExtension.lowercased())
    }
}

private struct ProjectJSON: Decodable {
    let type: String?
    let file: String?
    let title: String?
    let preview: String?
    let general: GeneralJSON?
    let interactive: InteractiveJSON?
}

private struct GeneralJSON: Decodable {
    let properties: [String: WallpaperProperty]?
}

private struct InteractiveJSON: Decodable {
    let objects: [WallpaperInteractiveObject]?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
