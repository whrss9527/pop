import AppKit
import CoreText
@testable import Pop

/// 这台 Mac 上的字体：每个字体家族一项，记着显示名字、常规字重的 PostScript 名、几种字重、是不是中文字体、是不是等宽、
/// 字体文件在哪；还能看一段文字它能不能完整显示。字体文件（.ttf、.otf、.ttc）不装也能先读出来预览。
enum FontCatalog {
    struct Family: Identifiable, Equatable {
        /// 字体家族的名字（英文，比如「PingFang SC」），CSS、设计软件里用它
        let name: String
        /// 按界面语言写的名字（中文界面是「苹方-简」）
        let displayName: String
        /// 常规字重那一款的 PostScript 名（「PingFangSC-Regular」）
        let postScriptName: String
        /// 有几种字重和样式
        let styles: Int
        let isChinese: Bool
        let isMonospaced: Bool
        /// 字体文件；系统字体也有
        let file: URL?

        var id: String { name }

        /// 系统自带的（/System/Library 里的）
        var isSystem: Bool {
            file?.path(percentEncoded: false).hasPrefix("/System/") ?? true
        }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case chinese
        case western
        case monospaced
        case favorites

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return String(localized: "全部")
            case .chinese: return String(localized: "中文")
            case .western: return String(localized: "西文")
            case .monospaced: return String(localized: "等宽")
            case .favorites: return String(localized: "收藏")
            }
        }
    }

    /// 没选中文字时的示例
    static var sample: String {
        String(localized: "永和九年，岁在癸丑 The quick brown fox jumps over the lazy dog 0123456789")
    }

    /// 用来判断是不是中文字体的几个常用字
    static let chineseProbe = "永国的我们"

    static let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "otc", "dfont"]

    static func isFontFile(_ url: URL) -> Bool {
        fontExtensions.contains(url.pathExtension.lowercased())
    }

    /// 装着的字体家族，按显示名字排；名字以「.」开头的系统内部字体不要
    static func installed() -> [Family] {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { !$0.hasPrefix(".") }.compactMap { name in
            let members = manager.availableMembers(ofFontFamily: name) ?? []
            // 挑常规字重（5）、不是斜体的那一款，没有就用第一款
            let regular = members.first { member in
                member.count > 3 && (member[2] as? Int) == 5 && ((member[3] as? UInt) ?? 0) & NSFontTraitMask.italicFontMask.rawValue == 0
            } ?? members.first
            guard let postScriptName = regular?.first as? String else { return nil }
            let font = CTFontCreateWithName(postScriptName as CFString, 16, nil)
            return family(name: name, displayName: manager.localizedName(forFamily: name, face: nil), postScriptName: postScriptName,
                          styles: members.count, font: font)
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    static func family(name: String, displayName: String, postScriptName: String, styles: Int, font: CTFont) -> Family {
        let traits = CTFontGetSymbolicTraits(font)
        let file = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL
        return Family(name: name, displayName: displayName.isEmpty ? name : displayName, postScriptName: postScriptName, styles: styles,
                      isChinese: covers(font, chineseProbe), isMonospaced: traits.contains(.traitMonoSpace), file: file)
    }

    /// 字体能不能完整显示这段文字（空格、换行不算）
    static func covers(_ font: CTFont, _ text: String) -> Bool {
        var checked = Set<String>()
        for character in text where !character.isWhitespace && !character.isNewline {
            let piece = String(character)
            guard checked.insert(piece).inserted else { continue }
            let units = Array(piece.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            if !CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count) {
                return false
            }
        }
        return true
    }

    /// 字体文件里的每一款（.ttc 里有好几款），不装也能用来预览
    static func faces(in file: URL) -> [(postScriptName: String, displayName: String, font: CTFont)] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor] else { return [] }
        return descriptors.map { descriptor in
            let font = CTFontCreateWithFontDescriptor(descriptor, 16, nil)
            let postScriptName = CTFontCopyPostScriptName(font) as String
            let displayName = CTFontCopyDisplayName(font) as String
            return (postScriptName: postScriptName, displayName: displayName, font: font)
        }
    }

    /// 装上：复制到「~/资源库/Fonts」（同名的已经有了就不复制），返回装好的
    static func install(_ files: [URL], into folder: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Fonts", directoryHint: .isDirectory)) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var installed: [URL] = []
        for file in files {
            let target = folder.appending(path: file.lastPathComponent)
            if !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
                try FileManager.default.copyItem(at: file, to: target)
            }
            installed.append(target)
        }
        return installed
    }

    /// 按筛选、搜索、能不能显示这段文字挑出来
    static func filter(_ families: [Family], by filter: Filter, favorites: Set<String>, search: String,
                       covering text: String?, coverage: [String: Bool]) -> [Family] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return families.filter { family in
            switch filter {
            case .all: break
            case .chinese: guard family.isChinese else { return false }
            case .western: guard !family.isChinese else { return false }
            case .monospaced: guard family.isMonospaced else { return false }
            case .favorites: guard favorites.contains(family.name) else { return false }
            }
            if !query.isEmpty, !family.name.lowercased().contains(query), !family.displayName.lowercased().contains(query) {
                return false
            }
            if text != nil, coverage[family.name] == false {
                return false
            }
            return true
        }
    }

    /// CSS 里用的写法：`font-family: "PingFang SC";`
    static func css(_ family: Family) -> String {
        "font-family: \"\(family.name)\";"
    }
}
