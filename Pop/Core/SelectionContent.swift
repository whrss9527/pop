import Foundation

/// 从前台 App 读到的原始选中内容。
enum SelectionContent: Equatable {
    case text(String)
    case files([URL])
    case image(Data)
    case none
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
            if kinds.contains(.url) { return "链接" }
            if kinds.contains(.email) { return "邮箱" }
            if kinds.contains(.math) { return "算式" }
            if kinds.contains(.timestamp) { return "时间戳" }
            if kinds.contains(.json) { return "JSON" }
            return "\(text?.count ?? 0) 字"
        }
    }
}
