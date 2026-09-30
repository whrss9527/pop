import Foundation
import UniformTypeIdentifiers

/// 对比两个文本文件：读成文字（UTF-8 读不了再按 UTF-16、GB18030 试），按修改时间把旧的当作原文
enum FileDiff {
    struct Failure: LocalizedError, Equatable {
        let message: String

        var errorDescription: String? { message }
    }

    /// 每个文件最多这么多字（和「文本对比」的上限一样），再多逐行比较太慢
    static let maxCharacters = 300_000
    /// 文件超过这么大就不读了
    static let maxBytes = 4_000_000

    /// 看起来是文本文件：扩展名是文本类（代码、Markdown、JSON、CSV……）；
    /// 没有扩展名或者系统不认识的扩展名，就看开头一段能不能按 UTF-8 读、里面有没有 0 字节
    static func isTextFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty, let type = UTType(filenameExtension: pathExtension), !type.isDynamic {
            return type.conforms(to: .text)
        }
        return looksLikeText(url)
    }

    /// 开头 8 KB 里没有 0 字节，并且能按 UTF-8 读（截在一个字中间的不算错）
    static func looksLikeText(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8192), !data.isEmpty else { return true }
        guard !data.contains(0) else { return false }
        return (0...3).contains { trim in data.count > trim && String(data: data.dropLast(trim), encoding: .utf8) != nil }
    }

    /// 读成文字；太大或者不是文字时抛出原因
    static func read(_ url: URL) throws -> String {
        let name = url.lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxBytes else { throw Failure(message: String(localized: "「\(name)」太大了，只能对比 30 万字以内的文本文件")) }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Failure(message: String(localized: "读不了「\(name)」：\(error.localizedDescription)"))
        }
        guard let text = decode(data) else { throw Failure(message: String(localized: "「\(name)」不是文本文件，没法对比")) }
        guard text.count <= maxCharacters else { throw Failure(message: String(localized: "「\(name)」太大了，只能对比 30 万字以内的文本文件")) }
        return text
    }

    /// UTF-8（带不带 BOM 都行）、带 BOM 的 UTF-16，都不是时按 GB18030 试（Windows 上存的中文文件）
    static func decode(_ data: Data) -> String? {
        guard !data.isEmpty else { return "" }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        guard !data.contains(0) else { return nil }
        if let text = String(data: data, encoding: .utf8) {
            return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb18030))
    }

    /// 按修改时间排好：旧的在前；时间一样时按选中的顺序
    static func ordered(_ first: URL, _ second: URL) -> (old: URL, new: URL) {
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return modified(second) < modified(first) ? (second, first) : (first, second)
    }

    static func card(old: URL, new: URL, result: TextDiff.Result) -> ResultCard {
        let oldName = old.lastPathComponent
        let newName = new.lastPathComponent
        return ResultCard(title: String(localized: "对比文件"),
                          detail: String(localized: "「\(oldName)」→「\(newName)」（旧的在前）：删去 \(result.removedCount) 行，新增 \(result.addedCount) 行"),
                          copyText: result.unifiedText, diff: result)
    }
}
