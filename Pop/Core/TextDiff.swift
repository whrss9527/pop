import Foundation

/// 两段文字的差异：先按行比较，一一对应的改动行再按词（中文按字）比较，标出具体改了哪里。
enum TextDiff {
    struct Segment: Equatable {
        var text: String
        /// 这一段是行内改动的部分（删去或新增的词）
        var changed: Bool
    }

    enum Kind: Equatable {
        case same
        case removed
        case added
    }

    struct Line: Equatable {
        var kind: Kind
        var segments: [Segment]

        var text: String { segments.map(\.text).joined() }
    }

    /// 显示用的一行：连续很多行相同时折叠成一行「⋯ N 行相同 ⋯」
    enum Row: Equatable {
        case line(Line)
        case skipped(Int)
    }

    struct Result: Equatable {
        var lines: [Line]

        var addedCount: Int { lines.filter { $0.kind == .added }.count }
        var removedCount: Int { lines.filter { $0.kind == .removed }.count }
        var isIdentical: Bool { lines.allSatisfy { $0.kind == .same } }

        /// 统一格式的差异文本：删去的行前面是「-」，新增的是「+」，相同的是两个空格
        var unifiedText: String {
            lines.map { line in
                switch line.kind {
                case .same: return "  " + line.text
                case .removed: return "- " + line.text
                case .added: return "+ " + line.text
                }
            }.joined(separator: "\n")
        }

        /// 改动的行前后各留 context 行相同的，其余相同的行折叠（只有一两行时不折叠）
        func rows(context: Int = 2) -> [Row] {
            var visible = lines.map { $0.kind != .same }
            for (index, line) in lines.enumerated() where line.kind != .same {
                for neighbor in max(0, index - context)...min(lines.count - 1, index + context) {
                    visible[neighbor] = true
                }
            }
            var rows: [Row] = []
            var hidden: [Line] = []
            func flushHidden() {
                if hidden.count > 2 {
                    rows.append(.skipped(hidden.count))
                } else {
                    rows += hidden.map(Row.line)
                }
                hidden.removeAll()
            }
            for (index, line) in lines.enumerated() {
                if visible[index] {
                    flushHidden()
                    rows.append(.line(line))
                } else {
                    hidden.append(line)
                }
            }
            flushHidden()
            return rows
        }
    }

    static func compare(_ old: String, _ new: String) -> Result {
        let oldLines = lines(of: old)
        let newLines = lines(of: new)
        let (removed, inserted) = changes(from: oldLines, to: newLines)
        var result: [Line] = []
        var pendingRemoved: [String] = []
        var pendingAdded: [String] = []
        func flush() {
            result += hunk(removed: pendingRemoved, added: pendingAdded)
            pendingRemoved.removeAll()
            pendingAdded.removeAll()
        }
        var i = 0
        var j = 0
        while i < oldLines.count || j < newLines.count {
            if i < oldLines.count, removed.contains(i) {
                pendingRemoved.append(oldLines[i])
                i += 1
            } else if j < newLines.count, inserted.contains(j) {
                pendingAdded.append(newLines[j])
                j += 1
            } else {
                flush()
                guard i < oldLines.count, j < newLines.count else { break }
                result.append(Line(kind: .same, segments: [Segment(text: oldLines[i], changed: false)]))
                i += 1
                j += 1
            }
        }
        flush()
        return Result(lines: result)
    }

    static func lines(of text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    /// 切成词：连续的字母、数字算一个词；汉字、假名、谚文、标点、空格各算一个
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var word = ""
        for character in text {
            if (character.isLetter || character.isNumber || character == "_") && !isCJK(character) {
                word.append(character)
            } else {
                if !word.isEmpty {
                    tokens.append(word)
                    word = ""
                }
                tokens.append(String(character))
            }
        }
        if !word.isEmpty {
            tokens.append(word)
        }
        return tokens
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
                return true
            default:
                return false
            }
        }
    }

    /// 从 old 变成 new 要删去 old 的哪几项、插入 new 的哪几项
    private static func changes<T: Hashable>(from old: [T], to new: [T]) -> (removed: Set<Int>, inserted: Set<Int>) {
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in new.difference(from: old) {
            switch change {
            case .remove(let offset, _, _):
                removed.insert(offset)
            case .insert(let offset, _, _):
                inserted.insert(offset)
            }
        }
        return (removed, inserted)
    }

    /// 一处改动：删去的几行排在前面，新增的几行排在后面；前后一一对应的行再逐词标出改了哪里
    private static func hunk(removed: [String], added: [String]) -> [Line] {
        var removedLines = removed.map { Line(kind: .removed, segments: [Segment(text: $0, changed: false)]) }
        var addedLines = added.map { Line(kind: .added, segments: [Segment(text: $0, changed: false)]) }
        for index in 0..<min(removed.count, added.count) {
            if let (old, new) = inlineSegments(removed[index], added[index]) {
                removedLines[index].segments = old
                addedLines[index].segments = new
            }
        }
        return removedLines + addedLines
    }

    /// 两行逐词比较；差别太大（相同的词不到四成）时逐词标出来反而乱，返回 nil，整行标出就好
    private static func inlineSegments(_ old: String, _ new: String) -> ([Segment], [Segment])? {
        let oldTokens = tokens(old)
        let newTokens = tokens(new)
        guard !oldTokens.isEmpty, !newTokens.isEmpty, oldTokens.count + newTokens.count <= 4_000 else { return nil }
        let (removed, inserted) = changes(from: oldTokens, to: newTokens)
        let common = oldTokens.count - removed.count
        guard Double(common) >= Double(max(oldTokens.count, newTokens.count)) * 0.4 else { return nil }
        return (segments(oldTokens, changed: removed), segments(newTokens, changed: inserted))
    }

    private static func segments(_ tokens: [String], changed: Set<Int>) -> [Segment] {
        var result: [Segment] = []
        for (index, token) in tokens.enumerated() {
            let isChanged = changed.contains(index)
            if let last = result.last, last.changed == isChanged {
                result[result.count - 1].text += token
            } else {
                result.append(Segment(text: token, changed: isChanged))
            }
        }
        return result
    }
}
