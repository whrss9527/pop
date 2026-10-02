import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 图片转换：换格式、缩小尺寸、压缩体积、去掉照片里的位置和拍摄信息。结果存在原图旁边，不覆盖原图。
enum ImageConverter {
    enum Operation: String, CaseIterable, Identifiable {
        case png
        case jpeg
        case heic
        case halfSize
        case compress
        case rotateLeft
        case rotateRight
        case flipHorizontal
        case removeLocation
        case removeMetadata

        var id: String { rawValue }

        var title: String {
            switch self {
            case .png: return String(localized: "转成 PNG")
            case .jpeg: return String(localized: "转成 JPEG")
            case .heic: return String(localized: "转成 HEIC")
            case .halfSize: return String(localized: "缩小一半")
            case .compress: return String(localized: "压缩")
            case .rotateLeft: return String(localized: "向左转")
            case .rotateRight: return String(localized: "向右转")
            case .flipHorizontal: return String(localized: "左右翻转")
            case .removeLocation: return String(localized: "去掉位置信息")
            case .removeMetadata: return String(localized: "去掉拍摄信息")
            }
        }
    }

    struct Failure: Error, Equatable {
        let message: String
    }

    /// 存结果的文件建不出来（CGImageDestinationCreateWithURL 返回 nil）时告诉用户为什么：系统确实不支持这种格式时说不支持，
    /// 否则多半是没有权限在那个文件夹里存文件（App Store 版只能写允许过的文件夹，见 FolderAccess）
    static func cannotCreateMessage(_ output: URL, type: UTType) -> String {
        let supported = (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(type.identifier)
        guard supported else {
            return String(localized: "这台 Mac 不支持存成 \(type.preferredFilenameExtension?.uppercased() ?? String(localized: "这种格式"))")
        }
        let folder = output.deletingLastPathComponent().lastPathComponent
        if Distribution.isAppStore {
            return String(localized: "没有权限在「\(folder)」里存文件：在「设置 → 通用 → 文件夹访问」里允许 Pop 访问这个文件夹")
        }
        return String(localized: "没有权限在「\(folder)」里存文件")
    }

    /// 转换一张图片，返回新文件的位置
    static func convert(_ url: URL, _ operation: Operation) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」"))
        }
        if operation == .removeLocation || operation == .removeMetadata {
            return try removingMetadata(url, source: source, operation: operation)
        }
        let sourceType = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) } ?? .png
        let type: UTType
        var properties: [CFString: Any] = [:]
        let image: CGImage?
        switch operation {
        case .png:
            type = .png
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        case .jpeg:
            type = .jpeg
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        case .heic:
            type = .heic
            properties[kCGImageDestinationLossyCompressionQuality] = 0.8
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        case .halfSize:
            type = sourceType
            image = halfSizeImage(source)
        case .compress:
            type = .jpeg
            properties[kCGImageDestinationLossyCompressionQuality] = 0.7
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        case .rotateLeft, .rotateRight, .flipHorizontal:
            type = sourceType
            properties[kCGImageDestinationLossyCompressionQuality] = 0.95
            image = uprightImage(source).flatMap { transformed($0, operation) }
        case .removeLocation, .removeMetadata:
            return url
        }
        guard let image else { throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」")) }
        let output = outputURL(for: url, operation: operation, type: type)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: cannotCreateMessage(output, type: type))
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: String(localized: "存储「\(output.lastPathComponent)」失败"))
        }
        return output
    }

    /// 缩小一半：按原图方向摆正后，长边缩到原来的一半
    private static func halfSizeImage(_ source: CGImageSource) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(max(width, height) / 2, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 另存一份去掉位置（或者全部拍摄信息）的照片：尽量原样拷贝画面数据不重新压缩，照片的方向保留；
    /// 存好后再读一遍，确认真的去掉了
    private static func removingMetadata(_ url: URL, source: CGImageSource, operation: Operation) throws -> URL {
        let removeAll = operation == .removeMetadata
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let sourceIdentifier = (CGImageSourceGetType(source) as String?) ?? UTType.jpeg.identifier
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(sourceIdentifier)
        // RAW 这类存不回原格式的，存成 JPEG
        let type = writable ? (UTType(sourceIdentifier) ?? .jpeg) : .jpeg
        let output = outputURL(for: url, operation: operation, type: type)

        // 只去掉位置时，相机、参数、拍摄时间都要原样留着
        var kept = PhotoMetadata(properties: properties)
        kept.latitude = nil
        kept.longitude = nil
        kept.altitude = nil
        func cleaned(keepingTheRest: Bool) -> Bool {
            guard let metadata = PhotoMetadata.read(output) else { return false }
            if removeAll { return metadata.isEmpty }
            return keepingTheRest ? metadata == kept : !metadata.hasLocation
        }

        // JPEG 去掉全部信息：直接删掉存信息的那几段，画面数据一个字节都不动
        if removeAll, type == .jpeg, let data = try? Data(contentsOf: url),
           let stripped = JPEGMetadata.stripped(data, orientation: properties[kCGImagePropertyOrientation] as? Int ?? 1) {
            if (try? stripped.write(to: output, options: .withoutOverwriting)) != nil, cleaned(keepingTheRest: true) {
                return output
            }
            try? FileManager.default.removeItem(at: output)
        }

        // 原样拷贝画面数据，只改元数据
        var attempts: [[CFString: Any]] = []
        if removeAll {
            // 换成空的元数据，只把方向带上
            var options: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true,
                                            kCGImageDestinationMetadata: CGImageMetadataCreateMutable(),
                                            kCGImageDestinationMergeMetadata: false]
            if let orientation = properties[kCGImagePropertyOrientation] {
                options[kCGImageDestinationOrientation] = orientation
            }
            attempts.append(options)
        } else {
            // 不给元数据时原来的会被整个换掉：合并一份空的，或者原样再给一遍，都只是不写位置
            attempts.append([kCGImageMetadataShouldExcludeGPS: true,
                             kCGImageDestinationMetadata: CGImageMetadataCreateMutable(),
                             kCGImageDestinationMergeMetadata: true])
            if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
                attempts.append([kCGImageMetadataShouldExcludeGPS: true,
                                 kCGImageDestinationMetadata: metadata,
                                 kCGImageDestinationMergeMetadata: false])
            }
        }
        for options in attempts where writable {
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else { break }
            if CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil), cleaned(keepingTheRest: true) {
                return output
            }
            try? FileManager.default.removeItem(at: output)
        }

        // 这种格式不能原样拷贝：重新存一份
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: cannotCreateMessage(output, type: type))
        }
        if removeAll {
            // 画面按方向摆正后重新画一份，不带任何拍摄信息
            guard let image = uprightImage(source) else { throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」")) }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        } else {
            let changes: [CFString: Any] = [kCGImagePropertyGPSDictionary: kCFNull as Any,
                                            kCGImageMetadataShouldExcludeGPS: true,
                                            kCGImageDestinationLossyCompressionQuality: 0.95]
            CGImageDestinationAddImageFromSource(destination, source, 0, changes as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination), cleaned(keepingTheRest: false) else {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: removeAll ? String(localized: "没能去掉「\(url.lastPathComponent)」的拍摄信息") : String(localized: "没能去掉「\(url.lastPathComponent)」的位置信息"))
        }
        return output
    }

    /// 按原图方向（照片的 EXIF 方向）摆正后的原尺寸图片
    static func uprightImage(_ source: CGImageSource) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 转 90° 或者左右翻转
    static func transformed(_ image: CGImage, _ operation: Operation) -> CGImage? {
        let width = image.width
        let height = image.height
        let turns = operation == .rotateLeft || operation == .rotateRight
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: turns ? height : width, height: turns ? width : height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        switch operation {
        case .rotateRight:
            // 顺时针：原来的左边转到上面
            context.translateBy(x: 0, y: CGFloat(width))
            context.rotate(by: -.pi / 2)
        case .rotateLeft:
            context.translateBy(x: CGFloat(height), y: 0)
            context.rotate(by: .pi / 2)
        case .flipHorizontal:
            context.translateBy(x: CGFloat(width), y: 0)
            context.scaleBy(x: -1, y: 1)
        default:
            break
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// 新文件名：「原名.png」；和原图同名同格式时加上说明（「原名 缩小.jpg」），已经有同名文件时再加编号
    static func outputURL(for url: URL, operation: Operation, type: UTType) -> URL {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        // JPEG 习惯用 .jpg
        let ext = type == .jpeg ? "jpg" : (type.preferredFilenameExtension ?? url.pathExtension)
        var name = base
        switch operation {
        case .halfSize: name += String(localized: " 缩小")
        case .compress: name += String(localized: " 压缩")
        case .rotateLeft: name += String(localized: " 向左转")
        case .rotateRight: name += String(localized: " 向右转")
        case .flipHorizontal: name += String(localized: " 翻转")
        case .removeLocation: name += String(localized: " 无位置")
        case .removeMetadata: name += String(localized: " 无拍摄信息")
        case .png, .jpeg, .heic: break
        }
        var candidate = folder.appending(path: "\(name).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folder.appending(path: "\(name) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}

/// 直接改 JPEG 文件里的段：去掉 EXIF、XMP、IPTC、注释和厂商自己的信息段，只留解码要用的（JFIF、颜色描述文件、Adobe）；
/// 照片的方向写回一个只有方向的 EXIF 段。画面数据原样拷贝，主图后面附带的图片（MPF）一起去掉。
enum JPEGMetadata {
    static func stripped(_ data: Data, orientation: Int) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var output: [UInt8] = [0xFF, 0xD8]
        var wroteOrientation = orientation == 1
        var index = 2
        while index + 3 < bytes.count {
            guard bytes[index] == 0xFF else { return nil }
            let marker = bytes[index + 1]
            if marker == 0xFF {
                // 填充字节
                index += 1
                continue
            }
            // 方向段放在 JFIF 段后面（没有 JFIF 就紧跟文件开头）
            if marker != 0xE0, !wroteOrientation {
                output += orientationSegment(orientation)
                wroteOrientation = true
            }
            if marker == 0xDA {
                guard let end = endOfImage(bytes, from: index) else { return nil }
                output += bytes[index..<end]
                return Data(output)
            }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 2, index + 2 + length <= bytes.count else { return nil }
            let segment = bytes[index..<(index + 2 + length)]
            if keeps(marker, segment) {
                output += segment
            }
            index += 2 + length
        }
        return nil
    }

    /// JFIF、颜色描述文件（ICC）、Adobe 段和所有非 APP 段（量化表、霍夫曼表、帧信息……）留着
    private static func keeps(_ marker: UInt8, _ segment: ArraySlice<UInt8>) -> Bool {
        switch marker {
        case 0xE0, 0xEE:
            return true
        case 0xE2:
            let signature = Array("ICC_PROFILE".utf8)
            let start = segment.startIndex + 4
            return segment.count >= 4 + signature.count && Array(segment[start..<(start + signature.count)]) == signature
        case 0xE1, 0xE3...0xED, 0xEF, 0xFE:
            return false
        default:
            return true
        }
    }

    /// 从第一段画面数据开始找到主图的结尾（EOI 之后）
    private static func endOfImage(_ bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        while index + 1 < bytes.count {
            guard bytes[index] == 0xFF else { return nil }
            let marker = bytes[index + 1]
            if marker == 0xD9 {
                return index + 2
            }
            if marker == 0xFF {
                index += 1
                continue
            }
            if (0xD0...0xD7).contains(marker) || marker == 0x01 {
                index += 2
                continue
            }
            guard index + 3 < bytes.count else { return nil }
            index += 2 + (Int(bytes[index + 2]) << 8 | Int(bytes[index + 3]))
            if marker == 0xDA {
                // 画面数据里的 FF 后面只会跟 00 或者 RST，遇到别的就是下一个标记
                while index + 1 < bytes.count,
                      !(bytes[index] == 0xFF && bytes[index + 1] != 0x00 && !(0xD0...0xD7).contains(bytes[index + 1])) {
                    index += 1
                }
            }
        }
        return nil
    }

    /// 只有一项「方向」的 EXIF 段（大端 TIFF）
    static func orientationSegment(_ orientation: Int) -> [UInt8] {
        var payload: [UInt8] = Array("Exif".utf8)
        payload += [0x00, 0x00]
        // TIFF 头：大端，第一个目录在第 8 个字节
        payload += [0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08]
        // 一项：0x0112 方向，SHORT，1 个值
        payload += [0x00, 0x01]
        payload += [0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01]
        payload += [0x00, UInt8(clamping: orientation), 0x00, 0x00]
        // 没有下一个目录
        payload += [0x00, 0x00, 0x00, 0x00]
        let length = payload.count + 2
        var segment: [UInt8] = [0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 0xFF)]
        segment += payload
        return segment
    }
}
