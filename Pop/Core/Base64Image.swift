import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Base64 写的图片：data:image/png;base64,… 或者一长串 Base64 解出来是图片；也能把图片文件写成 data URI。
enum Base64Image {
    struct Decoded: Equatable {
        var data: Data
        var type: UTType
        var width: Int
        var height: Int
    }

    /// 图片文件超过这么大就不生成 data URI（太长了没法用）
    static let dataURILimit = 2_000_000

    /// 去掉 data: 开头和空白，URL 安全的写法换回标准写法、补齐 =；不像 Base64 时返回 nil
    static func payload(_ text: String) -> String? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.lowercased().hasPrefix("data:") {
            guard let comma = body.firstIndex(of: ","), body[..<comma].lowercased().hasSuffix(";base64") else { return nil }
            body = String(body[body.index(after: comma)...])
        }
        body = body.filter { !$0.isWhitespace }
        guard body.count >= 24,
              body.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=-_".contains($0)) }) else { return nil }
        body = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = body.count % 4
        if remainder > 0 {
            body += String(repeating: "=", count: 4 - remainder)
        }
        return body
    }

    /// 只解开头一小段，看文件头是不是图片（圆盘里判断要不要显示这个功能，要快）
    static func looksLikeImage(_ text: String) -> Bool {
        guard text.count >= 24, let body = payload(String(text.prefix(4096))) else { return false }
        let head = String(body.prefix(64))
        guard let data = Data(base64Encoded: head, options: .ignoreUnknownCharacters) else { return false }
        return imageType(ofHeader: [UInt8](data)) != nil
    }

    /// 按文件头认图片格式
    static func imageType(ofHeader bytes: [UInt8]) -> UTType? {
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + prefix.count && Array(bytes[offset..<(offset + prefix.count)]) == prefix
        }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return .png }
        if starts([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if starts(Array("GIF8".utf8)) { return .gif }
        if starts(Array("RIFF".utf8)), starts(Array("WEBP".utf8), at: 8) { return .webP }
        if starts(Array("BM".utf8)) { return .bmp }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        if starts([0x00, 0x00, 0x01, 0x00]) { return .ico }
        if starts(Array("ftyp".utf8), at: 4) {
            let brand = bytes.count >= 12 ? String(decoding: bytes[8..<12], as: UTF8.self) : ""
            if ["heic", "heix", "hevc", "mif1", "msf1"].contains(brand) { return .heic }
            if brand == "avif" { return UTType("public.avif") ?? .image }
        }
        return nil
    }

    /// 解出图片，并读出格式和尺寸
    static func decode(_ text: String) -> Decoded? {
        guard let body = payload(text), let data = Data(base64Encoded: body, options: .ignoreUnknownCharacters),
              imageType(ofHeader: [UInt8](data.prefix(16))) != nil,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source) as String?, let type = UTType(identifier),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return Decoded(data: data, type: type, width: width, height: height)
    }

    /// 图片文件写成 data URI；太大或者读不了时返回 nil
    static func dataURI(for file: URL, limit: Int = dataURILimit) -> String? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit,
              let data = try? Data(contentsOf: file) else { return nil }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType
            ?? imageType(ofHeader: [UInt8](data.prefix(16)))?.preferredMIMEType
            ?? "application/octet-stream"
        return "data:\(mime);base64," + data.base64EncodedString()
    }

    /// PNG 图片（卡片里显示、复制、贴到屏幕用）
    static func png(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
