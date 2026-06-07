import AppKit
import Foundation
import WallpaperEngineCore

@MainActor
enum ScenePackageSupport {
    struct RenderableScene {
        let backgroundImageURL: URL?
        let audioStyle: AudioResponsiveOverlayStyle?
    }

    private struct AudioBarPass {
        let constants: [String: Any]
        let combos: [String: Any]
        let score: Int
    }

    private static var cache: [String: RenderableScene] = [:]

    static func renderableScene(for project: WallpaperProject) -> RenderableScene? {
        guard let packageURL = packageURL(for: project) else {
            return nil
        }

        let cacheKey = cacheKey(for: project, packageURL: packageURL)
        if let cached = cache[cacheKey] {
            return cached
        }

        guard let package = try? ScenePackageArchive(url: packageURL) else {
            return nil
        }

        let sceneObject = sceneObject(from: package, project: project)
        let cacheDirectoryURL = sceneCacheDirectoryURL(for: project, packageURL: packageURL)
        let backgroundImageURL = extractBackgroundImage(
            from: package,
            sceneObject: sceneObject,
            cacheDirectoryURL: cacheDirectoryURL
        )
        let audioStyle = sceneObject.flatMap { audioResponsiveStyle(from: $0, project: project) }

        let scene = RenderableScene(backgroundImageURL: backgroundImageURL, audioStyle: audioStyle)
        cache[cacheKey] = scene
        return scene
    }

    private static func packageURL(for project: WallpaperProject) -> URL? {
        var candidates: [URL] = []

        if let entryURL = project.entryURL,
           SupportedScenePackageFile.isKnownScenePackageFile(entryURL) {
            candidates.append(entryURL)
        }

        if let fileName = project.fileName?.nilIfBlank {
            let fileURL = project.rootURL.appendingPathComponent(fileName)
            candidates.append(fileURL)
            candidates.append(fileURL.deletingPathExtension().appendingPathExtension("pkg"))
        }

        candidates.append(project.rootURL.appendingPathComponent("scene.pkg"))

        if let packageURLs = try? FileManager.default.contentsOfDirectory(
            at: project.rootURL,
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

    private static func sceneObject(
        from package: ScenePackageArchive,
        project: WallpaperProject
    ) -> Any? {
        if let fileName = project.fileName?.nilIfBlank,
           let object = package.jsonObject(named: fileName) {
            return object
        }

        if let object = package.jsonObject(named: "scene.json") {
            return object
        }

        return package.firstJSONObject { name in
            name.hasSuffix(".json") && !name.hasPrefix("materials/") && !name.hasPrefix("models/")
        }
    }

    private static func extractBackgroundImage(
        from package: ScenePackageArchive,
        sceneObject: Any?,
        cacheDirectoryURL: URL
    ) -> URL? {
        for fileExtension in ["gif", "png", "jpg"] {
            let cachedURL = cacheDirectoryURL.appendingPathComponent("background.\(fileExtension)")
            if FileManager.default.fileExists(atPath: cachedURL.path) {
                return cachedURL
            }
        }

        guard let textureData = primaryTextureData(from: package, sceneObject: sceneObject),
              let decodedTexture = TextureFileDecoder.decode(textureData)
        else {
            return nil
        }

        let outputURL = cacheDirectoryURL.appendingPathComponent("background.\(decodedTexture.fileExtension)")
        do {
            try FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
            try decodedTexture.data.write(to: outputURL, options: .atomic)
            return outputURL
        } catch {
            NSLog("[WallpaperEngineMac ScenePackage] failed to cache background: %@", error.localizedDescription)
            return nil
        }
    }

    private static func primaryTextureData(from package: ScenePackageArchive, sceneObject: Any?) -> Data? {
        if let sceneObject,
           let texturePath = primaryTexturePath(from: sceneObject, package: package),
           let data = package.data(named: texturePath) {
            return data
        }

        return package.firstData { name in
            name.hasPrefix("materials/") && name.hasSuffix(".tex")
        }
    }

    private static func primaryTexturePath(from sceneObject: Any, package: ScenePackageArchive) -> String? {
        guard let scene = sceneObject as? [String: Any],
              let objects = scene["objects"] as? [[String: Any]]
        else {
            return nil
        }

        var candidates: [(path: String, score: Double)] = []
        for (index, object) in objects.enumerated() {
            guard sceneObjectIsVisible(object) else {
                continue
            }
            guard let modelPath = object["image"] as? String,
                  let model = package.jsonObject(named: modelPath) as? [String: Any],
                  let materialPath = model["material"] as? String,
                  let material = package.jsonObject(named: materialPath) as? [String: Any],
                  let textureName = firstTextureName(in: material)
            else {
                continue
            }

            let texturePath: String
            if textureName.hasSuffix(".tex") {
                texturePath = textureName
            } else if textureName.contains("/") {
                texturePath = "\(textureName).tex"
            } else {
                texturePath = "materials/\(textureName).tex"
            }

            let name = (object["name"] as? String ?? modelPath).lowercased()
            let size = numericVector(object["size"]) ?? [1, 1]
            let area = max(1, (size.first ?? 1) * (size.dropFirst().first ?? 1))
            var score = area - Double(index) * 0.001
            if name.contains("cover") {
                score *= 2
            }
            if name.contains("background") {
                score *= 1.25
            }
            candidates.append((texturePath, score))
        }

        return candidates.max { $0.score < $1.score }?.path
    }

    private static func sceneObjectIsVisible(_ object: [String: Any]) -> Bool {
        guard let visible = object["visible"] else {
            return true
        }

        if let bool = visible as? Bool {
            return bool
        }
        if let number = visible as? NSNumber {
            return number.boolValue
        }
        if let visibility = visible as? [String: Any] {
            if let bool = visibility["value"] as? Bool {
                return bool
            }
            if let number = visibility["value"] as? NSNumber {
                return number.boolValue
            }
        }

        return true
    }

    private static func numericVector(_ value: Any?) -> [Double]? {
        guard let string = string(value) else {
            return nil
        }

        let numbers = string
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n" })
            .compactMap { Double($0) }
        return numbers.isEmpty ? nil : numbers
    }

    private static func firstTextureName(in material: [String: Any]) -> String? {
        guard let passes = material["passes"] as? [[String: Any]] else {
            return nil
        }

        for pass in passes {
            if let textures = pass["textures"] as? [String],
               let texture = textures.first?.nilIfBlank {
                return texture
            }
        }

        return nil
    }

    private static func pngData(fromTextureData textureData: Data) -> Data? {
        let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        guard let startRange = textureData.range(of: signature),
              let endRange = textureData.range(of: Data("IEND".utf8), options: [], in: startRange.upperBound..<textureData.endIndex)
        else {
            return nil
        }

        let endIndex = min(textureData.endIndex, endRange.lowerBound + 8)
        return textureData.subdata(in: startRange.lowerBound..<endIndex)
    }

    private static func audioResponsiveStyle(
        from sceneObject: Any,
        project: WallpaperProject
    ) -> AudioResponsiveOverlayStyle? {
        if let enabled = boolProjectProperty("audioresponse", in: project),
           !enabled {
            return nil
        }

        guard let pass = bestAudioBarPass(in: sceneObject) else {
            return fallbackAudioResponsiveStyle(for: project)
        }

        let constants = pass.constants
        let combos = pass.combos
        let barCountValue = constantValue(
            in: constants,
            exactNames: ["Bar Count"],
            fuzzyTerms: [["bar", "count"], ["bars"], ["count"]]
        )
        let spacingValue = constantValue(
            in: constants,
            exactNames: ["Bar Spacing"],
            fuzzyTerms: [["bar", "spacing"], ["spacing"], ["gap"]]
        )
        let boundsValue = constantValue(
            in: constants,
            exactNames: ["Lower/Upper Bar Bounds"],
            fuzzyTerms: [["lower", "upper", "bar"], ["bar", "bounds"], ["bounds"]]
        )
        let opacityValue = constantValue(
            in: constants,
            exactNames: ["ui_editor_properties_opacity", "Bar Opacity"],
            fuzzyTerms: [["opacity"], ["alpha"]]
        )
        let colorValue = constantValue(
            in: constants,
            exactNames: ["Bar Color"],
            fuzzyTerms: [["bar", "color"], ["color"], ["tint"]]
        )
        let angleValue = constantValue(
            in: constants,
            exactNames: ["Circle Start/End Angles"],
            fuzzyTerms: [["circle", "angle"], ["start", "end", "angle"]]
        )

        let barCount = max(1, min(200, Int(numberValue(barCountValue, project: project) ?? 32)))
        let spacing = CGFloat(numberValue(spacingValue, project: project) ?? 0.1)
        let bounds = vectorValue(boundsValue, project: project) ?? [0, 0.13]
        let lowerBound = CGFloat(bounds.first ?? 0)
        let upperBound = CGFloat(bounds.dropFirst().first ?? 0.13)
        let opacity = CGFloat(numberValue(opacityValue, project: project) ?? 1)
        let color = color(from: colorValue, project: project)
            ?? projectAudioColor(in: project)
            ?? NSColor(calibratedRed: 0.286, green: 0.353, blue: 0.973, alpha: 1)
        let angles = vectorValue(angleValue, project: project) ?? [0, 360]
        let shape = Int(numberValue(comboValue("SHAPE", in: combos), project: project) ?? 0)

        return AudioResponsiveOverlayStyle(
            source: .workshopAudioBars,
            placement: placement(forWallpaperEngineShape: shape),
            barCount: barCount,
            color: color,
            lowerBound: lowerBound,
            upperBound: upperBound,
            spacing: spacing,
            opacity: opacity,
            angleStart: CGFloat(angles.first ?? 0),
            angleEnd: CGFloat(angles.dropFirst().first ?? 360)
        )
    }

    private static func fallbackAudioResponsiveStyle(for project: WallpaperProject) -> AudioResponsiveOverlayStyle? {
        guard project.usesAudioResponsiveOverlay || projectAudioColor(in: project) != nil else {
            return nil
        }

        return AudioResponsiveOverlayStyle(
            source: .workshopAudioBars,
            placement: .bottom,
            barCount: 32,
            color: projectAudioColor(in: project) ?? .systemTeal,
            lowerBound: 0,
            upperBound: 0.14,
            spacing: 0.12,
            opacity: 0.85,
            angleStart: 0,
            angleEnd: 360
        )
    }

    private static func bestAudioBarPass(in value: Any) -> AudioBarPass? {
        audioBarPasses(in: value).max { lhs, rhs in
            lhs.score < rhs.score
        }
    }

    private static func audioBarPasses(
        in value: Any,
        inheritedHints: [String] = []
    ) -> [AudioBarPass] {
        if let object = value as? [String: Any] {
            let hints = inheritedHints + hintStrings(in: object)
            var matches: [AudioBarPass] = []

            if let constants = object["constantshadervalues"] as? [String: Any] {
                let combos = object["combos"] as? [String: Any] ?? [:]
                let score = audioBarPassScore(constants: constants, combos: combos, hints: hints)
                if score > 0 {
                    matches.append(AudioBarPass(constants: constants, combos: combos, score: score))
                }
            }

            for child in object.values {
                matches.append(contentsOf: audioBarPasses(in: child, inheritedHints: hints))
            }

            return matches
        } else if let array = value as? [Any] {
            var matches: [AudioBarPass] = []
            for child in array {
                matches.append(contentsOf: audioBarPasses(in: child, inheritedHints: inheritedHints))
            }
            return matches
        }

        return []
    }

    private static func audioBarPassScore(
        constants: [String: Any],
        combos: [String: Any],
        hints: [String]
    ) -> Int {
        let normalizedHints = (hints + Array(constants.keys) + Array(combos.keys)).map(normalized)
        let containsHint: (String) -> Bool = { term in
            normalizedHints.contains { $0.contains(term) }
        }

        let hasAudioHint = ["simpleaudiobars", "audio", "music", "sound", "visualizer", "spectrum", "fft", "equalizer"]
            .contains(where: containsHint)
        let hasBarStyle = hasConstant(
            in: constants,
            fuzzyTerms: [["bar", "count"], ["bar", "color"], ["bar", "bounds"], ["bar", "spacing"], ["spectrum"]]
        )

        guard containsHint("simpleaudiobars") || (hasAudioHint && (hasBarStyle || comboValue("SHAPE", in: combos) != nil)) else {
            return 0
        }

        var score = 1
        if containsHint("simpleaudiobars") { score += 10 }
        if containsHint("audio") { score += 4 }
        if containsHint("visualizer") || containsHint("spectrum") { score += 3 }
        if comboValue("SHAPE", in: combos) != nil { score += 3 }
        if hasConstant(in: constants, fuzzyTerms: [["bar", "count"], ["count"]]) { score += 3 }
        if hasConstant(in: constants, fuzzyTerms: [["bar", "color"], ["color"]]) { score += 3 }
        if hasConstant(in: constants, fuzzyTerms: [["bar", "bounds"], ["bounds"]]) { score += 2 }
        if hasConstant(in: constants, fuzzyTerms: [["bar", "spacing"], ["spacing"]]) { score += 1 }
        return score
    }

    private static func hintStrings(in object: [String: Any]) -> [String] {
        let interestingKeys = Set([
            "description",
            "effect",
            "file",
            "group",
            "material",
            "name",
            "replacementkey",
            "shader"
        ])
        var hints = Array(object.keys)
        for (key, value) in object where interestingKeys.contains(normalized(key)) {
            if let string = string(value) {
                hints.append(string)
            }
        }
        return hints
    }

    private static func placement(forWallpaperEngineShape shape: Int) -> AudioResponsiveOverlayStyle.Placement {
        switch shape {
        case 1:
            return .top
        case 2:
            return .left
        case 3:
            return .right
        case 4:
            return .circleInner
        case 5:
            return .circleOuter
        case 6:
            return .centerHorizontal
        case 7:
            return .centerVertical
        case 8:
            return .stereoHorizontal
        case 9:
            return .stereoVertical
        default:
            return .bottom
        }
    }

    private static func constantValue(
        in constants: [String: Any],
        exactNames: [String],
        fuzzyTerms: [[String]]
    ) -> Any? {
        for name in exactNames {
            if let value = constants[name] {
                return value
            }
        }

        for (key, value) in constants where matches(key, fuzzyTerms: fuzzyTerms) {
            return value
        }

        return nil
    }

    private static func hasConstant(in constants: [String: Any], fuzzyTerms: [[String]]) -> Bool {
        constants.keys.contains { matches($0, fuzzyTerms: fuzzyTerms) }
    }

    private static func comboValue(_ key: String, in combos: [String: Any]) -> Any? {
        combos[key] ?? combos.first { normalized($0.key) == normalized(key) }?.value
    }

    private static func matches(_ key: String, fuzzyTerms: [[String]]) -> Bool {
        let normalizedKey = normalized(key)
        return fuzzyTerms.contains { terms in
            terms.allSatisfy { normalizedKey.contains(normalized($0)) }
        }
    }

    private static func color(from value: Any?, project: WallpaperProject) -> NSColor? {
        guard let components = vectorValue(value, project: project), components.count >= 3 else {
            return nil
        }

        return NSColor(
            calibratedRed: CGFloat(min(max(components[0], 0), 1)),
            green: CGFloat(min(max(components[1], 0), 1)),
            blue: CGFloat(min(max(components[2], 0), 1)),
            alpha: 1
        )
    }

    private static func vectorValue(_ value: Any?, project: WallpaperProject) -> [Double]? {
        let resolved = resolveUserBackedValue(value, project: project)
        if let array = resolved as? [Any] {
            let numbers = array.compactMap { numberValue($0, project: project) }
            return numbers.isEmpty ? nil : numbers
        }
        if let number = resolved as? NSNumber {
            return [number.doubleValue]
        }
        guard let string = string(resolved) else {
            return nil
        }
        let numbers = string
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n" })
            .compactMap { Double($0) }
        return numbers.isEmpty ? nil : numbers
    }

    private static func numberValue(_ value: Any?, project: WallpaperProject) -> Double? {
        let resolved = resolveUserBackedValue(value, project: project)
        if let number = resolved as? NSNumber {
            return number.doubleValue
        }
        if let string = resolved as? String {
            return Double(string)
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func resolveUserBackedValue(_ value: Any?, project: WallpaperProject) -> Any? {
        guard let object = value as? [String: Any] else {
            return value
        }

        if let userKey = object["user"] as? String,
           let projectValue = projectPropertyValue(userKey, in: project) {
            return projectValue
        }

        return object["value"] ?? value
    }

    private static func projectAudioColor(in project: WallpaperProject) -> NSColor? {
        for key in ["audioresponsecolor", "audioColor", "audiocolor", "barColor", "visualizerColor"] {
            if let value = projectPropertyValue(key, in: project),
               let color = color(from: value, project: project) {
                return color
            }
        }
        return nil
    }

    private static func projectPropertyValue(_ key: String, in project: WallpaperProject) -> Any? {
        if let value = project.properties[key]?.value {
            return anyValue(from: value)
        }
        if let value = project.properties.first(where: { normalized($0.key) == normalized(key) })?.value.value {
            return anyValue(from: value)
        }
        return nil
    }

    private static func anyValue(from value: JSONValue) -> Any? {
        switch value {
        case let .string(string):
            return string
        case let .number(number):
            return number
        case let .bool(bool):
            return bool
        case let .array(values):
            return values.compactMap(anyValue)
        case let .object(object):
            return object.compactMapValues { anyValue(from: $0) }
        default:
            return nil
        }
    }

    private static func boolProjectProperty(_ key: String, in project: WallpaperProject) -> Bool? {
        guard let value = projectPropertyValue(key, in: project) else {
            return nil
        }

        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? Double {
            return number != 0
        }
        if let number = value as? NSNumber {
            return number.doubleValue != 0
        }
        if let string = value as? String {
            return Bool(string.lowercased())
        }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            }
        }
    }

    private static func cacheKey(for project: WallpaperProject, packageURL: URL) -> String {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: packageURL.path)) ?? [:]
        let size = attributes[.size] as? NSNumber
        let modified = attributes[.modificationDate] as? Date
        return [
            "tex-v2",
            project.rootURL.path,
            size?.stringValue ?? "0",
            String(Int(modified?.timeIntervalSince1970 ?? 0))
        ].joined(separator: "|")
    }

    private static func sceneCacheDirectoryURL(for project: WallpaperProject, packageURL: URL) -> URL {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: packageURL.path)) ?? [:]
        let size = (attributes[.size] as? NSNumber)?.stringValue ?? "0"
        let modified = String(Int((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0))
        let folderName = "\(sanitized(project.id))-tex-v2-\(size)-\(modified)"

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/WallpaperEngineMac/ScenePackages", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .nilIfBlank ?? "scene"
    }
}

private struct ScenePackageArchive {
    private struct Entry {
        let name: String
        let offset: Int
        let size: Int
    }

    private let data: Data
    private let dataStart: Int
    private let entries: [Entry]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        var cursor = 0
        let magicLength = try Self.readUInt32(data, cursor: &cursor)
        let magicData = try Self.readData(data, cursor: &cursor, count: magicLength)
        let magic = String(data: magicData, encoding: .utf8)
        guard Self.isPackageMagic(magic) else {
            throw ScenePackageArchiveError.invalidMagic
        }

        let entryCount = try Self.readUInt32(data, cursor: &cursor)
        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)

        for _ in 0..<entryCount {
            let nameLength = try Self.readUInt32(data, cursor: &cursor)
            let nameData = try Self.readData(data, cursor: &cursor, count: nameLength)
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw ScenePackageArchiveError.invalidName
            }
            let offset = try Self.readUInt32(data, cursor: &cursor)
            let size = try Self.readUInt32(data, cursor: &cursor)
            entries.append(Entry(name: name, offset: offset, size: size))
        }

        self.data = data
        self.dataStart = cursor
        self.entries = entries
    }

    func data(named name: String) -> Data? {
        guard let entry = entries.first(where: { $0.name == name }) else {
            return nil
        }
        return data(for: entry)
    }

    func firstData(where predicate: (String) -> Bool) -> Data? {
        guard let entry = entries.first(where: { predicate($0.name) }) else {
            return nil
        }
        return data(for: entry)
    }

    func firstJSONObject(where predicate: (String) -> Bool) -> Any? {
        guard let entry = entries.first(where: { predicate($0.name) }),
              let data = data(for: entry)
        else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    func jsonObject(named name: String) -> Any? {
        guard let data = data(named: name) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func data(for entry: Entry) -> Data? {
        let start = dataStart + entry.offset
        let end = start + entry.size
        guard start >= data.startIndex, end <= data.endIndex, start <= end else {
            return nil
        }
        return data.subdata(in: start..<end)
    }

    private static func readUInt32(_ data: Data, cursor: inout Int) throws -> Int {
        let raw = try readData(data, cursor: &cursor, count: 4)
        let bytes = [UInt8](raw)
        return Int(UInt32(bytes[0]) |
            UInt32(bytes[1]) << 8 |
            UInt32(bytes[2]) << 16 |
            UInt32(bytes[3]) << 24)
    }

    private static func isPackageMagic(_ magic: String?) -> Bool {
        guard let magic,
              magic.count == 8,
              magic.hasPrefix("PKGV")
        else {
            return false
        }

        return magic.dropFirst(4).allSatisfy(\.isNumber)
    }

    private static func readData(_ data: Data, cursor: inout Int, count: Int) throws -> Data {
        guard count >= 0, cursor >= data.startIndex, cursor + count <= data.endIndex else {
            throw ScenePackageArchiveError.truncated
        }
        defer {
            cursor += count
        }
        return data.subdata(in: cursor..<(cursor + count))
    }
}

private enum ScenePackageArchiveError: Error {
    case invalidMagic
    case invalidName
    case truncated
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
