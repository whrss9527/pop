import Foundation

/// 从前台 App 读到的原始选中内容。
enum SelectionContent: Equatable {
    case text(String)
    case files([URL])
    case image(Data)
    case none
}

/// 带格式的选中内容（重新拷贝一次得到），给「转成 Markdown」用。
struct RichSelection: Equatable {
    var html: String?
    var rtf: Data?
    var rtfd: Data?
    var text: String?

    var isEmpty: Bool { html == nil && rtf == nil && rtfd == nil && text == nil }
}

/// 识别出的内容特征。一段内容可以同时具备多个特征（比如链接同时也是文本）。
enum ContentKind: String, Codable, CaseIterable {
    /// 任意文本
    case text
    /// 以中文为主的自然语言文本
    case chineseText
    /// 非中文的自然语言文本（外文）
    case foreignText
    case url
    case email
    /// 可计算的算式
    case math
    /// Unix 时间戳（秒或毫秒）
    case timestamp
    case json
    case files
    case image
    /// 单个词（英文单词或很短的中文词）
    case word
    /// 颜色值：#RRGGBB、rgb()、hsl()
    case color
    /// 数字（十进制、0x 十六进制、0b 二进制、0o 八进制）
    case number
    /// 日期时间，比如 2026-09-28 14:30、2026年9月28日
    case dateTime
    /// 选中的文件都是图片
    case imageFile
    /// 带单位的数值，比如 5 km、100°F、2 斤、1 TB
    case measurement

    var title: String {
        switch self {
        case .text: return "文本"
        case .chineseText: return "中文"
        case .foreignText: return "外文"
        case .url: return "链接"
        case .email: return "邮箱"
        case .math: return "算式"
        case .timestamp: return "时间戳"
        case .json: return "JSON"
        case .files: return "文件"
        case .image: return "图片"
        case .word: return "单个词"
        case .color: return "颜色"
        case .number: return "数字"
        case .dateTime: return "日期时间"
        case .imageFile: return "图片文件"
        case .measurement: return "带单位的数值"
        }
    }
}

/// 分类后的内容，插件和分发规则都基于它工作。
struct ClassifiedContent: Equatable {
    var selection: SelectionContent
    var kinds: Set<ContentKind>
    /// 去掉首尾空白后的文本
    var text: String?
    /// 识别出的语种（BCP-47，比如 en、ja、zh-Hans）
    var language: String?
    var url: URL?
    var files: [URL]

    static let empty = ClassifiedContent(selection: .none, kinds: [], text: nil, language: nil, url: nil, files: [])

    var isEmpty: Bool { kinds.isEmpty }

    /// 圆盘中心显示的简短描述
    var summary: String {
        switch selection {
        case .none:
            return "未选中内容"
        case .files(let urls):
            return urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) 个文件"
        case .image:
            return "图片"
        case .text:
            if kinds.contains(.measurement), let text, text.count <= 12 {
                return text
            }
            let specific: [ContentKind] = [.url, .email, .math, .timestamp, .json, .color, .dateTime, .measurement, .number, .files]
            if let kind = specific.first(where: { kinds.contains($0) }) {
                return kind == .files ? "路径" : kind.title
            }
            if kinds.contains(.word), let text { return text }
            return "\(text?.count ?? 0) 字"
        }
    }
}
