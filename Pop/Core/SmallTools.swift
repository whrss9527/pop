import Foundation

// MARK: - 日期计算

/// 两个日期相差多少天：「2026-09-29 到 2026-12-25」「2026年1月1日 - 2027年3月15日」，或者两行各一个日期。
enum DateSpan {
    struct Result: Equatable {
        var start: Date
        var end: Date
        /// 相差的天数（不含第二天那天）
        var days: Int
        /// 其中的周一到周五
        var workdays: Int
    }

    private static let pattern = #"(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?"#

    /// 文字里正好有两个日期（整段不太长）时算出相差多少天
    static func find(in text: String, calendar: Calendar = .current) -> Result? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 80, let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        guard matches.count == 2 else { return nil }
        let dates = matches.compactMap { match -> Date? in
            func number(_ index: Int) -> Int? {
                Range(match.range(at: index), in: trimmed).flatMap { Int(trimmed[$0]) }
            }
            guard let year = number(1), let month = number(2), let day = number(3),
                  (1...12).contains(month), (1...31).contains(day) else { return nil }
            var components = DateComponents(year: year, month: month, day: day)
            components.calendar = calendar
            // 2 月 30 日这种不存在的日子不算
            guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else { return nil }
            return date
        }
        guard dates.count == 2 else { return nil }
        let start = min(dates[0], dates[1])
        let end = max(dates[0], dates[1])
        guard let days = calendar.dateComponents([.day], from: start, to: end).day, days <= 366 * 200 else { return nil }
        var workdays = 0
        var day = start
        for _ in 0..<days {
            let weekday = calendar.component(.weekday, from: day)
            if weekday != 1 && weekday != 7 {
                workdays += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return Result(start: start, end: end, days: days, workdays: workdays)
    }

    static func rows(for result: Result, calendar: Calendar = .current) -> [ResultCard.Row] {
        var rows = [ResultCard.Row(label: String(localized: "相差"), value: String(localized: "\(result.days) 天"))]
        if result.days >= 7 {
            let rest = result.days % 7
            rows.append(ResultCard.Row(label: String(localized: "折合"), value: String(localized: "\(result.days / 7) 周") + (rest > 0 ? String(localized: " \(rest) 天") : "")))
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: result.start, to: result.end)
        if (parts.year ?? 0) > 0 || (parts.month ?? 0) > 0 {
            var text = ""
            if let years = parts.year, years > 0 { text += String(localized: "\(years) 年 ") }
            if let months = parts.month, months > 0 { text += String(localized: "\(months) 个月 ") }
            if let days = parts.day, days > 0 { text += String(localized: "\(days) 天") }
            rows.append(ResultCard.Row(label: String(localized: "也就是"), value: text.trimmingCharacters(in: .whitespaces)))
        }
        rows.append(ResultCard.Row(label: String(localized: "首尾都算"), value: String(localized: "\(result.days + 1) 天")))
        rows.append(ResultCard.Row(label: String(localized: "工作日"), value: String(localized: "\(result.workdays) 天（周一到周五，不算节假日）")))
        return rows
    }
}

// MARK: - 目录结构

/// 文件夹的目录结构：树形（├── └──）或者 Markdown 列表。文件夹在前，按名字排；隐藏文件不列，
/// node_modules 这类依赖文件夹只列名字不展开。
enum FolderTree {
    struct Result: Equatable {
        var tree: String
        var markdown: String
        var folders: Int
        var files: Int
        /// 太多了没有全部列出
        var truncated: Bool
    }

    /// 只列名字、不展开的文件夹
    static let collapsed: Set<String> = ["node_modules", "Pods", "DerivedData", ".build", "build", "dist", "vendor", "__pycache__",
                                         "target", ".gradle", "venv", ".venv"]

    static func build(_ root: URL, maxDepth: Int = 3, maxEntries: Int = 400) -> Result {
        var tree = [root.lastPathComponent + "/"]
        var markdown = ["- " + root.lastPathComponent + "/"]
        var folders = 0
        var files = 0
        var truncated = false

        func children(of folder: URL) -> [(url: URL, isFolder: Bool)] {
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                                                     options: [.skipsHiddenFiles])) ?? []
            return urls.map { url -> (url: URL, isFolder: Bool) in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                return (url, values?.isDirectory == true && values?.isPackage != true)
            }.sorted { lhs, rhs in
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
            }
        }

        func walk(_ folder: URL, prefix: String, depth: Int) {
            let items = children(of: folder)
            for (index, item) in items.enumerated() {
                guard tree.count <= maxEntries else {
                    truncated = true
                    return
                }
                let last = index == items.count - 1
                let name = item.url.lastPathComponent + (item.isFolder ? "/" : "")
                let expandable = item.isFolder && depth < maxDepth && !collapsed.contains(item.url.lastPathComponent)
                // 不展开的文件夹里有东西时后面加「…」（只看名字，node_modules 这种也很快）
                let hasContent = item.isFolder && !expandable
                    && ((try? FileManager.default.contentsOfDirectory(atPath: item.url.path(percentEncoded: false)))?.isEmpty == false)
                let note = hasContent ? " …" : ""
                tree.append(prefix + (last ? "└── " : "├── ") + name + note)
                markdown.append(String(repeating: "  ", count: depth) + "- " + name + note)
                if item.isFolder {
                    folders += 1
                } else {
                    files += 1
                }
                if expandable {
                    walk(item.url, prefix: prefix + (last ? "    " : "│   "), depth: depth + 1)
                }
            }
        }

        walk(root, prefix: "", depth: 1)
        if truncated {
            tree.append(String(localized: "…（太多了，没有全部列出）"))
            markdown.append(String(localized: "- …（太多了，没有全部列出）"))
        }
        return Result(tree: tree.joined(separator: "\n"), markdown: markdown.joined(separator: "\n"),
                      folders: folders, files: files, truncated: truncated)
    }

    static func isFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            && !path.hasSuffix(".app") && !path.hasSuffix(".app/")
    }
}

// MARK: - Markdown 目录

/// 按 Markdown 里的标题（# 开头）生成目录，锚点的写法和 GitHub 一样。代码块里的 # 不算。
enum MarkdownTOC {
    struct Heading: Equatable {
        var level: Int
        var title: String
        var anchor: String
    }

    static func headings(in markdown: String) -> [Heading] {
        var headings: [Heading] = []
        var used: [String: Int] = [:]
        var fence: String?
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // ``` 或者 ~~~ 围起来的代码块
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let marker = String(line.prefix(3))
                if fence == nil {
                    fence = marker
                } else if fence == marker {
                    fence = nil
                }
                continue
            }
            guard fence == nil, rawLine.prefix(while: { $0 == " " }).count < 4 else { continue }
            let hashes = line.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { continue }
            var title = String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
            // 结尾可以有收尾的 #
            while title.hasSuffix("#") {
                title.removeLast()
            }
            title = plainTitle(title.trimmingCharacters(in: .whitespaces))
            guard !title.isEmpty else { continue }
            headings.append(Heading(level: hashes, title: title, anchor: anchor(for: title, used: &used)))
        }
        return headings
    }

    /// 标题里的链接只留文字，去掉 `、*、~ 这些格式符号
    static func plainTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[`*~]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// GitHub 的写法：小写，去掉标点（保留字母、数字、汉字、空格、-、_），空格换成 -，重复的后面加 -1、-2
    static func anchor(for title: String, used: inout [String: Int]) -> String {
        var slug = ""
        for character in title.lowercased() {
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                slug.append(character)
            } else if character == " " {
                slug.append("-")
            }
        }
        let count = used[slug, default: 0]
        used[slug] = count + 1
        return count == 0 ? slug : "\(slug)-\(count)"
    }

    /// 缩进的列表，最浅的一级顶格
    static func toc(for headings: [Heading]) -> String {
        let base = headings.map(\.level).min() ?? 1
        return headings.map { heading in
            String(repeating: "  ", count: heading.level - base) + "- [\(heading.title)](#\(heading.anchor))"
        }.joined(separator: "\n")
    }
}
