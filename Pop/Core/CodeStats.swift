import Foundation

/// 代码行数：按扩展名分语言，数文件数、行数和空行。隐藏文件夹（.git 这些）、node_modules 这类依赖和编译产物文件夹不算，
/// 锁文件、压缩过的 .min.js、看起来是二进制的文件和太大的文件（多半是生成的）也跳过。
enum CodeStats {
    struct Language: Equatable {
        var name: String
        var files = 0
        var lines = 0
        var blank = 0

        /// 不算空行
        var code: Int { lines - blank }
    }

    struct Result: Equatable {
        /// 按行数从多到少
        var languages: [Language]
        /// 跳过的太大或者二进制的文件
        var skipped: Int
        /// 文件太多，只数了前面一部分
        var truncated: Bool

        var files: Int { languages.reduce(0) { $0 + $1.files } }
        var lines: Int { languages.reduce(0) { $0 + $1.lines } }
        var blank: Int { languages.reduce(0) { $0 + $1.blank } }
    }

    static let maxFileSize = 2 * 1024 * 1024
    static let fileLimit = 50_000

    static let languages: [String: String] = [
        "swift": "Swift", "m": "Objective-C", "mm": "Objective-C++", "c": "C", "h": "C/C++ 头文件", "cc": "C++", "cpp": "C++",
        "cxx": "C++", "hpp": "C/C++ 头文件", "hh": "C/C++ 头文件", "cs": "C#", "java": "Java", "kt": "Kotlin", "kts": "Kotlin",
        "scala": "Scala", "groovy": "Groovy", "gradle": "Gradle", "go": "Go", "rs": "Rust", "zig": "Zig", "dart": "Dart",
        "js": "JavaScript", "jsx": "JavaScript", "mjs": "JavaScript", "cjs": "JavaScript", "ts": "TypeScript", "tsx": "TypeScript",
        "mts": "TypeScript", "vue": "Vue", "svelte": "Svelte", "html": "HTML", "htm": "HTML", "css": "CSS", "scss": "SCSS",
        "sass": "Sass", "less": "Less", "py": "Python", "pyi": "Python", "rb": "Ruby", "php": "PHP", "pl": "Perl", "pm": "Perl",
        "lua": "Lua", "r": "R", "jl": "Julia", "ex": "Elixir", "exs": "Elixir", "erl": "Erlang", "hs": "Haskell", "ml": "OCaml",
        "clj": "Clojure", "fs": "F#", "nim": "Nim", "sh": "Shell", "bash": "Shell", "zsh": "Shell", "fish": "Shell",
        "ps1": "PowerShell", "bat": "批处理", "sql": "SQL", "graphql": "GraphQL", "proto": "Protocol Buffers", "tf": "Terraform",
        "json": "JSON", "yaml": "YAML", "yml": "YAML", "toml": "TOML", "xml": "XML", "plist": "XML", "md": "Markdown",
        "markdown": "Markdown", "rst": "reStructuredText", "tex": "TeX", "vim": "Vim script", "asm": "汇编", "s": "汇编",
        "metal": "Metal", "glsl": "GLSL", "cmake": "CMake",
    ]

    /// 没有扩展名、按文件名认的
    static let fileNames: [String: String] = [
        "Makefile": "Makefile", "makefile": "Makefile", "GNUmakefile": "Makefile", "Dockerfile": "Dockerfile",
        "CMakeLists.txt": "CMake", "Podfile": "Ruby", "Gemfile": "Ruby", "Rakefile": "Ruby", "Fastfile": "Ruby",
        "Brewfile": "Ruby", "Jenkinsfile": "Groovy", "Vagrantfile": "Ruby",
    ]

    /// 生成的文件，不算
    static let generated: Set<String> = [
        "package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock", "Package.resolved", "Cargo.lock",
        "Gemfile.lock", "Podfile.lock", "composer.lock", "poetry.lock", "go.sum",
    ]

    static func language(of url: URL) -> String? {
        let name = url.lastPathComponent
        if let language = fileNames[name] {
            return language
        }
        guard !generated.contains(name), !name.hasSuffix(".min.js"), !name.hasSuffix(".min.css") else { return nil }
        return languages[url.pathExtension.lowercased()]
    }

    /// 行数和其中的空行（只有空格、制表符的也算空行）；看起来是二进制的返回 nil
    static func count(_ data: Data) -> (lines: Int, blank: Int)? {
        guard !data.prefix(8000).contains(0) else { return nil }
        var lines = 0
        var blank = 0
        var lineHasText = false
        var lineHasBytes = false
        for byte in data {
            switch byte {
            case 0x0A:
                lines += 1
                if !lineHasText {
                    blank += 1
                }
                lineHasText = false
                lineHasBytes = false
            case 0x20, 0x09, 0x0D, 0x0C:
                lineHasBytes = true
            default:
                lineHasText = true
                lineHasBytes = true
            }
        }
        // 最后一行没有换行符
        if lineHasBytes {
            lines += 1
            if !lineHasText {
                blank += 1
            }
        }
        return (lines, blank)
    }

    static func scan(_ roots: [URL], isCancelled: () -> Bool = { false }) -> Result {
        var byName: [String: Language] = [:]
        var skipped = 0
        var seen = Set<String>()
        var truncated = false
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]
        rootLoop: for root in roots {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                            errorHandler: { _, _ in true })
            while let url = enumerator?.nextObject() as? URL {
                if isCancelled() { break rootLoop }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
                if values.isDirectory == true {
                    // node_modules、build 这类依赖和编译产物不进去
                    if FolderTree.collapsed.contains(url.lastPathComponent) {
                        enumerator?.skipDescendants()
                    }
                    continue
                }
                guard values.isRegularFile == true, let kind = language(of: url),
                      seen.insert(url.standardizedFileURL.path(percentEncoded: false)).inserted else { continue }
                guard (values.fileSize ?? 0) <= maxFileSize, let data = try? Data(contentsOf: url), let counted = count(data) else {
                    skipped += 1
                    continue
                }
                byName[kind, default: Language(name: kind)].files += 1
                byName[kind, default: Language(name: kind)].lines += counted.lines
                byName[kind, default: Language(name: kind)].blank += counted.blank
                if seen.count >= fileLimit {
                    truncated = true
                    break rootLoop
                }
            }
        }
        let languages = byName.values.sorted { lhs, rhs in
            if lhs.lines != rhs.lines {
                return lhs.lines > rhs.lines
            }
            return lhs.name < rhs.name
        }
        return Result(languages: languages, skipped: skipped, truncated: truncated)
    }

    /// Markdown 表格：语言、文件、行数、空行、代码行
    static func markdown(_ result: Result) -> String {
        var lines = ["| 语言 | 文件 | 行数 | 空行 | 代码行 |", "| --- | ---: | ---: | ---: | ---: |"]
        for language in result.languages {
            lines.append("| \(language.name) | \(language.files) | \(language.lines) | \(language.blank) | \(language.code) |")
        }
        lines.append("| 合计 | \(result.files) | \(result.lines) | \(result.blank) | \(result.lines - result.blank) |")
        return lines.joined(separator: "\n")
    }
}
