import Foundation

/// 表格转换：从表格软件复制出来的文字（制表符分隔）、CSV、Markdown 表格互相转换，也能转成 JSON。纯逻辑，方便测试。
enum TableConverter {
    enum Format: String, CaseIterable {
        case markdown
        case csv
        case tsv
        case json

        var title: String {
            switch self {
            case .markdown: return "Markdown"
            case .csv: return "CSV"
            case .tsv: return String(localized: "制表符分隔")
            case .json: return "JSON"
            }
        }
    }

    struct Table: Equatable {
        /// 第一行当作表头
        var rows: [[String]]
        var source: Format
    }

    /// 至少两行两列、每行列数一样才算表格
    static func parse(_ text: String) -> Table? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .newlines)
        guard normalized.contains("\n") else { return nil }
        if let rows = parseMarkdown(normalized) {
            return Table(rows: rows, source: .markdown)
        }
        if normalized.contains("\t"), let rows = consistent(parseDelimited(normalized, separator: "\t")) {
            return Table(rows: rows, source: .tsv)
        }
        if normalized.contains(","), let rows = consistent(parseDelimited(normalized, separator: ",")) {
            return Table(rows: rows, source: .csv)
        }
        return nil
    }

    /// 转成其他格式（不含原来的格式）
    static func conversions(_ table: Table) -> [ResultCard.Row] {
        Format.allCases.filter { $0 != table.source }.map { format in
            ResultCard.Row(label: format.title, value: render(table.rows, as: format))
        }
    }

    static func render(_ rows: [[String]], as format: Format) -> String {
        switch format {
        case .markdown:
            guard let header = rows.first else { return "" }
            let escape: (String) -> String = { cell in
                cell.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
            }
            var lines = ["| " + header.map(escape).joined(separator: " | ") + " |",
                         "|" + header.map { _ in " --- " }.joined(separator: "|") + "|"]
            lines += rows.dropFirst().map { "| " + $0.map(escape).joined(separator: " | ") + " |" }
            return lines.joined(separator: "\n")
        case .csv:
            return rows.map { row in row.map(csvField).joined(separator: ",") }.joined(separator: "\n")
        case .tsv:
            return rows.map { row in
                row.map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
                    .joined(separator: "\t")
            }.joined(separator: "\n")
        case .json:
            guard let header = rows.first else { return "[]" }
            let objects = rows.dropFirst().map { row -> String in
                let pairs = header.enumerated().map { index, key in
                    "\(jsonString(key)): \(jsonString(index < row.count ? row[index] : ""))"
                }
                return "  {" + pairs.joined(separator: ", ") + "}"
            }
            return "[\n" + objects.joined(separator: ",\n") + "\n]"
        }
    }

    // MARK: - 解析

    /// | a | b |、|---|---|、| 1 | 2 | 这样的 Markdown 表格
    private static func parseMarkdown(_ text: String) -> [[String]]? {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 3, lines.allSatisfy({ $0.hasPrefix("|") || $0.contains("|") }),
              isSeparatorRow(lines[1]) else { return nil }
        let rows = ([lines[0]] + lines.dropFirst(2)).map(markdownCells)
        return consistent(rows)
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let cells = markdownCells(line)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" }
        }
    }

    private static func markdownCells(_ line: String) -> [String] {
        var body = line
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|"), !body.hasSuffix("\\|") { body.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in body {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// 按分隔符拆成表格，双引号里的分隔符、换行和 "" 按 CSV 的规则处理
    static func parseDelimited(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var characters = Array(text)[...]
        while let character = characters.popFirst() {
            if inQuotes {
                if character == "\"" {
                    if characters.first == "\"" {
                        field.append("\"")
                        characters.removeFirst()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" && field.isEmpty {
                inQuotes = true
            } else if character == separator {
                row.append(field)
                field = ""
            } else if character == "\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
        }
        row.append(field)
        rows.append(row)
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    /// 至少两行两列，并且每行的列数一样
    private static func consistent(_ rows: [[String]]) -> [[String]]? {
        guard rows.count >= 2, let columns = rows.first?.count, columns >= 2,
              rows.allSatisfy({ $0.count == columns }) else { return nil }
        return rows
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    private static func jsonString(_ value: String) -> String {
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return text
    }
}
