import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// 隐私打码：找出照片和截图里的人脸，以及手机号、邮箱、身份证号、银行卡号、车牌这些个人信息，打上马赛克另存一份。
/// 在本机识别；另存的那份只有像素，不带拍摄信息和位置。
enum Redaction {
    struct Failure: LocalizedError, Equatable {
        let message: String

        var errorDescription: String? { message }
    }

    /// 要打码的东西
    enum Target: String, CaseIterable, Hashable {
        case faces
        /// 电话号码、邮箱、身份证号和银行卡号、车牌
        case personalInfo
        /// 认出来的所有文字
        case allText
    }

    /// 找到的一处：在图片里的位置（像素，左上角为原点）和它是什么
    struct Region: Equatable {
        enum Kind: CaseIterable, Equatable {
            case face
            case phone
            case email
            case idNumber
            case plate
            case text
        }

        var rect: CGRect
        var kind: Kind
    }

    static let defaultTargets: Set<Target> = [.faces, .personalInfo]

    // MARK: - 个人信息

    /// 15 到 19 位的数字（中间可以有空格或短横线），最后一位可以是 X：再用证件号和银行卡号的校验筛一遍
    private static let numberCandidate = try! NSRegularExpression(pattern: #"(?<![0-9A-Za-z])(?:\d[ -]?){14,18}[\dXx](?![0-9A-Za-z])"#)
    private static let plate = try! NSRegularExpression(
        pattern: #"[京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼][A-HJ-NP-Z][·•. ]?[A-HJ-NP-Z0-9]{4,5}[A-HJ-NP-Z0-9挂学警港澳]"#)

    /// 一行文字里的个人信息在哪里：校验通过的身份证号和银行卡号、电话号码、邮箱、车牌
    static func sensitiveRanges(in text: String) -> [(range: Range<String.Index>, kind: Region.Kind)] {
        var found: [(range: Range<String.Index>, kind: Region.Kind)] = []
        func add(_ range: Range<String.Index>, _ kind: Region.Kind) {
            guard !found.contains(where: { $0.range.overlaps(range) }) else { return }
            found.append((range, kind))
        }
        let full = NSRange(text.startIndex..., in: text)
        for match in numberCandidate.matches(in: text, range: full) {
            guard let range = Range(match.range, in: text) else { continue }
            let digits = String(text[range].filter { $0.isNumber || $0 == "X" || $0 == "x" })
            // 校验不通过的（订单号之类）不算
            if let info = IDNumber.parse(digits), info.isValid {
                add(range, .idNumber)
            }
        }
        for item in InfoExtractor.extract(text) where item.kind == .phone || item.kind == .email {
            var start = text.startIndex
            while let range = text.range(of: item.value, range: start..<text.endIndex) {
                add(range, item.kind == .phone ? .phone : .email)
                start = range.upperBound
            }
        }
        for match in plate.matches(in: text, range: full) {
            if let range = Range(match.range, in: text) {
                add(range, .plate)
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    // MARK: - 找位置

    /// 在图片里找要打码的地方
    static func find(in image: CGImage, targets: Set<Target>) throws -> [Region] {
        let size = CGSize(width: image.width, height: image.height)
        let faceRequest = VNDetectFaceRectanglesRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        // 号码不要被「纠正」成别的字
        textRequest.usesLanguageCorrection = false
        textRequest.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        var requests: [VNRequest] = []
        if targets.contains(.faces) {
            requests.append(faceRequest)
        }
        if targets.contains(.personalInfo) || targets.contains(.allText) {
            requests.append(textRequest)
        }
        guard !requests.isEmpty else { return [] }
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform(requests)
        } catch {
            throw Failure(message: String(localized: "识别失败：\(error.localizedDescription)"))
        }

        var regions: [Region] = []
        if targets.contains(.faces) {
            for face in faceRequest.results ?? [] {
                // 往外扩一圈，把头发和下巴也盖住
                let rect = pixelRect(face.boundingBox, in: size)
                regions.append(Region(rect: rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.2), kind: .face))
            }
        }
        if targets.contains(.personalInfo) || targets.contains(.allText) {
            for observation in textRequest.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                if targets.contains(.allText) {
                    regions.append(Region(rect: pixelRect(observation.boundingBox, in: size).insetBy(dx: -2, dy: -2), kind: .text))
                    continue
                }
                for (range, kind) in sensitiveRanges(in: candidate.string) {
                    let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                    regions.append(Region(rect: pixelRect(box, in: size).insetBy(dx: -3, dy: -3), kind: kind))
                }
            }
        }
        let bounds = CGRect(origin: .zero, size: size)
        return regions.compactMap { region in
            let rect = region.rect.integral.intersection(bounds)
            return rect.width >= 2 && rect.height >= 2 ? Region(rect: rect, kind: region.kind) : nil
        }
    }

    /// Vision 的归一化坐标（左下角为原点）换成像素坐标（左上角为原点）
    static func pixelRect(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: normalized.minX * size.width, y: (1 - normalized.maxY) * size.height,
               width: normalized.width * size.width, height: normalized.height * size.height)
    }

    // MARK: - 打码

    /// 每一处按自己的大小分成格子，格子里是这块的平均色：人脸分成 6 格左右，文字的格子比字高的一半还大，认不出来
    static func pixelate(_ image: CGImage, regions: [Region]) -> CGImage? {
        let width = image.width
        let height = image.height
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: bitmapInfo) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: bounds)
        for region in regions {
            let rect = region.rect.integral.intersection(bounds)
            guard rect.width >= 2, rect.height >= 2, let piece = image.cropping(to: rect) else { continue }
            let block = max(8, min(rect.width, rect.height) / (region.kind == .face ? 6 : 2.5))
            let columns = max(1, Int((rect.width / block).rounded()))
            let rows = max(1, Int((rect.height / block).rounded()))
            guard let small = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: space, bitmapInfo: bitmapInfo) else { continue }
            small.interpolationQuality = .high
            small.draw(piece, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            guard let tiles = small.makeImage() else { continue }
            context.interpolationQuality = .none
            // CGContext 的原点在左下角
            context.draw(tiles, in: CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
        }
        return context.makeImage()
    }

    // MARK: - 文件

    /// 读图片（按拍摄方向转正）
    static func image(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let image = ImageConverter.uprightImage(source) else {
            throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」"))
        }
        return image
    }

    /// 打好码另存一份「原名 打码.jpg」（照片存成 JPEG，其余存成 PNG），原图不动
    static func redact(_ url: URL, targets: Set<Target>) throws -> (output: URL, regions: [Region]) {
        let original = try image(at: url)
        let regions = try find(in: original, targets: targets)
        guard !regions.isEmpty else {
            throw Failure(message: String(localized: "「\(url.lastPathComponent)」里没找到要打码的地方"))
        }
        guard let result = pixelate(original, regions: regions) else {
            throw Failure(message: String(localized: "「\(url.lastPathComponent)」打码失败"))
        }
        let sourceType = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceGetType($0) as String? }.flatMap { UTType($0) } ?? .png
        let photo = sourceType.conforms(to: .jpeg) || sourceType.conforms(to: .heic) || sourceType.conforms(to: .heif)
        let type: UTType = photo ? .jpeg : .png
        let output = FileNames.available(in: url.deletingLastPathComponent(),
                                         base: url.deletingPathExtension().lastPathComponent + String(localized: " 打码"),
                                         extension: photo ? "jpg" : "png")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: String(localized: "存储「\(output.lastPathComponent)」失败"))
        }
        // 只写像素：不带原图的拍摄信息和位置
        CGImageDestinationAddImage(destination, result, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: String(localized: "存储「\(output.lastPathComponent)」失败"))
        }
        return (output, regions)
    }

    /// 卡片上的预览：打好码后缩到最长 900 像素的 PNG，和找到的地方
    struct Preview {
        let png: Data
        let regions: [Region]
    }

    static func preview(_ url: URL, targets: Set<Target>) throws -> Preview {
        let original = try image(at: url)
        let regions = try find(in: original, targets: targets)
        guard let result = regions.isEmpty ? original : pixelate(original, regions: regions),
              let png = pngData(result, maxSide: 900) else {
            throw Failure(message: String(localized: "「\(url.lastPathComponent)」打码失败"))
        }
        return Preview(png: png, regions: regions)
    }

    /// 缩到最长 maxSide 像素，存成 PNG
    private static func pngData(_ image: CGImage, maxSide: CGFloat) -> Data? {
        let scale = min(1, maxSide / CGFloat(max(image.width, image.height, 1)))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, scaled, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// 「人脸 1 处、电话号码 2 处」
    static func summary(_ regions: [Region]) -> String {
        let names: [(Region.Kind, String)] = [
            (.face, String(localized: "人脸")), (.phone, String(localized: "电话号码")), (.email, String(localized: "邮箱")),
            (.idNumber, String(localized: "证件号和银行卡号")), (.plate, String(localized: "车牌")), (.text, String(localized: "文字")),
        ]
        return names.compactMap { kind, name in
            let count = regions.filter { $0.kind == kind }.count
            return count > 0 ? String(localized: "\(name) \(count) 处") : nil
        }.joinedAsList()
    }
}
