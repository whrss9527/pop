import Foundation
import UniformTypeIdentifiers
@testable import Pop

/// 文本文件的编码和换行：认出是什么编码（UTF-8、带 BOM 的 UTF-8 / UTF-16、GB18030、Big5……）、用的什么换行，
/// 转成 UTF-8（可以带 BOM，Excel 打开 CSV 才不乱码）或者 GB18030，换行统一成 LF 或 CRLF。
enum TextEncodingTools {
    struct Failure: Error, Equatable {
        let message: String
    }

    enum Encoding: String, CaseIterable, Identifiable {
        case utf8
        case utf8BOM
        case utf16LE
        case utf16BE
        case gb18030
        case big5
        case shiftJIS
        case eucKR
        case windows1252

        var id: String { rawValue }

        var title: String {
            switch self {
            case .utf8: return "UTF-8"
            case .utf8BOM: return String(localized: "UTF-8 带 BOM")
            case .utf16LE: return "UTF-16 LE"
            case .utf16BE: return "UTF-16 BE"
            case .gb18030: return "GB18030（GBK）"
            case .big5: return "Big5"
            case .shiftJIS: return "Shift_JIS"
            case .eucKR: return "EUC-KR"
            case .windows1252: return String(localized: "Windows 西欧")
            }
        }

        var foundation: String.Encoding {
            switch self {
            case .utf8, .utf8BOM: return .utf8
            case .utf16LE: return .utf16LittleEndian
            case .utf16BE: return .utf16BigEndian
            case .gb18030: return Self.cf(.GB_18030_2000)
            case .big5: return Self.cf(.big5)
            case .shiftJIS: return .shiftJIS
            case .eucKR: return Self.cf(.EUC_KR)
            case .windows1252: return .windowsCP1252
            }
        }

        /// 文件开头的 BOM
        var bom: [UInt8] {
            switch self {
            case .utf8BOM: return [0xEF, 0xBB, 0xBF]
            case .utf16LE: return [0xFF, 0xFE]
            case .utf16BE: return [0xFE, 0xFF]
            default: return []
            }
        }

        /// 能转成的几种
        static let targets: [Encoding] = [.utf8, .utf8BOM, .gb18030]

        /// 读文件时可以手动换成的几种
        static let readable: [Encoding] = [.utf8, .gb18030, .big5, .shiftJIS, .eucKR, .utf16LE, .utf16BE, .windows1252]

        private static func cf(_ encoding: CFStringEncodings) -> String.Encoding {
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
        }
    }

    enum LineEnding: String, Equatable {
        case lf
        case crlf
        case cr
        case mixed
        /// 只有一行
        case none

        var title: String {
            switch self {
            case .lf: return "LF"
            case .crlf: return "CRLF"
            case .cr: return "CR"
            case .mixed: return String(localized: "混用")
            case .none: return String(localized: "只有一行")
            }
        }
    }

    /// 换行转成什么
    enum LineTarget: String, CaseIterable, Identifiable {
        case keep
        case lf
        case crlf

        var id: String { rawValue }

        var title: String {
            switch self {
            case .keep: return String(localized: "不变")
            case .lf: return String(localized: "LF（Mac、Linux）")
            case .crlf: return String(localized: "CRLF（Windows）")
            }
        }
    }

    /// 太大的文件不转（多半不是手写的文本）
    static let maxBytes = 50_000_000

    /// 认得出来的文本文件：扩展名属于纯文本、源代码，或者是字幕、歌词、表格这些常见的文本格式
    static func isTextFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if ["txt", "csv", "tsv", "srt", "ass", "ssa", "vtt", "lrc", "cue", "nfo", "md", "log", "ini", "conf", "cfg", "properties",
            "json", "xml", "html", "htm", "yml", "yaml", "sql", "bat", "cmd", "ps1", "sh", "tex"].contains(ext) {
            return true
        }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .plainText) || type.conforms(to: .sourceCode)
    }

    // MARK: - 认编码

    /// 先看 BOM，再试 UTF-8，都不是时让系统在几种中日韩、西欧编码里挑最像的；都读不了时为 nil
    static func detect(_ data: Data) -> Encoding? {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: Encoding.utf8BOM.bom) { return .utf8BOM }
        if bytes.starts(with: Encoding.utf16LE.bom) { return .utf16LE }
        if bytes.starts(with: Encoding.utf16BE.bom) { return .utf16BE }
        if String(data: data, encoding: .utf8) != nil { return .utf8 }
        let candidates: [Encoding] = [.gb18030, .big5, .shiftJIS, .eucKR, .windows1252]
        var converted: NSString?
        var lossy: ObjCBool = false
        let raw = NSString.stringEncoding(for: data, encodingOptions: [
            .suggestedEncodingsKey: candidates.map { $0.foundation.rawValue },
            .useOnlySuggestedEncodingsKey: true,
            .allowLossyKey: false,
        ], convertedString: &converted, usedLossyConversion: &lossy)
        if raw != 0, !lossy.boolValue, let found = candidates.first(where: { $0.foundation.rawValue == raw }) {
            return found
        }
        return candidates.first { decode(data, as: $0) != nil }
    }

    /// 按某种编码读成文字（去掉开头的 BOM）；读不了时为 nil
    static func decode(_ data: Data, as encoding: Encoding) -> String? {
        var payload = data
        let bom = encoding.bom
        if !bom.isEmpty, [UInt8](data.prefix(bom.count)) == bom {
            payload = data.dropFirst(bom.count)
        } else if encoding == .utf8, [UInt8](data.prefix(3)) == Encoding.utf8BOM.bom {
            payload = data.dropFirst(3)
        }
        return String(data: Data(payload), encoding: encoding.foundation)
    }

    /// 文字存成某种编码（带上 BOM）；有存不下的字时为 nil
    static func encode(_ text: String, as encoding: Encoding) -> Data? {
        guard let body = text.data(using: encoding.foundation, allowLossyConversion: false) else { return nil }
        return Data(encoding.bom) + body
    }

    static func lineEnding(of text: String) -> LineEnding {
        var crlf = 0
        var lf = 0
        var cr = 0
        // 「\r\n」在 Swift 里是一个字符
        for scalar in text.unicodeScalars.indices {
            switch text.unicodeScalars[scalar] {
            case "\n":
                if scalar > text.unicodeScalars.startIndex, text.unicodeScalars[text.unicodeScalars.index(before: scalar)] == "\r" {
                    crlf += 1
                } else {
                    lf += 1
                }
            case "\r":
                let next = text.unicodeScalars.index(after: scalar)
                if next == text.unicodeScalars.endIndex || text.unicodeScalars[next] != "\n" {
                    cr += 1
                }
            default:
                break
            }
        }
        let kinds = [crlf > 0, lf > 0, cr > 0].filter { $0 }.count
        if kinds == 0 { return .none }
        if kinds > 1 { return .mixed }
        return crlf > 0 ? .crlf : (lf > 0 ? .lf : .cr)
    }

    /// 换行统一成 LF 或 CRLF
    static func normalize(_ text: String, to target: LineTarget) -> String {
        guard target != .keep else { return text }
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return target == .crlf ? unified.replacingOccurrences(of: "\n", with: "\r\n") : unified
    }

    /// 第一行不是空白的文字（卡片上预览，看读得对不对）
    static func firstLine(_ text: String, limit: Int = 80) -> String {
        let line = text.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }

    /// 转好的内容；读不了或者存不下时报错
    static func convert(_ data: Data, from source: Encoding, to target: Encoding, lines: LineTarget) throws -> Data {
        guard let text = decode(data, as: source) else {
            throw Failure(message: String(localized: "按 \(source.title) 读不出来"))
        }
        guard let converted = encode(normalize(text, to: lines), as: target) else {
            throw Failure(message: String(localized: "有的字 \(target.title) 存不下"))
        }
        return converted
    }
}
