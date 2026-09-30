import AppKit

/// 文字转图片：把一段文字排成一张手机上看着舒服的长图（宽 1080 像素），发到不方便贴长文字的地方
enum TextImage {
    enum Style: String, CaseIterable, Identifiable {
        case paper
        case warm
        case night

        var id: String { rawValue }

        var title: String {
            switch self {
            case .paper: return String(localized: "白底")
            case .warm: return String(localized: "米黄")
            case .night: return String(localized: "深色")
            }
        }

        var background: NSColor {
            switch self {
            case .paper: return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            case .warm: return NSColor(srgbRed: 0.98, green: 0.95, blue: 0.88, alpha: 1)
            case .night: return NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1)
            }
        }

        var text: NSColor {
            switch self {
            case .paper: return NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
            case .warm: return NSColor(srgbRed: 0.24, green: 0.2, blue: 0.15, alpha: 1)
            case .night: return NSColor(srgbRed: 0.87, green: 0.88, blue: 0.9, alpha: 1)
            }
        }
    }

    /// 图片宽度（点）：按 2 倍像素画，正好 1080 像素宽
    static let width: CGFloat = 540
    static let margin: CGFloat = 36
    static let fontSize: CGFloat = 17
    /// 最多画这么多字，再多截掉，末尾说一声
    static let maxCharacters = 8000

    /// 整理一下：统一换行、去掉首尾和行尾的空白、连续的空行只留一个、Tab 换成空格
    static func normalized(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
            .components(separatedBy: "\n")
            .map { line -> String in
                var line = line
                while line.last?.isWhitespace == true {
                    line.removeLast()
                }
                return line
            }
        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty ?? true {
                continue
            }
            result.append(line)
        }
        while result.last?.isEmpty == true {
            result.removeLast()
        }
        return result.joined(separator: "\n")
    }

    /// 太长的截到 maxCharacters 个字，后面注明还剩多少字
    static func limited(_ text: String) -> String {
        guard text.count > maxCharacters else { return text }
        let rest = text.count - maxCharacters
        return String(text.prefix(maxCharacters)) + "\n\n" + String(localized: "……（后面还有 \(rest) 字没画）")
    }

    static func attributed(_ text: String, style: Style) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * 0.55
        paragraph.paragraphSpacing = fontSize * 0.7
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: style.text,
            .paragraphStyle: paragraph,
        ])
    }

    /// 画成 PNG（scale 倍像素）；没有文字时返回 nil
    static func render(_ source: String, style: Style = .paper, scale: CGFloat = 2) -> Data? {
        let text = limited(normalized(source))
        guard !text.isEmpty else { return nil }
        let string = attributed(text, style: style)
        let textWidth = width - margin * 2
        let textHeight = ceil(string.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                                                      options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        let size = CGSize(width: width, height: textHeight + margin * 2)
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int((size.height * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0, pixelWidth * pixelHeight <= 120_000_000,
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(style.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        // 换成「点、左上角为原点」的坐标
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        string.draw(with: CGRect(x: margin, y: margin, width: textWidth, height: textHeight + 2),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// 结果卡片：预览、复制、存储、贴到屏幕，换别的底色
    static func card(_ text: String, style: Style, png: Data) -> ResultCard {
        let count = normalized(text).count
        var buttons = [
            CardButton(title: String(localized: "复制图片"), action: .copyImage(png)),
            CardButton(title: String(localized: "存储"), action: .saveImage(png, name: ImageFiles.timestampedName(String(localized: "Pop 文字")))),
            CardButton(title: String(localized: "贴到屏幕"), action: .pinImage(png)),
        ]
        buttons += Style.allCases.filter { $0 != style }.map { CardButton(title: $0.title, action: .textImage(text, $0)) }
        return ResultCard(title: String(localized: "文字转图片"), detail: String(localized: "\(count) 个字，图片宽 1080 像素；按住拖动预览图也能拖到别的 App 里"),
                          image: png, buttons: buttons)
    }
}
