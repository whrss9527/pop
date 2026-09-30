import Foundation

/// App 里带着的更新记录（仓库根目录的 CHANGELOG.md）：更新后第一次启动告诉用户这一版新增了什么，「更新」页里也能看。
/// 更新记录只有中文：英文界面的通知只说更新到了哪一版，点开看网页上的版本说明
enum Changelog {
    struct Release: Equatable {
        let version: String
        let date: String?
        /// 版本标题下面的内容（Markdown）
        let notes: String
    }

    /// 记着上次启动时的版本，比较出是不是刚更新过
    static let lastVersionKey = "pop.lastLaunchedVersion"
    /// 最近一次是从哪个版本更新上来的，「更新」页按它列出这几版的更新内容
    static let updatedFromKey = "pop.updatedFromVersion"

    /// 分出每一版：「## 0.29.0（2026-09-30）」开头，到下一个「## 」为止；不是版本号的标题跳过
    static func parse(_ text: String) -> [Release] {
        var releases: [Release] = []
        var current: (version: String, date: String?)?
        var lines: [String] = []
        func flush() {
            if let current {
                releases.append(Release(version: current.version, date: current.date,
                                        notes: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            lines = []
        }
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                current = heading(line)
            } else if current != nil {
                lines.append(line)
            }
        }
        flush()
        return releases
    }

    /// 「## 0.29.0（2026-09-30）」→ 版本号和日期；半角括号也认
    static func heading(_ line: String) -> (version: String, date: String?)? {
        let title = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        let parts = title.split(maxSplits: 1, whereSeparator: { "（(".contains($0) })
        guard let first = parts.first else { return nil }
        let version = first.trimmingCharacters(in: .whitespaces)
        guard version.first?.isNumber == true else { return nil }
        let date = parts.count > 1 ? parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "）) ")) : nil
        return (version, date?.isEmpty == false ? date : nil)
    }

    /// 比 previous 新、不比 current 新的几版，新的在前（和文件里的顺序一样）
    static func releases(_ all: [Release], after previous: String, upTo current: String) -> [Release] {
        all.filter { UpdateChecker.isNewer($0.version, than: previous) && !UpdateChecker.isNewer($0.version, than: current) }
    }

    /// 这几版新增的功能：「### 新增」下面每一条开头加粗的名字，不重复
    static func highlights(_ releases: [Release]) -> [String] {
        var names: [String] = []
        for release in releases {
            var added = false
            for line in release.notes.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("### ") {
                    added = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces) == "新增"
                    continue
                }
                guard added, trimmed.hasPrefix("- **") else { continue }
                let rest = trimmed.dropFirst(4)
                if let end = rest.range(of: "**") {
                    let name = String(rest[..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty, !names.contains(name) {
                        names.append(name)
                    }
                }
            }
        }
        return names
    }

    /// 通知里的一句话：「新增：录屏、视频拼缩略图」；没有新增的功能就说修了问题。不是中文界面时不列名字
    static func summary(_ releases: [Release], chinese: Bool = Localization.isChinese) -> String {
        guard chinese else { return String(localized: "点这里看这一版的更新说明。") }
        let names = highlights(releases)
        guard !names.isEmpty else { return String(localized: "修了一些问题，用起来更顺手。点这里看更新内容。") }
        let shown = names.prefix(4).joinedAsList()
        return names.count > 4 ? String(localized: "新增：\(shown) 等 \(names.count) 项。点这里看更新内容。")
            : String(localized: "新增：\(shown)。点这里看更新内容。")
    }

    /// 网页上这一版的说明
    static func releasePage(_ version: String) -> URL {
        URL(string: "https://github.com/\(UpdateChecker.repository)/releases/tag/v\(version)") ?? UpdateChecker.releasesPageURL
    }

    /// 启动时调用：刚更新过（这次的版本比上次启动的新）就返回要告诉用户的话，第一次装或者降级返回 nil。顺便记下这次的版本
    static func whatsNew(current: String, releases all: [Release], defaults: UserDefaults = .standard) -> String? {
        let previous = defaults.string(forKey: lastVersionKey)
        defaults.set(current, forKey: lastVersionKey)
        guard let previous, UpdateChecker.isNewer(current, than: previous) else { return nil }
        defaults.set(previous, forKey: updatedFromKey)
        return summary(releases(all, after: previous, upTo: current))
    }

    /// 「更新」页上列出的：从上次更新前的版本到现在的每一版；不知道从哪版更新上来的就只列这一版
    static func recent(current: String, releases all: [Release], defaults: UserDefaults = .standard) -> [Release] {
        if let previous = defaults.string(forKey: updatedFromKey) {
            let list = releases(all, after: previous, upTo: current)
            if !list.isEmpty {
                return list
            }
        }
        return all.filter { $0.version == current }
    }

    /// App 里带着的更新记录
    static let bundled: [Release] = {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }()
}
