import AppKit
import Foundation
import WallpaperEngineCore

enum InteractiveProjectEditorError: LocalizedError {
    case missingProjectFile
    case unreadableProjectJSON
    case unsupportedObjectsFormat
    case unsupportedImage(URL)
    case unsupportedVideo(URL)
    case unsupportedLive2DEntry(URL)
    case objectNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingProjectFile:
            return "Interactive objects can only be added to folders with a project.json file."
        case .unreadableProjectJSON:
            return "Could not read project.json as a JSON object."
        case .unsupportedObjectsFormat:
            return "project.json has an interactive.objects value that is not an array."
        case let .unsupportedImage(url):
            return "\(url.lastPathComponent) could not be loaded as an image."
        case let .unsupportedVideo(url):
            return "\(url.lastPathComponent) is not a supported video object. Use mp4, m4v, or mov."
        case let .unsupportedLive2DEntry(url):
            return "\(url.lastPathComponent) is not a Live2D Web entry. Choose an HTML file that loads the Live2D model."
        case let .objectNotFound(objectID):
            return "Could not find interactive object \(objectID)."
        }
    }
}

@MainActor
struct InteractiveProjectEditor {
    private static let objectFolderName = "InteractiveObjects"

    static func addImageObject(imageURL: URL, to project: WallpaperProject) throws {
        guard let projectURL = project.projectURL else {
            throw InteractiveProjectEditorError.missingProjectFile
        }
        guard NSImage(contentsOf: imageURL) != nil else {
            throw InteractiveProjectEditorError.unsupportedImage(imageURL)
        }

        let objectID = "image-\(UUID().uuidString.lowercased())"
        let copiedImageRelativePath = try copyFile(imageURL, objectID: objectID, to: project.rootURL)
        try appendObject([
            "id": objectID,
            "type": "image",
            "title": imageURL.deletingPathExtension().lastPathComponent,
            "file": copiedImageRelativePath,
            "frame": [
                "x": 0.68,
                "y": 0.24,
                "width": 0.18,
                "height": 0.18
            ],
            "opacity": 1.0,
            "cornerRadius": 12.0,
            "draggable": true
        ], to: projectURL)
    }

    static func addVideoObject(videoURL: URL, to project: WallpaperProject) throws {
        guard let projectURL = project.projectURL else {
            throw InteractiveProjectEditorError.missingProjectFile
        }
        guard SupportedVideoFile.videoExtensions.contains(videoURL.pathExtension.lowercased()) else {
            throw InteractiveProjectEditorError.unsupportedVideo(videoURL)
        }

        let objectID = "video-\(UUID().uuidString.lowercased())"
        let copiedVideoRelativePath = try copyFile(videoURL, objectID: objectID, to: project.rootURL)
        try appendObject([
            "id": objectID,
            "type": "video",
            "title": videoURL.deletingPathExtension().lastPathComponent,
            "file": copiedVideoRelativePath,
            "frame": [
                "x": 0.62,
                "y": 0.22,
                "width": 0.28,
                "height": 0.18
            ],
            "opacity": 1.0,
            "cornerRadius": 12.0,
            "draggable": true
        ], to: projectURL)
    }

    static func addLive2DWebObject(entryHTMLURL: URL, to project: WallpaperProject) throws {
        guard let projectURL = project.projectURL else {
            throw InteractiveProjectEditorError.missingProjectFile
        }
        guard entryHTMLURL.pathExtension.lowercased() == "html" || entryHTMLURL.pathExtension.lowercased() == "htm" else {
            throw InteractiveProjectEditorError.unsupportedLive2DEntry(entryHTMLURL)
        }

        let objectID = "live2d-\(UUID().uuidString.lowercased())"
        let copiedEntryRelativePath = try copyFolderContainingEntry(entryHTMLURL, objectID: objectID, to: project.rootURL)
        try appendObject([
            "id": objectID,
            "type": "live2d-web",
            "title": entryHTMLURL.deletingPathExtension().lastPathComponent,
            "file": copiedEntryRelativePath,
            "frame": [
                "x": 0.68,
                "y": 0.16,
                "width": 0.22,
                "height": 0.34
            ],
            "opacity": 1.0,
            "cornerRadius": 0.0,
            "draggable": true
        ], to: projectURL)
    }

    static func removeObject(objectID: String, from project: WallpaperProject) throws {
        guard let projectURL = project.projectURL else {
            throw InteractiveProjectEditorError.missingProjectFile
        }

        var projectJSON = try loadProjectJSON(projectURL)
        var interactive = projectJSON["interactive"] as? [String: Any] ?? [:]
        let existingObjects = interactive["objects"]
        guard var objects = existingObjects as? [[String: Any]] else {
            if existingObjects == nil {
                throw InteractiveProjectEditorError.objectNotFound(objectID)
            }
            throw InteractiveProjectEditorError.unsupportedObjectsFormat
        }

        guard let index = objects.firstIndex(where: { $0["id"] as? String == objectID }) else {
            throw InteractiveProjectEditorError.objectNotFound(objectID)
        }

        let removedObject = objects.remove(at: index)
        interactive["objects"] = objects
        projectJSON["interactive"] = interactive
        try writeProjectJSON(projectJSON, to: projectURL)
        try removeCopiedAssetIfSafe(removedObject["file"] as? String, from: project.rootURL)
    }

    private static func loadProjectJSON(_ projectURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: projectURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InteractiveProjectEditorError.unreadableProjectJSON
        }
        return object
    }

    private static func writeProjectJSON(_ projectJSON: [String: Any], to projectURL: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: projectJSON,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: projectURL, options: .atomic)
    }

    private static func appendObject(_ object: [String: Any], to projectURL: URL) throws {
        var projectJSON = try loadProjectJSON(projectURL)
        var interactive = projectJSON["interactive"] as? [String: Any] ?? [:]

        let existingObjects = interactive["objects"]
        var objects = existingObjects as? [[String: Any]] ?? []
        if existingObjects != nil, interactive["objects"] as? [[String: Any]] == nil {
            throw InteractiveProjectEditorError.unsupportedObjectsFormat
        }

        objects.append(object)
        interactive["objects"] = objects
        projectJSON["interactive"] = interactive
        try writeProjectJSON(projectJSON, to: projectURL)
    }

    private static func copyFile(_ sourceURL: URL, objectID: String, to projectRootURL: URL) throws -> String {
        let fileManager = FileManager.default
        let objectFolderURL = projectRootURL.appendingPathComponent(objectFolderName, isDirectory: true)
        try fileManager.createDirectory(at: objectFolderURL, withIntermediateDirectories: true)

        let sourceExtension = sourceURL.pathExtension.nilIfBlank ?? "dat"
        let destinationFileName = "\(objectID).\(sourceExtension.lowercased())"
        let destinationURL = objectFolderURL.appendingPathComponent(destinationFileName)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return "\(objectFolderName)/\(destinationFileName)"
    }

    private static func copyFolderContainingEntry(
        _ entryURL: URL,
        objectID: String,
        to projectRootURL: URL
    ) throws -> String {
        let fileManager = FileManager.default
        let objectFolderURL = projectRootURL.appendingPathComponent(objectFolderName, isDirectory: true)
        try fileManager.createDirectory(at: objectFolderURL, withIntermediateDirectories: true)

        let sourceFolderURL = entryURL.deletingLastPathComponent()
        let destinationFolderURL = objectFolderURL.appendingPathComponent(objectID, isDirectory: true)
        if fileManager.fileExists(atPath: destinationFolderURL.path) {
            try fileManager.removeItem(at: destinationFolderURL)
        }
        try fileManager.copyItem(at: sourceFolderURL, to: destinationFolderURL)
        return "\(objectFolderName)/\(objectID)/\(entryURL.lastPathComponent)"
    }

    private static func removeCopiedAssetIfSafe(_ relativePath: String?, from projectRootURL: URL) throws {
        guard let relativePath = relativePath?.nilIfBlank,
              relativePath.hasPrefix("\(objectFolderName)/")
        else {
            return
        }

        let components = relativePath.split(separator: "/").map(String.init)
        let targetURL: URL
        if components.count >= 3, components[1].hasPrefix("live2d-") {
            targetURL = projectRootURL.appendingPathComponent(objectFolderName).appendingPathComponent(components[1])
        } else {
            targetURL = projectRootURL.appendingPathComponent(relativePath)
        }

        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
