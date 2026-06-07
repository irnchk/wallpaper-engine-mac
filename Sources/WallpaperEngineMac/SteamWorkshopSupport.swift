import AppKit
import Foundation

enum SteamWorkshopSupportError: LocalizedError {
    case invalidPublishedFileID(String)
    case steamCMDNotFound
    case steamCMDDownloadFailed(String)
    case steamCMDTimedOut(String)
    case downloadedItemNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .invalidPublishedFileID(input):
            return "Could not find a Steam Workshop item ID in: \(input)"
        case .steamCMDNotFound:
            return "steamcmd was not found. Install SteamCMD or subscribe in Steam, then import the local Workshop folder."
        case let .steamCMDDownloadFailed(output):
            return """
            SteamCMD could not download the item.

            Wallpaper Engine Workshop downloads often require a Steam account that owns Wallpaper Engine. Try subscribing in Steam and importing the local Workshop folder, or retry with SteamCMD account login.

            \(output)
            """
        case let .steamCMDTimedOut(output):
            return """
            SteamCMD did not finish in time.

            If you used cached login, SteamCMD may be waiting for a password or Steam Guard approval. Run SteamCMD once manually, complete login, then retry.

            \(output)
            """
        case let .downloadedItemNotFound(itemID):
            return "SteamCMD finished, but item \(itemID) was not found on disk."
        }
    }
}

enum SteamWorkshopSupport {
    static let wallpaperEngineAppID = "431960"
    static let wallpaperEngineWorkshopURL = URL(string: "https://steamcommunity.com/app/431960/workshop/")!

    struct SteamCMDAccount {
        let username: String
        let password: String
        let steamGuardCode: String?
    }

    enum SteamCMDLoginMode {
        case account(SteamCMDAccount)
    }

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
        let existingFolders = commonWorkshopFolderURLs()
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return existingFolders.first(where: containsProjectJSON) ?? existingFolders.first
    }

    static func commonWorkshopFolderURLs() -> [URL] {
        let steamClientFolders = steamLibraryRootURLs()
            .map {
                $0
                    .appendingPathComponent("steamapps/workshop/content")
                    .appendingPathComponent(wallpaperEngineAppID)
            }

        let steamCMDFolder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WallpaperEngineMac/SteamCMD/steamapps/workshop/content")
            .appendingPathComponent(wallpaperEngineAppID)

        return uniqueURLs(steamClientFolders + [steamCMDFolder])
    }

    static func downloadItemWithSteamCMD(
        idOrURL: String,
        loginMode: SteamCMDLoginMode,
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
                    commands: steamCMDDownloadCommands(
                        itemID: itemID,
                        downloadRoot: downloadRoot,
                        loginMode: loginMode
                    )
                )

                let itemURL = downloadRoot
                    .appendingPathComponent("steamapps/workshop/content")
                    .appendingPathComponent(wallpaperEngineAppID)
                    .appendingPathComponent(itemID)

                if isDownloadedItemPresent(at: itemURL) {
                    completion(.success(itemURL))
                } else if let existingItemURL = existingWorkshopItemURL(itemID: itemID) {
                    completion(.success(existingItemURL))
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

    private static func steamCMDDownloadCommands(
        itemID: String,
        downloadRoot: URL,
        loginMode: SteamCMDLoginMode
    ) -> [String] {
        var commands = [
            "@sSteamCmdForcePlatformType windows",
            "force_install_dir \(steamCMDArgument(downloadRoot.path))"
        ]

        switch loginMode {
        case let .account(account):
            var loginParts = [
                "login",
                steamCMDArgument(account.username),
                steamCMDArgument(account.password)
            ]
            if let steamGuardCode = account.steamGuardCode?.nilIfBlank {
                loginParts.append(steamCMDArgument(steamGuardCode))
            }
            commands.append(loginParts.joined(separator: " "))
        }

        commands.append("workshop_download_item \(wallpaperEngineAppID) \(itemID)")
        commands.append("quit")
        return commands
    }

    private static func steamCMDArgument(_ value: String) -> String {
        let charactersRequiringQuotes = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"\\"))
        guard value.rangeOfCharacter(from: charactersRequiringQuotes) != nil else {
            return value
        }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func steamCMDDownloadRoot() throws -> URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WallpaperEngineMac/SteamCMD", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func runSteamCMD(
        executableURL: URL,
        commands: [String],
        timeout: TimeInterval = 900
    ) throws -> String {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()

        let script = commands.joined(separator: "\n") + "\n"
        inputPipe.fileHandleForWriting.write(Data(script.utf8))
        inputPipe.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }

        let didTimeOut = process.isRunning
        if didTimeOut {
            process.terminate()
            process.waitUntilExit()
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combinedOutput = [output, error].filter { !$0.isEmpty }.joined(separator: "\n")

        if didTimeOut {
            throw SteamWorkshopSupportError.steamCMDTimedOut(combinedOutput)
        }

        guard process.terminationStatus == 0 else {
            throw SteamWorkshopSupportError.steamCMDDownloadFailed(combinedOutput)
        }

        return combinedOutput
    }

    private static func existingWorkshopItemURL(itemID: String) -> URL? {
        commonWorkshopFolderURLs()
            .map { $0.appendingPathComponent(itemID) }
            .first(where: isDownloadedItemPresent)
    }

    private static func isDownloadedItemPresent(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path)
        else {
            return false
        }
        return !contents.isEmpty
    }

    private static func containsProjectJSON(_ url: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "project.json" {
                return true
            }
        }
        return false
    }

    private static func steamLibraryRootURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let steamRoot = home.appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
        let libraryFoldersURL = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
        var roots = [steamRoot]

        if let vdf = try? String(contentsOf: libraryFoldersURL) {
            let pattern = #""path"\s+"([^"]+)""#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(vdf.startIndex..<vdf.endIndex, in: vdf)
                for match in regex.matches(in: vdf, range: range) {
                    guard let pathRange = Range(match.range(at: 1), in: vdf) else {
                        continue
                    }
                    let path = String(vdf[pathRange])
                        .replacingOccurrences(of: #"\\\\"#, with: #"\"#)
                        .replacingOccurrences(of: #"\/"#, with: #"/"#)
                    roots.append(URL(fileURLWithPath: path, isDirectory: true))
                }
            }
        }

        return uniqueURLs(roots)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let standardizedURL = url.standardizedFileURL
            if seen.insert(standardizedURL.path).inserted {
                result.append(standardizedURL)
            }
        }
        return result
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
