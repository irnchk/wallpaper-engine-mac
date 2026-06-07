import Foundation
import WallpaperEngineCore

@main
struct SmokeTestRunner {
    static func main() throws {
        try loadsVideoProjectJSON()
        try scannerFindsWorkshopChildren()
        try scannerSkipsBrokenWorkshopChildren()
        try scannerSkipsBrokenRootsInMultiRootScan()
        try webmIsDetectedButNotRuntimePlayableYet()
        try webWallpaperIsPlayable()
        try gifSceneUsesPreviewFallback()
        try scenePackageUsesPackageInsteadOfTinyIconPreview()
        try gifScenePackageUsesMatchingPackage()
        try audioResponsiveWorkshopMetadataIsDetected()
        try interactiveObjectsDecode()
        try directVideoImport()
        try bundledSampleWallpaperIsImportable()
        print("WallpaperEngineSmokeTests passed")
    }

    private static func loadsVideoProjectJSON() throws {
        try withTemporaryRoot { temporaryRoot in
            let projectDirectory = temporaryRoot.appendingPathComponent("12345")
            try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
            try Data().write(to: projectDirectory.appendingPathComponent("wallpaper.mp4"))
            try Data().write(to: projectDirectory.appendingPathComponent("preview.jpg"))

            let json = """
            {
              "type": "video",
              "file": "wallpaper.mp4",
              "title": "Quiet Loop",
              "preview": "preview.jpg",
              "general": {
                "properties": {
                  "volume": { "type": "slider", "text": "Volume", "value": 0 }
                }
              }
            }
            """
            try write(json, to: projectDirectory.appendingPathComponent("project.json"))

            let project = try WallpaperProject.load(projectJSONURL: projectDirectory.appendingPathComponent("project.json"))

            try expect(project.id == "12345", "id should come from workshop folder")
            try expect(project.title == "Quiet Loop", "title should decode")
            try expect(project.type == .video, "type should decode")
            try expect(project.entryURL?.lastPathComponent == "wallpaper.mp4", "entry file should resolve")
            try expect(project.previewURL?.lastPathComponent == "preview.jpg", "preview should resolve")
            try expect(project.isPlayableNow, "mp4 video should be playable")
            try expect(project.properties["volume"]?.type == "slider", "properties should decode")
        }
    }

    private static func scannerFindsWorkshopChildren() throws {
        try withTemporaryRoot { temporaryRoot in
            let workshopRoot = temporaryRoot.appendingPathComponent("431960")
            let first = workshopRoot.appendingPathComponent("111")
            let second = workshopRoot.appendingPathComponent("222")
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
            try writeProject(title: "B", file: "b.mp4", type: "video", to: first)
            try writeProject(title: "A", file: "a.mp4", type: "video", to: second)

            let projects = try WallpaperLibraryScanner().scan(rootURL: workshopRoot)

            try expect(projects.map(\.title) == ["A", "B"], "scanner should sort projects by title")
            try expect(projects.allSatisfy(\.isPlayableNow), "all mp4 projects should be playable")
        }
    }

    private static func scannerSkipsBrokenWorkshopChildren() throws {
        try withTemporaryRoot { temporaryRoot in
            let workshopRoot = temporaryRoot.appendingPathComponent("431960")
            let valid = workshopRoot.appendingPathComponent("111")
            let broken = workshopRoot.appendingPathComponent("broken")
            try FileManager.default.createDirectory(at: valid, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
            try writeProject(title: "Valid", file: "valid.mp4", type: "video", to: valid)
            try write("{", to: broken.appendingPathComponent("project.json"))

            let projects = try WallpaperLibraryScanner().scan(rootURL: workshopRoot)

            try expect(projects.map(\.title) == ["Valid"], "recursive scan should skip broken project.json files")
        }
    }

    private static func scannerSkipsBrokenRootsInMultiRootScan() throws {
        try withTemporaryRoot { temporaryRoot in
            let valid = temporaryRoot.appendingPathComponent("valid")
            let broken = temporaryRoot.appendingPathComponent("broken")
            try FileManager.default.createDirectory(at: valid, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
            try writeProject(title: "Still Here", file: "valid.mp4", type: "video", to: valid)
            try write("{", to: broken.appendingPathComponent("project.json"))

            let projects = try WallpaperLibraryScanner().scan(roots: [broken, valid])

            try expect(projects.map(\.title) == ["Still Here"], "multi-root scan should skip broken roots")
        }
    }

    private static func webmIsDetectedButNotRuntimePlayableYet() throws {
        try withTemporaryRoot { temporaryRoot in
            let projectDirectory = temporaryRoot.appendingPathComponent("webm")
            try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
            try writeProject(title: "Needs Cache", file: "loop.webm", type: "video", to: projectDirectory)

            let project = try WallpaperProject.load(projectJSONURL: projectDirectory.appendingPathComponent("project.json"))

            try expect(!project.isPlayableNow, "webm should wait for import-time transcoding")
            guard case .needsTranscoding = project.supportStatus else {
                throw SmokeTestError.expectationFailed("Expected .needsTranscoding, got \(project.supportStatus)")
            }
        }
    }

    private static func webWallpaperIsPlayable() throws {
        try withTemporaryRoot { temporaryRoot in
            let projectDirectory = temporaryRoot.appendingPathComponent("web")
            try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
            try write("<!doctype html><canvas></canvas>", to: projectDirectory.appendingPathComponent("index.html"))

            let json = """
            {
              "type": "web",
              "file": "index.html",
              "title": "Web Visualizer"
            }
            """
            try write(json, to: projectDirectory.appendingPathComponent("project.json"))

            let project = try WallpaperProject.load(projectJSONURL: projectDirectory.appendingPathComponent("project.json"))

            try expect(project.type == .web, "web type should decode")
            try expect(project.entryURL?.lastPathComponent == "index.html", "web entry should resolve")
            try expect(project.isPlayableNow, "local web wallpaper should be playable")
        }
    }

    private static func gifSceneUsesPreviewFallback() throws {
        try withTemporaryRoot { temporaryRoot in
            let projectDirectory = temporaryRoot.appendingPathComponent("gifscene")
            try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
            try gifHeader(width: 1280, height: 720).write(to: projectDirectory.appendingPathComponent("preview.gif"))

            let json = """
            {
              "type": "scene",
              "file": "gifscene.json",
              "title": "Before the Road",
              "preview": "preview.gif",
              "templateoptions": [
                {
                  "type": "replacetexture",
                  "destination": "materials/background.gif"
                }
              ]
            }
            """
            try write(json, to: projectDirectory.appendingPathComponent("project.json"))

            let project = try WallpaperProject.load(projectJSONURL: projectDirectory.appendingPathComponent("project.json"))

            try expect(project.type == .scene, "scene type should decode")
            try expect(project.entryURL?.lastPathComponent == "preview.gif", "gif scene should use animated preview fallback")
            try expect(project.isPlayableNow, "gif scene preview fallback should be playable")
        }
    }

    private static func scenePackageUsesPackageInsteadOfTinyIconPreview() throws {
        try withTemporaryRoot { temporaryRoot in
            let projectDirectory = temporaryRoot.appendingPathComponent("tiny-preview-scene")
            try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
            try Data().write(to: projectDirectory.appendingPathComponent("scene.pkg"))
            try gifHeader(width: 256, height: 256).write(to: projectDirectory.appendingPathComponent("cyberpunk_gif_icon.gif"))

            let json = """
            {
              "type": "scene",
              "file": "scene.json",
              "title": "Cyberpunk 2077 - Night City [Ultrawide]",
              "preview": "cyberpunk_gif_icon.gif"
            }
            """
            try write(json, to: projectDirectory.appendingPathComponent("project.json"))

            let project = try WallpaperProject.load(projectJSONURL: projectDirectory.appendingPathComponent("project.json"))

            try expect(project.entryURL?.lastPathComponent == "scene.pkg", "scene package should be used instead of tiny icon preview")
            try expect(project.isPlayableNow, "scene package should be applyable even when preview is only an icon")
        }
    }

    private static func gifScenePackageUsesMatchingPackage() throws {
        try withTemporaryRoot { temporaryRoot in
            let projectDirectory = temporaryRoot.appendingPathComponent("gifscene-package")
            try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
            try Data().write(to: projectDirectory.appendingPathComponent("gifscene.pkg"))
            try gifHeader(width: 200, height: 200).write(to: projectDirectory.appendingPathComponent("preview.gif"))

            let json = """
            {
              "type": "scene",
              "file": "gifscene.json",
              "title": "Before the Road",
              "preview": "preview.gif"
            }
            """
            try write(json, to: projectDirectory.appendingPathComponent("project.json"))

            let project = try WallpaperProject.load(projectJSONURL: projectDirectory.appendingPathComponent("project.json"))

            try expect(project.entryURL?.lastPathComponent == "gifscene.pkg", "scene should use package matching the scene json basename")
            try expect(project.isPlayableNow, "matching scene package should be applyable")
        }
    }

    private static func audioResponsiveWorkshopMetadataIsDetected() throws {
        try withTemporaryRoot { temporaryRoot in
            let projectDirectory = temporaryRoot.appendingPathComponent("audio-scene")
            try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
            try gifHeader(width: 1280, height: 720).write(to: projectDirectory.appendingPathComponent("preview.gif"))

            let json = """
            {
              "type": "scene",
              "file": "scene.pkg",
              "title": "Audio Responsive Spectrum",
              "description": "Music reactive visualizer overlay for Wallpaper Engine.",
              "preview": "preview.gif",
              "tags": ["Music"],
              "general": {
                "properties": {
                  "bassIntensity": {
                    "type": "slider",
                    "text": "Bass intensity",
                    "value": 50
                  }
                }
              }
            }
            """
            try write(json, to: projectDirectory.appendingPathComponent("project.json"))

            let project = try WallpaperProject.load(projectJSONURL: projectDirectory.appendingPathComponent("project.json"))

            try expect(project.isPlayableNow, "audio-responsive scene preview fallback should be playable")
            try expect(project.usesAudioResponsiveOverlay, "audio-responsive metadata should enable the overlay")
        }
    }

    private static func directVideoImport() throws {
        try withTemporaryRoot { temporaryRoot in
            let videoURL = temporaryRoot.appendingPathComponent("direct.mov")
            try Data().write(to: videoURL)

            let projects = try WallpaperLibraryScanner().scan(rootURL: videoURL)

            try expect(projects.count == 1, "direct video should produce one project")
            try expect(projects[0].title == "direct", "direct video title should come from filename")
            try expect(projects[0].isPlayableNow, "mov should be playable")
        }
    }

    private static func interactiveObjectsDecode() throws {
        try withTemporaryRoot { temporaryRoot in
            let projectDirectory = temporaryRoot.appendingPathComponent("interactive")
            try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
            try Data().write(to: projectDirectory.appendingPathComponent("wallpaper.mp4"))

            let json = """
            {
              "type": "video",
              "file": "wallpaper.mp4",
              "title": "Interactive Demo",
              "interactive": {
                "objects": [
                  {
                    "id": "album-cover",
                    "type": "albumArt",
                    "title": "Album Cover",
                    "file": "InteractiveObjects/cover.jpg",
                    "frame": {
                      "x": 0.7,
                      "y": 0.2,
                      "width": 0.16,
                      "height": 0.16
                    },
                    "opacity": 0.85,
                    "cornerRadius": 18,
                    "draggable": true
                  },
                  {
                    "id": "video-loop",
                    "type": "video",
                    "file": "InteractiveObjects/loop.mp4"
                  },
                  {
                    "id": "live2d-character",
                    "type": "live2d-web",
                    "file": "InteractiveObjects/live2d/index.html"
                  }
                ]
              }
            }
            """
            try write(json, to: projectDirectory.appendingPathComponent("project.json"))

            let project = try WallpaperProject.load(projectJSONURL: projectDirectory.appendingPathComponent("project.json"))
            let object = try expectNotNil(project.interactiveObjects.first, "interactive object should decode")

            try expect(object.id == "album-cover", "interactive object id should decode")
            try expect(object.isImageLike, "albumArt should be treated as image-like")
            try expect(object.fileURL(relativeTo: project.rootURL)?.lastPathComponent == "cover.jpg", "object file should resolve relative to project")
            try expect(object.frame.x == 0.7, "object frame should decode")
            try expect(object.opacity == 0.85, "object opacity should decode")
            try expect(object.cornerRadius == 18, "object corner radius should decode")
            try expect(object.draggable, "object should decode draggable")
            try expect(project.interactiveObjects[1].isVideoLike, "video object should be treated as video-like")
            try expect(project.interactiveObjects[2].isLive2DLike, "live2d-web object should be treated as Live2D-like")
        }
    }

    private static func bundledSampleWallpaperIsImportable() throws {
        let samplesURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("SampleWallpapers")
        guard FileManager.default.fileExists(atPath: samplesURL.path) else {
            return
        }

        let expectedSampleFolders = [
            "ambient-test-loop",
            "mixkit-abstract-macro-fluid-background",
            "city-pop-a-long-vacation-upscaled-4k",
            "city-pop-dark-4k-aesthetic-city-night",
        ]
        let existingSampleFolders = expectedSampleFolders
            .map { samplesURL.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("project.json").path) }

        guard !existingSampleFolders.isEmpty else {
            return
        }

        let projects = try WallpaperLibraryScanner().scan(roots: existingSampleFolders)
        let sampleTitles = projects.map(\.title)
        try expect(
            Set([
                "Ambient Test Loop (Pixabay 4K)",
                "Abstract Macro Fluid Background",
                "City Pop A Long Vacation (Upscaled 4K)",
                "City Pop Dark 4K: Aesthetic City at the Night",
            ]).isSuperset(of: sampleTitles),
            "sample wallpapers should all be importable"
        )
        try expect(projects.allSatisfy(\.isPlayableNow), "sample wallpapers should be playable")
    }

    private static func withTemporaryRoot(_ body: (URL) throws -> Void) throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WallpaperEngineCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try body(temporaryRoot)
    }

    private static func writeProject(title: String, file: String, type: String, to directory: URL) throws {
        try Data().write(to: directory.appendingPathComponent(file))
        let json = """
        {
          "type": "\(type)",
          "file": "\(file)",
          "title": "\(title)"
        }
        """
        try write(json, to: directory.appendingPathComponent("project.json"))
    }

    private static func write(_ string: String, to url: URL) throws {
        guard let data = string.data(using: .utf8) else {
            throw SmokeTestError.expectationFailed("Could not encode fixture")
        }
        try data.write(to: url)
    }

    private static func gifHeader(width: Int, height: Int) -> Data {
        Data([
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
            UInt8(width & 0xFF),
            UInt8((width >> 8) & 0xFF),
            UInt8(height & 0xFF),
            UInt8((height >> 8) & 0xFF),
            0x00, 0x00, 0x00
        ])
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw SmokeTestError.expectationFailed(message)
        }
    }

    private static func expectNotNil<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw SmokeTestError.expectationFailed(message)
        }
        return value
    }
}

private enum SmokeTestError: Error, CustomStringConvertible {
    case expectationFailed(String)

    var description: String {
        switch self {
        case let .expectationFailed(message):
            return message
        }
    }
}
