import AppKit
import Foundation
@testable import Pop

/// 新建文件：在文件夹里新建一个空白文件（Markdown 带上标题、HTML 是一个最简单的网页、Shell 脚本带上 #! 并且可以直接运行），
/// 或者把选中的文字、剪贴板里的文字和图片存成文件。
enum NewFileMaker {
    struct Failure: Error, Equatable {
        let message: String
    }

    enum Kind: String, CaseIterable, Identifiable {
        case text
        case markdown
        case rtf
        case json
        case html
        case csv
        case python
        case shell

        var id: String { rawValue }

        var ext: String {
            switch self {
            case .text: return "txt"
            case .markdown: return "md"
            case .rtf: return "rtf"
            case .json: return "json"
            case .html: return "html"
            case .csv: return "csv"
            case .python: return "py"
            case .shell: return "sh"
            }
        }

        var title: String {
            switch self {
            case .text: return String(localized: "纯文本")
            case .markdown: return "Markdown"
            case .rtf: return String(localized: "富文本")
            case .json: return "JSON"
            case .html: return "HTML"
            case .csv: return "CSV"
            case .python: return "Python"
            case .shell: return String(localized: "Shell 脚本")
            }
        }

        /// 扩展名对应的种类（不分大小写；.markdown、.htm 这些也认）
        static func of(extension ext: String) -> Kind? {
            switch ext.lowercased() {
            case "txt", "text": return .text
            case "md", "markdown": return .markdown
            case "rtf": return .rtf
            case "json": return .json
            case "html", "htm": return .html
            case "csv": return .csv
            case "py": return .python
            case "sh", "command", "zsh", "bash": return .shell
            default: return nil
            }
        }
    }

    /// 文件里放什么
    enum Content: Equatable {
        case blank
        case text(String)
        /// PNG
        case image(Data)
    }

    /// 没起名字时叫什么
    static var untitled: String {
        String(localized: "未命名")
    }

    /// 文件内容。title 是不带扩展名的文件名（Markdown 的标题、网页的标题用它）
    static func data(kind: Kind?, content: Content, title: String) -> Data {
        switch content {
        case .image(let png):
            return png
        case .text(let text):
            guard kind == .rtf else { return Data(text.utf8) }
            return rtf(text)
        case .blank:
            switch kind {
            case .markdown:
                return Data("# \(title)\n\n".utf8)
            case .html:
                return Data("""
                <!doctype html>
                <html>
                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1">
                  <title>\(escapeHTML(title))</title>
                </head>
                <body>

                </body>
                </html>

                """.utf8)
            case .json:
                return Data("{}\n".utf8)
            case .shell:
                return Data("#!/bin/bash\n\n".utf8)
            case .rtf:
                return rtf("")
            default:
                return Data()
            }
        }
    }

    /// 文字存成 RTF（系统字体 13 号）
    static func rtf(_ text: String) -> Data {
        let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        return (try? string.data(from: NSRange(location: 0, length: string.length),
                                 documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// 用户写的名字整理成文件名：去掉首尾空白和不能用的「/」「:」，空的叫「未命名」，没写扩展名时补上 ext
    static func fileName(_ typed: String, ext: String) -> String {
        var name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        // 不新建隐藏文件
        while name.hasPrefix(".") {
            name.removeFirst()
        }
        if name.isEmpty { name = untitled }
        if (name as NSString).pathExtension.isEmpty {
            name += "." + ext
        }
        return name
    }

    /// 写进文件夹；同名的已经有了就在后面加 2、3。Shell 脚本可以直接运行
    static func create(in folder: URL, name: String, data: Data, executable: Bool = false) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let url = FileNames.available(in: folder, base: base, extension: ext.isEmpty ? nil : ext)
        do {
            try data.write(to: url, options: .withoutOverwriting)
            if executable {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
            }
        } catch {
            throw Failure(message: String(localized: "没能在「\(folder.lastPathComponent)」里新建文件：\(error.localizedDescription)"))
        }
        return url
    }

    /// 访达最前面的窗口正在看的文件夹；没有窗口、看的不是文件夹或者不让问时为 nil
    @MainActor static func frontFinderFolder() -> URL? {
        let source = """
        tell application "Finder"
            if (count of Finder windows) is 0 then return ""
            return POSIX path of (target of front Finder window as alias)
        end tell
        """
        var error: NSDictionary?
        guard let path = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
