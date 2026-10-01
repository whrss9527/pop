import Foundation
@testable import Pop

/// 字幕文件：读 SRT、WebVTT、ASS/SSA、LRC，调整时间、换帧率、去掉样式标签和听障说明、两份合成双语，
/// 存成 SRT、WebVTT、LRC 或者纯文字。
enum SubtitleTools {
    struct Cue: Equatable {
        /// 秒
        var start: Double
        var end: Double
        /// 几行文字用换行隔开
        var text: String

        var duration: Double { max(end - start, 0) }
    }

    enum Format: String, CaseIterable, Identifiable {
        case srt
        case vtt
        case ass
        case lrc
        case txt

        var id: String { rawValue }

        var title: String {
            switch self {
            case .srt: return "SRT"
            case .vtt: return "WebVTT"
            case .ass: return "ASS"
            case .lrc: return "LRC"
            case .txt: return String(localized: "纯文字")
            }
        }

        var fileExtension: String { rawValue }

        /// 能存成的格式（ASS 只读不写）
        static let outputs: [Format] = [.srt, .vtt, .lrc, .txt]
    }

    /// 换帧率：同一部片子不同帧率的版本（比如 25 帧的 PAL 版本更短），字幕的时间按比例伸缩
    enum RateChange: String, CaseIterable, Identifiable {
        case none
        case film23to25
        case pal25to23
        case film24to25
        case pal25to24

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return String(localized: "不换帧率")
            case .film23to25: return "23.976 → 25"
            case .pal25to23: return "25 → 23.976"
            case .film24to25: return "24 → 25"
            case .pal25to24: return "25 → 24"
            }
        }

        /// 时间乘上这个数：原来的帧率 ÷ 现在的帧率
        var factor: Double {
            switch self {
            case .none: return 1
            case .film23to25: return 23.976 / 25
            case .pal25to23: return 25 / 23.976
            case .film24to25: return 24.0 / 25
            case .pal25to24: return 25 / 24.0
            }
        }
    }

    static let extensions: Set<String> = ["srt", "vtt", "ass", "ssa", "lrc"]

    static func isSubtitle(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - 读

    /// 按扩展名认格式；认不出时看内容
    static func format(of url: URL, text: String) -> Format? {
        switch url.pathExtension.lowercased() {
        case "srt": return .srt
        case "vtt": return .vtt
        case "ass", "ssa": return .ass
        case "lrc": return .lrc
        default: break
        }
        let head = text.prefix(400)
        if head.hasPrefix("WEBVTT") { return .vtt }
        if head.contains("[Script Info]") { return .ass }
        if head.contains("-->") { return .srt }
        if head.contains("[00:") { return .lrc }
        return nil
    }

    static func parse(_ text: String, format: Format) -> [Cue] {
        switch format {
        case .srt, .vtt: return parseTimed(text)
        case .ass: return parseASS(text)
        case .lrc: return parseLRC(text)
        case .txt: return []
        }
    }

    /// 读文件的文字：UTF-8（带不带 BOM）、UTF-16，不是的话按 GB18030、Big5 这些试；返回文字和编码的名字
    static func decode(_ data: Data) -> (text: String, encoding: String)? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data.dropFirst(3), encoding: .utf8) {
            return (text, "UTF-8")
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) {
            return (text, "UTF-16")
        }
        if let text = String(data: data, encoding: .utf8) {
            return (text, "UTF-8")
        }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        let big5 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
        var converted: NSString?
        var lossy: ObjCBool = false
        let raw = NSString.stringEncoding(for: data, encodingOptions: [.suggestedEncodingsKey: [gb18030, big5], .allowLossyKey: false],
                                          convertedString: &converted, usedLossyConversion: &lossy)
        guard raw != 0, let converted else { return nil }
        let name = raw == gb18030 ? "GBK" : raw == big5 ? "Big5" : String.localizedName(of: String.Encoding(rawValue: raw))
        return (converted as String, name)
    }

    /// 换行统一成 \n，去掉开头的 BOM
    static func normalized(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if result.hasPrefix("\u{FEFF}") {
            result.removeFirst()
        }
        return result
    }

    /// 「01:02:03,456」「02:03.456」「0:01:02.45」→ 秒；分和秒不能超过 59，只有最后一段可以带小数
    static func seconds(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), let value = Double(part),
                  index == parts.count - 1 || !part.contains(".") else { return nil }
            if index > 0 && value >= 60 {
                return nil
            }
            total = total * 60 + value
        }
        return total
    }

    /// 「00:00:01,000 --> 00:00:02,500 X1:100」→ 开始和结束
    static func timing(_ line: String) -> (start: Double, end: Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2, let start = seconds(parts[0]),
              let endText = parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first,
              let end = seconds(String(endText)) else { return nil }
        return (start, max(end, start))
    }

    /// SRT 和 WebVTT：一行时间，下面几行文字，空行隔开。前面的序号、WebVTT 的标识和 NOTE 都不算文字
    private static func parseTimed(_ text: String) -> [Cue] {
        var cues: [Cue] = []
        var current: Cue?
        var lines: [String] = []
        var collecting = false
        func finish() {
            guard var cue = current else { return }
            cue.text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            cues.append(cue)
            current = nil
            lines = []
        }
        for line in normalized(text).components(separatedBy: "\n") {
            if line.contains("-->"), let time = timing(line) {
                // 没有空行隔开时，上一句最后一行是这一句的序号
                if let last = lines.last, !last.isEmpty, last.allSatisfy(\.isNumber) {
                    lines.removeLast()
                }
                finish()
                current = Cue(start: time.start, end: time.end, text: "")
                collecting = true
            } else if current != nil && collecting {
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    // 文字后面的空行是这一句的结尾
                    if !lines.isEmpty { collecting = false }
                } else {
                    lines.append(line)
                }
            }
        }
        finish()
        return cues
    }

    /// ASS/SSA：[Events] 里的 Dialogue 行，按 Format 行找开始、结束和文字；去掉 {…} 特效，\N 换行
    private static func parseASS(_ text: String) -> [Cue] {
        var fields = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
        var inEvents = false
        var cues: [Cue] = []
        for line in normalized(text).components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if trimmed.hasPrefix("[") {
                inEvents = lower == "[events]"
                continue
            }
            guard inEvents else { continue }
            if lower.hasPrefix("format:") {
                fields = trimmed.dropFirst(7).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            } else if lower.hasPrefix("dialogue:") {
                // 文字是最后一项，里面可能有逗号
                let values = trimmed.dropFirst(9).split(separator: ",", maxSplits: max(fields.count - 1, 0), omittingEmptySubsequences: false)
                    .map(String.init)
                guard values.count == fields.count, let startIndex = fields.firstIndex(of: "start"), let endIndex = fields.firstIndex(of: "end"),
                      let textIndex = fields.firstIndex(of: "text"),
                      let start = seconds(values[startIndex]), let end = seconds(values[endIndex]) else { continue }
                let body = assText(values[textIndex])
                if !body.isEmpty {
                    cues.append(Cue(start: start, end: max(end, start), text: body))
                }
            }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// ASS 的文字：去掉 {…} 特效，\N 换行，\h 空格
    static func assText(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: " ")
        while let open = text.range(of: "{"), let close = text.range(of: "}", range: open.upperBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// LRC 歌词：每行前面一个或几个 [分:秒.百分秒]，一句到下一句开始时结束；[offset:毫秒] 整体提前
    private static func parseLRC(_ text: String) -> [Cue] {
        var stamps: [(time: Double, words: String)] = []
        var offset = 0.0
        for line in normalized(text).components(separatedBy: "\n") {
            var rest = Substring(line.trimmingCharacters(in: .whitespaces))
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = String(rest[rest.index(after: rest.startIndex)..<close])
                if let time = seconds(tag) {
                    times.append(time)
                } else if tag.lowercased().hasPrefix("offset:"), let milliseconds = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    offset = milliseconds / 1000
                }
                rest = rest[rest.index(after: close)...]
            }
            // 逐字歌词里的 <分:秒.百分秒> 不要
            let words = stripTags(String(rest)).trimmingCharacters(in: .whitespaces)
            for time in times {
                stamps.append((time: time, words: words))
            }
        }
        stamps.sort { $0.time < $1.time }
        var cues: [Cue] = []
        for (index, stamp) in stamps.enumerated() where !stamp.words.isEmpty {
            let next = index + 1 < stamps.count ? stamps[index + 1].time : stamp.time + 4
            cues.append(Cue(start: max(stamp.time - offset, 0), end: max(next - offset, 0), text: stamp.words))
        }
        return cues
    }

    // MARK: - 处理

    /// 换帧率、整体提前或推后（秒，正数推后）；提前到 0 之前的句子去掉
    static func retime(_ cues: [Cue], shift: Double, rate: RateChange = .none) -> [Cue] {
        cues.compactMap { cue in
            let start = cue.start * rate.factor + shift
            let end = cue.end * rate.factor + shift
            guard end > 0 else { return nil }
            return Cue(start: max(start, 0), end: end, text: cue.text)
        }
    }

    private static let tagPattern = try? NSRegularExpression(pattern: #"</?[A-Za-z][^>\n]*>|<\d+:\d+(?:[.:]\d+)?>|\{[^}\n]*\}"#)
    private static let descriptionPattern = try? NSRegularExpression(pattern: #"\[[^\]\n]*\]|\([^)\n]*\)|（[^）\n]*）|【[^】\n]*】|♪[^♪\n]*♪"#)

    /// 去掉样式标签：<i>、<b>、<font color=…>、{\an8}、逐字歌词的时间
    static func stripTags(_ text: String) -> String {
        guard let tagPattern else { return text }
        return tagPattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    /// 去掉听障说明：[音乐]、(笑声)、（掌声）、♪ 歌词 ♪
    static func stripDescriptions(_ text: String) -> String {
        guard let descriptionPattern else { return text }
        return descriptionPattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    /// 整理文字：去掉标签和说明以后，每行去掉首尾空格，空行和空的句子都不要
    static func clean(_ cues: [Cue], tags: Bool, descriptions: Bool) -> [Cue] {
        guard tags || descriptions else { return cues }
        return cues.compactMap { cue in
            var text = cue.text
            if tags { text = stripTags(text) }
            if descriptions { text = stripDescriptions(text) }
            let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { return nil }
            return Cue(start: cue.start, end: cue.end, text: lines.joined(separator: "\n"))
        }
    }

    /// 合成双语：第二份的每一句配给第一份里和它时间重叠最多的那句（至少重叠短的那句的三成），
    /// 上面一行是第一份的文字，下面一行是第二份的；配不上的句子单独留着
    static func merge(_ first: [Cue], _ second: [Cue]) -> [Cue] {
        func overlap(_ a: Cue, _ b: Cue) -> Double {
            max(0, min(a.end, b.end) - max(a.start, b.start))
        }
        var partners: [Int: [Int]] = [:]
        var alone: [Cue] = []
        for (index, cue) in second.enumerated() {
            let best = first.indices.max { overlap(first[$0], cue) < overlap(first[$1], cue) }
            if let best, overlap(first[best], cue) > 0, overlap(first[best], cue) >= min(first[best].duration, cue.duration) * 0.3 {
                partners[best, default: []].append(index)
            } else {
                alone.append(cue)
            }
        }
        func line(_ text: String) -> String {
            text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        }
        var merged = first.enumerated().map { index, cue -> Cue in
            let lower = (partners[index] ?? []).map { line(second[$0].text) }.joined(separator: " ")
            return Cue(start: cue.start, end: cue.end, text: lower.isEmpty ? line(cue.text) : line(cue.text) + "\n" + lower)
        }
        merged += alone.map { Cue(start: $0.start, end: $0.end, text: line($0.text)) }
        return merged.sorted { $0.start < $1.start }
    }

    // MARK: - 写

    static func render(_ cues: [Cue], as format: Format) -> String {
        switch format {
        case .srt:
            return cues.enumerated().map { index, cue in
                "\(index + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(cue.text)\n"
            }.joined(separator: "\n")
        case .vtt:
            return "WEBVTT\n\n" + cues.map { cue in
                "\(timestamp(cue.start, separator: ".")) --> \(timestamp(cue.end, separator: "."))\n\(cue.text)\n"
            }.joined(separator: "\n")
        case .lrc:
            return cues.map { "[\(lyricTime($0.start))]\($0.text.replacingOccurrences(of: "\n", with: " "))" }.joined(separator: "\n") + "\n"
        case .txt:
            return cues.map { $0.text.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n") + "\n"
        case .ass:
            // 不写 ASS，按 SRT 写
            return render(cues, as: .srt)
        }
    }

    /// 「01:02:03,456」（WebVTT 用点）
    static func timestamp(_ seconds: Double, separator: String = ",") -> String {
        let total = max(0, Int((seconds * 1000).rounded()))
        return String(format: "%02d:%02d:%02d", total / 3_600_000, total / 60_000 % 60, total / 1000 % 60) + separator
            + String(format: "%03d", total % 1000)
    }

    /// LRC 的时间「62:03.46」：分可以超过 59，秒后面两位
    static func lyricTime(_ seconds: Double) -> String {
        let total = max(0, Int((seconds * 100).rounded()))
        return String(format: "%02d:%02d.%02d", total / 6000, total / 100 % 60, total % 100)
    }

    /// 两份字幕合成以后的文件名：两个名字相同的开头（「电影.en」「电影.zh」→「电影」）加上「双语」
    static func mergedName(_ first: URL, _ second: URL) -> String {
        let a = first.deletingPathExtension().lastPathComponent
        let b = second.deletingPathExtension().lastPathComponent
        let common = String(zip(a, b).prefix { $0 == $1 }.map(\.0))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ._-（(").union(.whitespaces))
        return String(localized: "\(common.isEmpty ? a : common) 双语")
    }
}
