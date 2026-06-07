import AppKit
import Foundation
import ImageIO

struct TextureDecodeResult {
    let data: Data
    let fileExtension: String
}

enum TextureFileDecoder {
    static func decode(_ data: Data) -> TextureDecodeResult? {
        guard data.starts(with: Data("TEXV".utf8)) else {
            return embeddedImage(in: data)
        }

        guard let texture = texture(from: data) else {
            return nil
        }

        if let imageData = declaredImageData(from: texture) {
            return imageData
        }
        if texture.isGIF,
           let gifData = makeAnimatedGIF(from: texture) {
            return TextureDecodeResult(data: gifData, fileExtension: "gif")
        }

        guard let mipmap = texture.images.first?.mipmaps.first,
              let rgba = rgbaBytes(from: mipmap, texFormat: texture.format)
        else {
            return nil
        }

        let cropWidth = min(texture.imageWidth, mipmap.width)
        let cropHeight = min(texture.imageHeight, mipmap.height)
        guard let pngData = makePNG(
            rgba: rgba,
            width: mipmap.width,
            height: mipmap.height,
            cropWidth: cropWidth,
            cropHeight: cropHeight
        ) else {
            return nil
        }

        return TextureDecodeResult(data: pngData, fileExtension: "png")
    }

    private static func declaredImageData(from texture: TexTexture) -> TextureDecodeResult? {
        guard let bytes = texture.images.first?.mipmaps.first?.bytes else {
            return nil
        }

        switch texture.imageFormat {
        case 2:
            return TextureDecodeResult(data: bytes, fileExtension: "jpg")
        case 13:
            return TextureDecodeResult(data: bytes, fileExtension: "png")
        case 25:
            return TextureDecodeResult(data: bytes, fileExtension: "gif")
        case 35:
            return TextureDecodeResult(data: bytes, fileExtension: "mp4")
        default:
            return nil
        }
    }

    private static func texture(from data: Data) -> TexTexture? {
        var reader = TexReader(data: data)
        return try? reader.read()
    }

    private static func embeddedImage(in data: Data) -> TextureDecodeResult? {
        let signatures: [(Data, Data, String)] = [
            (
                Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
                Data("IEND".utf8),
                "png"
            ),
            (
                Data([0xFF, 0xD8, 0xFF]),
                Data([0xFF, 0xD9]),
                "jpg"
            ),
            (
                Data("GIF8".utf8),
                Data([0x3B]),
                "gif"
            )
        ]

        for (startSignature, endSignature, fileExtension) in signatures {
            guard let startRange = data.range(of: startSignature) else {
                continue
            }

            let searchRange = startRange.upperBound..<data.endIndex
            guard let endRange = data.range(of: endSignature, options: [], in: searchRange) else {
                continue
            }

            let endIndex = min(data.endIndex, endRange.upperBound)
            return TextureDecodeResult(
                data: data.subdata(in: startRange.lowerBound..<endIndex),
                fileExtension: fileExtension
            )
        }

        return nil
    }

    private static func rgbaBytes(from mipmap: TexMipmap, texFormat: Int) -> Data? {
        let bytes: Data
        if mipmap.isLZ4Compressed {
            guard let decompressed = lz4Decode(mipmap.bytes, decodedSize: mipmap.decompressedByteCount) else {
                return nil
            }
            bytes = decompressed
        } else {
            bytes = mipmap.bytes
        }

        switch texFormat {
        case 0:
            guard bytes.count >= mipmap.width * mipmap.height * 4 else {
                return nil
            }
            return bytes
        case 4:
            return DXTDecoder.decompress(width: mipmap.width, height: mipmap.height, data: bytes, format: .dxt5)
        case 6:
            return DXTDecoder.decompress(width: mipmap.width, height: mipmap.height, data: bytes, format: .dxt3)
        case 7:
            return DXTDecoder.decompress(width: mipmap.width, height: mipmap.height, data: bytes, format: .dxt1)
        default:
            return nil
        }
    }

    private static func lz4Decode(_ data: Data, decodedSize: Int) -> Data? {
        guard decodedSize > 0 else {
            return nil
        }

        let source = [UInt8](data)
        var sourceIndex = 0
        var output = [UInt8]()
        output.reserveCapacity(decodedSize)

        while sourceIndex < source.count {
            let token = source[sourceIndex]
            sourceIndex += 1

            var literalLength = Int(token >> 4)
            if literalLength == 15 {
                while sourceIndex < source.count {
                    let next = Int(source[sourceIndex])
                    sourceIndex += 1
                    literalLength += next
                    if next != 255 {
                        break
                    }
                }
            }

            guard sourceIndex + literalLength <= source.count else {
                return nil
            }
            output.append(contentsOf: source[sourceIndex..<(sourceIndex + literalLength)])
            sourceIndex += literalLength

            if sourceIndex >= source.count {
                break
            }

            guard sourceIndex + 2 <= source.count else {
                return nil
            }
            let offset = Int(source[sourceIndex]) | (Int(source[sourceIndex + 1]) << 8)
            sourceIndex += 2
            guard offset > 0, offset <= output.count else {
                return nil
            }

            var matchLength = Int(token & 0x0F) + 4
            if (token & 0x0F) == 15 {
                while sourceIndex < source.count {
                    let next = Int(source[sourceIndex])
                    sourceIndex += 1
                    matchLength += next
                    if next != 255 {
                        break
                    }
                }
            }

            for _ in 0..<matchLength {
                output.append(output[output.count - offset])
                if output.count > decodedSize {
                    return nil
                }
            }
        }

        guard output.count == decodedSize else {
            return nil
        }
        return Data(output)
    }

    private static func makeAnimatedGIF(from texture: TexTexture) -> Data? {
        guard let frameInfo = texture.frameInfo,
              let firstImage = texture.images.first,
              let firstMipmap = firstImage.mipmaps.first,
              let atlas = rgbaBytes(from: firstMipmap, texFormat: texture.format)
        else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "com.compuserve.gif" as CFString,
            frameInfo.frames.count,
            nil
        ) else {
            return nil
        }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ] as CFDictionary)

        for frame in frameInfo.frames {
            guard let frameRGBA = cropFrame(
                atlas: atlas,
                atlasWidth: firstMipmap.width,
                atlasHeight: firstMipmap.height,
                frame: frame
            ),
                let image = makeCGImage(
                    rgba: frameRGBA,
                    width: frame.outputWidth,
                    height: frame.outputHeight
                )
            else {
                continue
            }

            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: max(0.02, frame.duration)
                ]
            ] as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination), output.length > 0 else {
            return nil
        }

        return output as Data
    }

    private static func cropFrame(
        atlas: Data,
        atlasWidth: Int,
        atlasHeight: Int,
        frame: TexFrame
    ) -> Data? {
        let x = max(0, min(Int(frame.x.rounded(.down)), atlasWidth - 1))
        let y = max(0, min(Int(frame.y.rounded(.down)), atlasHeight - 1))
        let width = min(frame.outputWidth, atlasWidth - x)
        let height = min(frame.outputHeight, atlasHeight - y)
        guard width > 0, height > 0 else {
            return nil
        }

        var output = Data(count: width * height * 4)
        output.withUnsafeMutableBytes { outputBuffer in
            atlas.withUnsafeBytes { atlasBuffer in
                guard let outputBase = outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let atlasBase = atlasBuffer.bindMemory(to: UInt8.self).baseAddress
                else {
                    return
                }

                for row in 0..<height {
                    let sourceOffset = ((y + row) * atlasWidth + x) * 4
                    let destinationOffset = row * width * 4
                    outputBase.advanced(by: destinationOffset)
                        .update(from: atlasBase.advanced(by: sourceOffset), count: width * 4)
                }
            }
        }

        if width == frame.outputWidth, height == frame.outputHeight {
            return output
        }

        return output
    }

    private static func makePNG(
        rgba: Data,
        width: Int,
        height: Int,
        cropWidth: Int,
        cropHeight: Int
    ) -> Data? {
        let cropped = croppedRGBA(rgba, width: width, height: height, cropWidth: cropWidth, cropHeight: cropHeight)
        guard let image = makeCGImage(rgba: cropped, width: cropWidth, height: cropHeight) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length > 0 else {
            return nil
        }
        return output as Data
    }

    private static func croppedRGBA(
        _ rgba: Data,
        width: Int,
        height: Int,
        cropWidth: Int,
        cropHeight: Int
    ) -> Data {
        guard cropWidth != width || cropHeight != height else {
            return rgba
        }

        let safeWidth = min(width, cropWidth)
        let safeHeight = min(height, cropHeight)
        var output = Data(count: safeWidth * safeHeight * 4)
        output.withUnsafeMutableBytes { outputBuffer in
            rgba.withUnsafeBytes { sourceBuffer in
                guard let outputBase = outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = sourceBuffer.bindMemory(to: UInt8.self).baseAddress
                else {
                    return
                }

                for row in 0..<safeHeight {
                    outputBase.advanced(by: row * safeWidth * 4)
                        .update(from: sourceBase.advanced(by: row * width * 4), count: safeWidth * 4)
                }
            }
        }
        return output
    }

    private static func makeCGImage(rgba: Data, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              rgba.count >= width * height * 4,
              let provider = CGDataProvider(data: rgba as CFData)
        else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

private struct TexTexture {
    let format: Int
    let imageFormat: Int
    let imageWidth: Int
    let imageHeight: Int
    let isGIF: Bool
    let images: [TexImage]
    let frameInfo: TexFrameInfo?
}

private struct TexImage {
    let mipmaps: [TexMipmap]
}

private struct TexMipmap {
    let width: Int
    let height: Int
    let isLZ4Compressed: Bool
    let decompressedByteCount: Int
    let bytes: Data
}

private struct TexFrameInfo {
    let width: Int
    let height: Int
    let frames: [TexFrame]
}

private struct TexFrame {
    let imageID: Int
    let duration: Double
    let x: Double
    let y: Double
    let width: Double
    let widthY: Double
    let heightX: Double
    let height: Double

    var outputWidth: Int {
        max(1, Int(abs(width != 0 ? width : heightX).rounded()))
    }

    var outputHeight: Int {
        max(1, Int(abs(height != 0 ? height : widthY).rounded()))
    }
}

private struct TexReader {
    private let data: Data
    private var cursor = 0

    init(data: Data) {
        self.data = data
    }

    mutating func read() throws -> TexTexture {
        guard try readCString(maxLength: 16) == "TEXV0005",
              try readCString(maxLength: 16) == "TEXI0001"
        else {
            throw TexReaderError.invalidMagic
        }

        let format = try readInt32()
        let flags = try readInt32()
        _ = try readInt32()
        _ = try readInt32()
        let imageWidth = try readInt32()
        let imageHeight = try readInt32()
        _ = try readUInt32()

        let containerMagic = try readCString(maxLength: 16)
        let imageCount = try readInt32()
        var imageFormat = -1
        var isMP4 = false

        if containerMagic == "TEXB0003" {
            imageFormat = try readInt32()
        } else if containerMagic == "TEXB0004" {
            imageFormat = try readInt32()
            isMP4 = try readInt32() == 1
            if imageFormat == -1, isMP4 {
                imageFormat = 35
            }
        } else if containerMagic != "TEXB0001", containerMagic != "TEXB0002" {
            throw TexReaderError.invalidMagic
        }

        var containerVersion = Int(containerMagic.dropFirst(4)) ?? 1
        if containerVersion == 4, imageFormat != 35 {
            containerVersion = 3
        }

        var images: [TexImage] = []
        for _ in 0..<imageCount {
            let mipmapCount = try readInt32()
            var mipmaps: [TexMipmap] = []

            for _ in 0..<mipmapCount {
                let mipmap: TexMipmap
                switch containerVersion {
                case 1:
                    let width = try readInt32()
                    let height = try readInt32()
                    mipmap = TexMipmap(
                        width: width,
                        height: height,
                        isLZ4Compressed: false,
                        decompressedByteCount: 0,
                        bytes: try readSizedData()
                    )
                case 2, 3:
                    let width = try readInt32()
                    let height = try readInt32()
                    let isLZ4Compressed = try readInt32() == 1
                    let decompressedByteCount = try readInt32()
                    mipmap = TexMipmap(
                        width: width,
                        height: height,
                        isLZ4Compressed: isLZ4Compressed,
                        decompressedByteCount: decompressedByteCount,
                        bytes: try readSizedData()
                    )
                case 4:
                    guard try readInt32() == 1, try readInt32() == 2 else {
                        throw TexReaderError.unsupported
                    }
                    _ = try readCString(maxLength: 4096)
                    guard try readInt32() == 1 else {
                        throw TexReaderError.unsupported
                    }
                    let width = try readInt32()
                    let height = try readInt32()
                    let isLZ4Compressed = try readInt32() == 1
                    let decompressedByteCount = try readInt32()
                    mipmap = TexMipmap(
                        width: width,
                        height: height,
                        isLZ4Compressed: isLZ4Compressed,
                        decompressedByteCount: decompressedByteCount,
                        bytes: try readSizedData()
                    )
                default:
                    throw TexReaderError.unsupported
                }
                mipmaps.append(mipmap)
            }

            images.append(TexImage(mipmaps: mipmaps))
        }

        let frameInfo = (flags & 1) == 1 ? try readFrameInfo() : nil

        return TexTexture(
            format: format,
            imageFormat: imageFormat,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            isGIF: frameInfo != nil,
            images: images,
            frameInfo: frameInfo
        )
    }

    private mutating func readFrameInfo() throws -> TexFrameInfo {
        let magic = try readCString(maxLength: 16)
        let frameCount = try readInt32()
        var gifWidth = 0
        var gifHeight = 0

        if magic == "TEXS0003" {
            gifWidth = try readInt32()
            gifHeight = try readInt32()
        } else if magic != "TEXS0001", magic != "TEXS0002" {
            throw TexReaderError.invalidMagic
        }

        var frames: [TexFrame] = []
        for _ in 0..<frameCount {
            let imageID = try readInt32()
            let duration = Double(try readFloat32())
            let x: Double
            let y: Double
            let width: Double
            let widthY: Double
            let heightX: Double
            let height: Double

            if magic == "TEXS0001" {
                x = Double(try readInt32())
                y = Double(try readInt32())
                width = Double(try readInt32())
                widthY = Double(try readInt32())
                heightX = Double(try readInt32())
                height = Double(try readInt32())
            } else {
                x = Double(try readFloat32())
                y = Double(try readFloat32())
                width = Double(try readFloat32())
                widthY = Double(try readFloat32())
                heightX = Double(try readFloat32())
                height = Double(try readFloat32())
            }

            frames.append(TexFrame(
                imageID: imageID,
                duration: duration,
                x: x,
                y: y,
                width: width,
                widthY: widthY,
                heightX: heightX,
                height: height
            ))
        }

        if gifWidth == 0 || gifHeight == 0, let first = frames.first {
            gifWidth = first.outputWidth
            gifHeight = first.outputHeight
        }

        return TexFrameInfo(width: gifWidth, height: gifHeight, frames: frames)
    }

    private mutating func readSizedData() throws -> Data {
        let count = try readInt32()
        guard count >= 0, cursor + count <= data.count else {
            throw TexReaderError.truncated
        }
        defer {
            cursor += count
        }
        return data.subdata(in: cursor..<(cursor + count))
    }

    private mutating func readCString(maxLength: Int) throws -> String {
        let start = cursor
        var length = 0
        while cursor < data.count, data[cursor] != 0, length < maxLength {
            cursor += 1
            length += 1
        }
        guard cursor < data.count else {
            throw TexReaderError.truncated
        }

        let stringData = data.subdata(in: start..<cursor)
        cursor += 1
        return String(data: stringData, encoding: .utf8) ?? ""
    }

    private mutating func readInt32() throws -> Int {
        Int(Int32(bitPattern: try readUInt32()))
    }

    private mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }

    private mutating func readFloat32() throws -> Float {
        Float(bitPattern: try readUInt32())
    }

    private mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0, cursor + count <= data.count else {
            throw TexReaderError.truncated
        }
        defer {
            cursor += count
        }
        return Array(data[cursor..<(cursor + count)])
    }
}

private enum TexReaderError: Error {
    case invalidMagic
    case truncated
    case unsupported
}

private enum DXTFormat {
    case dxt1
    case dxt3
    case dxt5
}

private enum DXTDecoder {
    static func decompress(width: Int, height: Int, data: Data, format: DXTFormat) -> Data? {
        guard width > 0, height > 0 else {
            return nil
        }

        let bytesPerBlock = format == .dxt1 ? 8 : 16
        let blockWidth = (width + 3) / 4
        let blockHeight = (height + 3) / 4
        guard data.count >= blockWidth * blockHeight * bytesPerBlock else {
            return nil
        }

        var output = Data(count: width * height * 4)
        output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { dataBuffer in
                guard let outputBase = outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let dataBase = dataBuffer.bindMemory(to: UInt8.self).baseAddress
                else {
                    return
                }

                var blockOffset = 0
                for blockY in 0..<blockHeight {
                    for blockX in 0..<blockWidth {
                        let rgba = decompressBlock(dataBase.advanced(by: blockOffset), format: format)
                        defer {
                            rgba.deallocate()
                        }
                        for y in 0..<4 {
                            for x in 0..<4 {
                                let pixelX = blockX * 4 + x
                                let pixelY = blockY * 4 + y
                                guard pixelX < width, pixelY < height else {
                                    continue
                                }

                                let sourceOffset = (y * 4 + x) * 4
                                let destinationOffset = (pixelY * width + pixelX) * 4
                                outputBase.advanced(by: destinationOffset)
                                    .update(from: rgba.advanced(by: sourceOffset), count: 4)
                            }
                        }
                        blockOffset += bytesPerBlock
                    }
                }
            }
        }

        return output
    }

    private static func decompressBlock(_ block: UnsafePointer<UInt8>, format: DXTFormat) -> UnsafeMutablePointer<UInt8> {
        let rgba = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        rgba.initialize(repeating: 0, count: 64)

        let colorOffset = format == .dxt1 ? 0 : 8
        decompressColor(rgba, block.advanced(by: colorOffset), isDXT1: format == .dxt1)

        switch format {
        case .dxt1:
            break
        case .dxt3:
            decompressAlphaDXT3(rgba, block)
        case .dxt5:
            decompressAlphaDXT5(rgba, block)
        }

        return rgba
    }

    private static func decompressAlphaDXT3(_ rgba: UnsafeMutablePointer<UInt8>, _ block: UnsafePointer<UInt8>) {
        for index in 0..<8 {
            let value = block[index]
            let low = value & 0x0F
            let high = value & 0xF0
            rgba[8 * index + 3] = low | (low << 4)
            rgba[8 * index + 7] = high | (high >> 4)
        }
    }

    private static func decompressAlphaDXT5(_ rgba: UnsafeMutablePointer<UInt8>, _ block: UnsafePointer<UInt8>) {
        let alpha0 = block[0]
        let alpha1 = block[1]
        var codes = [UInt8](repeating: 0, count: 8)
        codes[0] = alpha0
        codes[1] = alpha1

        if alpha0 <= alpha1 {
            for index in 1..<5 {
                codes[index + 1] = UInt8(((5 - index) * Int(alpha0) + index * Int(alpha1)) / 5)
            }
            codes[6] = 0
            codes[7] = 255
        } else {
            for index in 1..<7 {
                codes[index + 1] = UInt8(((7 - index) * Int(alpha0) + index * Int(alpha1)) / 7)
            }
        }

        var indices = [UInt8](repeating: 0, count: 16)
        var sourceOffset = 2
        var indexOffset = 0
        for _ in 0..<2 {
            var value = 0
            for byteIndex in 0..<3 {
                value |= Int(block[sourceOffset]) << (8 * byteIndex)
                sourceOffset += 1
            }
            for bitIndex in 0..<8 {
                indices[indexOffset] = UInt8((value >> (3 * bitIndex)) & 0x07)
                indexOffset += 1
            }
        }

        for index in 0..<16 {
            rgba[4 * index + 3] = codes[Int(indices[index])]
        }
    }

    private static func decompressColor(_ rgba: UnsafeMutablePointer<UInt8>, _ block: UnsafePointer<UInt8>, isDXT1: Bool) {
        var codes = [UInt8](repeating: 0, count: 16)
        let colorA = unpack565(block, offset: 0, output: &codes, outputOffset: 0)
        let colorB = unpack565(block, offset: 2, output: &codes, outputOffset: 4)

        for index in 0..<3 {
            let a = Int(codes[index])
            let b = Int(codes[4 + index])
            if isDXT1, colorA <= colorB {
                codes[8 + index] = UInt8((a + b) / 2)
                codes[12 + index] = 0
            } else {
                codes[8 + index] = UInt8((2 * a + b) / 3)
                codes[12 + index] = UInt8((a + 2 * b) / 3)
            }
        }
        codes[8 + 3] = 255
        codes[12 + 3] = (isDXT1 && colorA <= colorB) ? 0 : 255

        var indices = [UInt8](repeating: 0, count: 16)
        for row in 0..<4 {
            let packed = block[4 + row]
            indices[row * 4] = packed & 0x03
            indices[row * 4 + 1] = (packed >> 2) & 0x03
            indices[row * 4 + 2] = (packed >> 4) & 0x03
            indices[row * 4 + 3] = (packed >> 6) & 0x03
        }

        for index in 0..<16 {
            let sourceOffset = Int(indices[index]) * 4
            let destinationOffset = index * 4
            rgba[destinationOffset] = codes[sourceOffset]
            rgba[destinationOffset + 1] = codes[sourceOffset + 1]
            rgba[destinationOffset + 2] = codes[sourceOffset + 2]
            rgba[destinationOffset + 3] = codes[sourceOffset + 3]
        }
    }

    private static func unpack565(
        _ block: UnsafePointer<UInt8>,
        offset: Int,
        output: inout [UInt8],
        outputOffset: Int
    ) -> Int {
        let value = Int(block[offset]) | (Int(block[offset + 1]) << 8)
        let red = UInt8((value >> 11) & 0x1F)
        let green = UInt8((value >> 5) & 0x3F)
        let blue = UInt8(value & 0x1F)

        output[outputOffset] = (red << 3) | (red >> 2)
        output[outputOffset + 1] = (green << 2) | (green >> 4)
        output[outputOffset + 2] = (blue << 3) | (blue >> 2)
        output[outputOffset + 3] = 255

        return value
    }
}
