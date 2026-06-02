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
    public let supportStatus: WallpaperSupportStatus

    public var isPlayableNow: Bool {
        supportStatus.isPlayableNow
    }

    public static func load(projectJSONURL: URL) throws -> WallpaperProject {
        let data = try Data(contentsOf: projectJSONURL)
        let project = try JSONDecoder().decode(ProjectJSON.self, from: data)
        let rootURL = projectJSONURL.deletingLastPathComponent()
        let type = WallpaperType(projectValue: project.type)
        let fileName = project.file?.nilIfBlank
        let entryURL = fileName.map { rootURL.appendingPathComponent($0) }
        let previewURL = project.preview?.nilIfBlank.map { rootURL.appendingPathComponent($0) }
        let title = project.title?.nilIfBlank ?? rootURL.lastPathComponent
        let supportStatus = supportStatusFor(type: type, entryURL: entryURL)

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
            return .unsupported("Web wallpapers are planned for phase 2")
        case .scene:
            return .unsupported("Scene wallpapers are planned for later R&D")
        case .application:
            return .unsupported("Windows application wallpapers are out of scope")
        case .unknown:
            return .unsupported("Unknown Wallpaper Engine project type")
        }
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

private struct ProjectJSON: Decodable {
    let type: String?
    let file: String?
    let title: String?
    let preview: String?
    let general: GeneralJSON?
}

private struct GeneralJSON: Decodable {
    let properties: [String: WallpaperProperty]?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
