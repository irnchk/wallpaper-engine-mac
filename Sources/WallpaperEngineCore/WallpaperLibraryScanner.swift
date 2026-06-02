import Foundation

public struct WallpaperLibraryScanner: Sendable {
    public enum ScannerError: Error, LocalizedError {
        case missingPath(URL)

        public var errorDescription: String? {
            switch self {
            case let .missingPath(url):
                return "Path does not exist: \(url.path)"
            }
        }
    }

    public let maximumProjectSearchDepth: Int

    public init(maximumProjectSearchDepth: Int = 3) {
        self.maximumProjectSearchDepth = maximumProjectSearchDepth
    }

    public func scan(roots: [URL]) throws -> [WallpaperProject] {
        var projectsByRoot: [String: WallpaperProject] = [:]

        for root in roots {
            let projects: [WallpaperProject]
            do {
                projects = try scan(rootURL: root)
            } catch {
                continue
            }

            for project in projects {
                projectsByRoot[project.rootURL.path] = project
            }
        }

        return projectsByRoot.values.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    public func scan(rootURL: URL) throws -> [WallpaperProject] {
        let fileManager = FileManager.default
        let standardizedRoot = rootURL.standardizedFileURL
        guard fileManager.fileExists(atPath: standardizedRoot.path) else {
            throw ScannerError.missingPath(standardizedRoot)
        }

        if standardizedRoot.lastPathComponent == "project.json" {
            return [try WallpaperProject.load(projectJSONURL: standardizedRoot)]
        }

        if SupportedVideoFile.isKnownVideoFile(standardizedRoot) {
            return [WallpaperProject.directVideo(url: standardizedRoot)]
        }

        let directProjectURL = standardizedRoot.appendingPathComponent("project.json")
        if fileManager.fileExists(atPath: directProjectURL.path) {
            return [try WallpaperProject.load(projectJSONURL: directProjectURL)]
        }

        return try scanProjectFilesBelow(standardizedRoot).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func scanProjectFilesBelow(_ rootURL: URL) throws -> [WallpaperProject] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        let rootDepth = rootURL.pathComponents.count
        var projects: [WallpaperProject] = []

        for case let url as URL in enumerator {
            let depth = url.deletingLastPathComponent().pathComponents.count - rootDepth
            if depth > maximumProjectSearchDepth {
                enumerator.skipDescendants()
                continue
            }

            guard url.lastPathComponent == "project.json" else {
                continue
            }

            do {
                projects.append(try WallpaperProject.load(projectJSONURL: url))
                enumerator.skipDescendants()
            } catch {
                continue
            }
        }

        return projects
    }
}
