import AppKit
import Foundation

enum SteamWorkshopSupportError: LocalizedError {
    case invalidPublishedFileID(String)
    case steamCMDNotFound
    case steamCMDDownloadFailed(String)
    case downloadedItemNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .invalidPublishedFileID(input):
            return "Could not find a Steam Workshop item ID in: \(input)"
        case .steamCMDNotFound:
            return "steamcmd was not found. Install SteamCMD or subscribe in Steam, then import the local Workshop folder."
        case let .steamCMDDownloadFailed(output):
            return "SteamCMD could not download the item.\n\n\(output)"
        case let .downloadedItemNotFound(itemID):
            return "SteamCMD finished, but item \(itemID) was not found on disk."
        }
    }
}

enum SteamWorkshopSupport {
    static let wallpaperEngineAppID = "431960"
    static let wallpaperEngineWorkshopURL = URL(string: "https://steamcommunity.com/app/431960/workshop/")!

    static func extractPublishedFileID(from input: String) -> String? {
        if let range = input.range(of: #"id=(\d+)"#, options: .regularExpression) {
            let match = String(input[range])
            return match.split(separator: "=").last.map(String.init)
        }

        if let range = input.range(of: #"^\s*\d{6,}\s*$"#, options: .regularExpression) {
            return String(input[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    static func openWorkshop() {
        NSWorkspace.shared.open(wallpaperEngineWorkshopURL)
    }

    static func openWorkshopItem(idOrURL: String) throws {
        guard let itemID = extractPublishedFileID(from: idOrURL),
              let url = URL(string: "steam://url/CommunityFilePage/\(itemID)")
        else {
            throw SteamWorkshopSupportError.invalidPublishedFileID(idOrURL)
        }
        NSWorkspace.shared.open(url)
    }

    static func existingWorkshopFolderURL() -> URL? {
        commonWorkshopFolderURLs().first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func commonWorkshopFolderURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home
                .appendingPathComponent("Library/Application Support/Steam/steamapps/workshop/content")
                .appendingPathComponent(wallpaperEngineAppID),
            home
                .appendingPathComponent("Library/Application Support/WallpaperEngineMac/SteamCMD/steamapps/workshop/content")
                .appendingPathComponent(wallpaperEngineAppID)
        ]
    }

    static func downloadItemWithSteamCMD(
        idOrURL: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let itemID = extractPublishedFileID(from: idOrURL) else {
            completion(.failure(SteamWorkshopSupportError.invalidPublishedFileID(idOrURL)))
            return
        }
        guard let steamCMDURL = steamCMDURL() else {
            completion(.failure(SteamWorkshopSupportError.steamCMDNotFound))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let downloadRoot = try steamCMDDownloadRoot()
                let output = try runSteamCMD(
                    executableURL: steamCMDURL,
                    arguments: [
                        "+force_install_dir",
                        downloadRoot.path,
                        "+login",
                        "anonymous",
                        "+workshop_download_item",
                        wallpaperEngineAppID,
                        itemID,
                        "+quit"
                    ]
                )

                let itemURL = downloadRoot
                    .appendingPathComponent("steamapps/workshop/content")
                    .appendingPathComponent(wallpaperEngineAppID)
                    .appendingPathComponent(itemID)

                if FileManager.default.fileExists(atPath: itemURL.path) {
                    completion(.success(itemURL))
                } else {
                    completion(.failure(SteamWorkshopSupportError.steamCMDDownloadFailed(output)))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private static func steamCMDURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/steamcmd",
            "/usr/local/bin/steamcmd",
            "/usr/bin/steamcmd"
        ].map(URL.init(fileURLWithPath:))

        if let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return candidate
        }

        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("steamcmd")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private static func steamCMDDownloadRoot() throws -> URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WallpaperEngineMac/SteamCMD", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func runSteamCMD(executableURL: URL, arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combinedOutput = [output, error].filter { !$0.isEmpty }.joined(separator: "\n")

        guard process.terminationStatus == 0 else {
            throw SteamWorkshopSupportError.steamCMDDownloadFailed(combinedOutput)
        }

        return combinedOutput
    }
}
