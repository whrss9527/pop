import CoreGraphics
import Vision

/// 识别图片里的表格：macOS 26 用系统的文档识别，按行列取出每个格子的文字；
/// 更早的系统没有这个接口，返回 nil，调用方退回普通的识别文字。
enum TableOCR {
    /// 这台 Mac 能不能按表格识别
    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return true
        }
        #endif
        return false
    }

    /// 图片里的每个表格（每行一个数组）；系统不支持时是 nil，没找到表格时是空数组
    static func tables(in image: CGImage) async throws -> [[[String]]]? {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let request = RecognizeDocumentsRequest()
            let observations = try await request.perform(on: image)
            return observations.flatMap { observation in
                observation.document.tables.map { table in
                    grid(table.rows.flatMap { $0 }.map { cell in
                        Cell(row: cell.rowRange.lowerBound, column: cell.columnRange.lowerBound,
                             text: cell.content.text.transcript)
                    })
                }
            }
        }
        #endif
        return nil
    }

    struct Cell: Equatable {
        var row: Int
        var column: Int
        var text: String
    }

    /// 按行列摆好；跨行跨列的格子只放在左上角，同一个格子出现多次只取一次
    static func grid(_ cells: [Cell]) -> [[String]] {
        let rows = (cells.map(\.row).max() ?? -1) + 1
        let columns = (cells.map(\.column).max() ?? -1) + 1
        guard rows > 0, columns > 0 else { return [] }
        var grid = Array(repeating: Array(repeating: "", count: columns), count: rows)
        var filled = Set<[Int]>()
        for cell in cells where cell.row >= 0 && cell.column >= 0 {
            guard filled.insert([cell.row, cell.column]).inserted else { continue }
            grid[cell.row][cell.column] = cell.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        // 去掉整行都是空的行
        return grid.filter { row in row.contains { !$0.isEmpty } }
    }

    /// 结果卡片：Markdown 表格、制表符分隔、CSV 三种写法切换
    static func card(for rows: [[String]], otherTables: Int = 0) -> ResultCard {
        let columns = rows.map(\.count).max() ?? 0
        let padded = rows.map { $0 + Array(repeating: "", count: columns - $0.count) }
        var detail = "\(padded.count) 行 × \(columns) 列"
        if otherTables > 0 {
            detail += "；图片里还有 \(otherTables) 个表格，这里只显示第一个"
        }
        return ResultCard(title: "识别表格", detail: detail, tabs: [
            ResultCard.Tab(title: "Markdown", text: TableConverter.render(padded, as: .markdown)),
            ResultCard.Tab(title: "制表符分隔", text: TableConverter.render(padded, as: .tsv)),
            ResultCard.Tab(title: "CSV", text: TableConverter.render(padded, as: .csv)),
        ])
    }
}
