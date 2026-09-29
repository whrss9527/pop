import Foundation

/// 批量重命名：按规则算出每个文件的新名字（扩展名不变），检查有没有重名，再一起改名；改完可以撤销。
enum BatchRename {
    enum Mode: String, CaseIterable, Identifiable {
        case sequence
        case replace
        case affix
        case captureDate
        case letterCase

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sequence: return "编号"
            case .replace: return "替换文字"
            case .affix: return "加前后缀"
            case .captureDate: return "拍摄时间"
            case .letterCase: return "大小写"
            }
        }
    }

    enum LetterCase: String, CaseIterable, Identifiable {
        case lower
        case upper
        case capitalized

        var id: String { rawValue }

        var title: String {
            switch self {
            case .lower: return "全部小写"
            case .upper: return "全部大写"
            case .capitalized: return "首字母大写"
            }
        }
    }

    struct Rule: Equatable {
        var mode: Mode = .sequence
        /// 编号：名字（后面接编号）、从几开始、至少几位
        var name = ""
        var start = 1
        var digits = 2
        /// 替换文字
        var find = ""
        var replacement = ""
        var useRegex = false
        /// 加前后缀
        var prefix = ""
        var suffix = ""
        var letterCase: LetterCase = .lower
    }

    struct Item: Equatable, Identifiable {
        var source: URL
        var newName: String
        /// 这个名字不能用的原因
        var problem: String?

        var id: URL { source }
        var changed: Bool { newName != source.lastPathComponent }
    }

    struct Plan: Equatable {
        var items: [Item] = []
        /// 规则本身有问题（比如正则写错了）
        var error: String?

        var changes: [Item] { items.filter(\.changed) }
        var problems: Int { items.filter { $0.problem != nil }.count }
        var canApply: Bool { error == nil && problems == 0 && !changes.isEmpty }
    }

    struct Move: Equatable {
        var from: URL
        var to: URL
    }

    struct Failure: Error, Equatable {
        let message: String
    }

    /// 按文件名排好的顺序（和访达按名称排列一样，数字按大小排）
    static func ordered(_ files: [URL]) -> [URL] {
        files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// 算出每个文件的新名字。dateNames 是「拍摄时间」模式下每个文件的时间写法；exists 判断文件夹里是不是已经有这个名字；
    /// 文件夹（App 这类包除外）的名字里的点不算扩展名
    static func plan(_ files: [URL], rule: Rule, dateNames: [URL: String] = [:],
                     exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) },
                     isFolder: (URL) -> Bool = { url in
                         let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                         return values?.isDirectory == true && values?.isPackage != true
                     }) -> Plan {
        var regex: NSRegularExpression?
        if rule.mode == .replace, rule.useRegex, !rule.find.isEmpty {
            do {
                regex = try NSRegularExpression(pattern: rule.find)
            } catch {
                return Plan(items: files.map { Item(source: $0, newName: $0.lastPathComponent) }, error: "正则表达式有误")
            }
        }
        var items: [Item] = []
        var usedDates: [String: Int] = [:]
        for (index, file) in files.enumerated() {
            let name = file.lastPathComponent
            let ext = isFolder(file) ? "" : (name as NSString).pathExtension
            let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
            var newBase = base
            switch rule.mode {
            case .sequence:
                let raw = String(rule.start + index)
                let number = String(repeating: "0", count: max(min(rule.digits, 6) - raw.count, 0)) + raw
                let prefix = rule.name.trimmingCharacters(in: .newlines)
                if prefix.isEmpty {
                    newBase = number
                } else if let last = prefix.last, " -_.（(【[".contains(last) {
                    newBase = prefix + number
                } else {
                    newBase = "\(prefix) \(number)"
                }
            case .replace:
                if let regex {
                    let range = NSRange(base.startIndex..., in: base)
                    newBase = regex.stringByReplacingMatches(in: base, range: range, withTemplate: rule.replacement)
                } else if !rule.find.isEmpty {
                    newBase = base.replacingOccurrences(of: rule.find, with: rule.replacement)
                }
            case .affix:
                newBase = rule.prefix + base + rule.suffix
            case .captureDate:
                if let date = dateNames[file] {
                    // 同一秒拍的几张：后面加 2、3……
                    let count = (usedDates[date] ?? 0) + 1
                    usedDates[date] = count
                    newBase = count == 1 ? date : "\(date) \(count)"
                }
            case .letterCase:
                switch rule.letterCase {
                case .lower: newBase = base.lowercased()
                case .upper: newBase = base.uppercased()
                case .capitalized: newBase = base.capitalized
                }
            }
            let newName = ext.isEmpty ? newBase : "\(newBase).\(ext)"
            let issue = newBase.trimmingCharacters(in: .whitespaces).isEmpty ? "名字不能是空的" : problem(with: newName, original: name)
            items.append(Item(source: file, newName: newName, problem: issue))
        }
        markConflicts(&items, exists: exists)
        return Plan(items: items)
    }

    /// 名字本身能不能用
    static func problem(with name: String, original: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "." || trimmed == ".." {
            return "名字不能是空的"
        }
        if name.contains("/") || name.contains(":") {
            return "名字里不能有 / 或 :"
        }
        if name.hasPrefix("."), !original.hasPrefix(".") {
            return "以 . 开头的文件会被隐藏"
        }
        if name.utf8.count > 255 {
            return "名字太长了"
        }
        return nil
    }

    /// 同一个文件夹里重名的、和不改名的文件撞名的，都标出来（不分大小写，和访达一样）
    private static func markConflicts(_ items: inout [Item], exists: (URL) -> Bool) {
        func key(_ url: URL) -> String {
            url.standardizedFileURL.path(percentEncoded: false).lowercased()
        }
        let sources = Set(items.map { key($0.source) })
        var targets: [String: Int] = [:]
        for item in items {
            targets[key(item.source.deletingLastPathComponent().appending(path: item.newName)), default: 0] += 1
        }
        for index in items.indices where items[index].problem == nil {
            let item = items[index]
            let target = item.source.deletingLastPathComponent().appending(path: item.newName)
            if (targets[key(target)] ?? 0) > 1 {
                items[index].problem = "和另一个文件重名"
            } else if item.changed, !sources.contains(key(target)), exists(target) {
                items[index].problem = "文件夹里已经有这个名字"
            }
        }
    }

    /// 按计划改名，返回每个文件从哪里改到了哪里（撤销用）
    static func apply(_ plan: Plan) throws -> [Move] {
        guard plan.canApply else { throw Failure(message: plan.error ?? "有的名字不能用") }
        let moves = plan.changes.map { item in
            Move(from: item.source, to: item.source.deletingLastPathComponent().appending(path: item.newName))
        }
        try perform(moves)
        return moves
    }

    /// 撤销：全部改回原来的名字
    static func undo(_ moves: [Move]) throws {
        try perform(moves.map { Move(from: $0.to, to: $0.from) })
    }

    /// 先全部改成临时名字，再改成新名字：名字互换（a ↔ b）、只改大小写也不会撞上；中途失败就全部改回去
    static func perform(_ moves: [Move]) throws {
        let manager = FileManager.default
        // 每个文件现在在哪里
        var current = moves.map(\.from)
        do {
            for index in moves.indices {
                let temporary = moves[index].from.deletingLastPathComponent().appending(path: ".pop-rename-\(UUID().uuidString)")
                try manager.moveItem(at: current[index], to: temporary)
                current[index] = temporary
            }
            for index in moves.indices {
                try manager.moveItem(at: current[index], to: moves[index].to)
                current[index] = moves[index].to
            }
        } catch {
            // 已经改到新名字的先挪回临时名字（新名字可能正是别的文件原来的名字），再全部改回原来的名字
            for index in moves.indices where current[index] != moves[index].from {
                if current[index] == moves[index].to {
                    let temporary = moves[index].from.deletingLastPathComponent().appending(path: ".pop-rename-\(UUID().uuidString)")
                    if (try? manager.moveItem(at: current[index], to: temporary)) != nil {
                        current[index] = temporary
                    }
                }
            }
            for index in moves.indices where current[index] != moves[index].from {
                try? manager.moveItem(at: current[index], to: moves[index].from)
            }
            throw Failure(message: "改名失败：\(error.localizedDescription)")
        }
    }

    /// 「拍摄时间」模式下每个文件的名字：照片按拍摄时间，别的文件按修改时间，写成 2026-09-27 17.42.18
    static func dateNames(for files: [URL]) -> [URL: String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        var names: [URL: String] = [:]
        for file in files {
            if let taken = PhotoMetadata.captureDate(of: file) {
                // 照片里记的是拍摄地的时间，原样使用
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                names[file] = formatter.string(from: taken)
            } else if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                formatter.timeZone = .current
                names[file] = formatter.string(from: modified)
            }
        }
        return names
    }
}
