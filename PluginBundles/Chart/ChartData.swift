import Foundation
@testable import Pop

/// 生成图表：从选中的文字里认出要画的数据。表格（表格软件里复制的、CSV、Markdown 表格）、
/// 一行一个「名字 数值」（「苹果 12」「一月：1,200 元」），或者一串数（「12, 15, 9」）。纯逻辑，方便测试。
enum ChartData {
    struct Series: Equatable {
        var name: String
        var values: [Double]
    }

    struct Dataset: Equatable {
        var labels: [String]
        var series: [Series]
        /// 标签那一列的表头，比如「月份」
        var labelTitle: String?
        /// 数值都带着同一个单位时记下来：%、元、kg、¥
        var unit: String?
        /// 输入里最多有几位小数，显示数值时按它
        var decimals: Int

        var hasNegative: Bool { series.contains { $0.values.contains { $0 < 0 } } }
    }

    enum Kind: String, CaseIterable, Identifiable {
        case bar, horizontal, line, pie

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bar: return String(localized: "柱状图")
            case .horizontal: return String(localized: "条形图")
            case .line: return String(localized: "折线图")
            case .pie: return String(localized: "饼图")
            }
        }
    }

    /// 最多画这么多行、这么多组
    static let maxRows = 500
    static let maxSeries = 6

    // MARK: - 数

    struct Number: Equatable {
        var value: Double
        var unit: String?
        var decimals: Int
    }

    private static let numberPattern = try! NSRegularExpression(
        pattern: #"^([-+−]?)([¥￥$€£]?)\s*([-+−]?)(\d{1,3}(?:[,，]\d{3})+|\d+)(?:\.(\d+))?\s*(%|‰|万|亿|[kK](?![A-Za-z])|[A-Za-z°℃\p{Han}]{1,4})?$"#)

    /// 一个数：可以带正负号、千分位、小数、货币符号、百分号，「1.2万」「3亿」「12k」，后面跟一个短的单位（元、kg、人）；
    /// 会计写法的「(1,200)」是负数
    static func number(_ raw: String) -> Number? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 24 else { return nil }
        var negative = false
        if text.hasPrefix("("), text.hasSuffix(")") {
            negative = true
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        let string = text as NSString
        guard let match = numberPattern.firstMatch(in: text, range: NSRange(location: 0, length: string.length)) else { return nil }
        func group(_ index: Int) -> String {
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : string.substring(with: range)
        }
        let signs = group(1) + group(3)
        if signs.contains("-") || signs.contains("−") {
            negative.toggle()
        }
        let digits = group(4).replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "")
        let fraction = group(5)
        guard var value = Double(fraction.isEmpty ? digits : digits + "." + fraction) else { return nil }
        var unit: String? = group(2).isEmpty ? nil : group(2)
        var decimals = fraction.count
        switch group(6) {
        case "":
            break
        case "万":
            value *= 10_000
            decimals = max(decimals - 4, 0)
        case "亿":
            value *= 100_000_000
            decimals = max(decimals - 8, 0)
        case "k", "K":
            value *= 1000
            decimals = max(decimals - 3, 0)
        case let suffix:
            unit = unit ?? suffix
        }
        if unit == "￥" {
            unit = "¥"
        }
        return Number(value: negative ? -value : value, unit: unit, decimals: min(decimals, 4))
    }

    // MARK: - 认数据

    /// 认不出能画的数据时为 nil
    static func parse(_ text: String) -> Dataset? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 20_000 else { return nil }
        if let table = TableConverter.parse(trimmed), let dataset = fromTable(table.rows) {
            return dataset
        }
        return fromLines(trimmed) ?? fromList(trimmed)
    }

    /// 表格：第一行是不是表头、哪一列是名字、哪几列是数
    static func fromTable(_ rows: [[String]]) -> Dataset? {
        let width = rows.map(\.count).max() ?? 0
        guard rows.count >= 2, width >= 1 else { return nil }
        let cells = rows.map { row in (0..<width).map { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : "" } }
        func ratio(_ column: Int, in body: ArraySlice<[String]>) -> Double {
            let filled = body.map { $0[column] }.filter { !$0.isEmpty }
            guard !filled.isEmpty else { return 0 }
            return Double(filled.filter { number($0) != nil }.count) / Double(filled.count)
        }
        // 某一列下面都是数、第一行这一格却不是数：第一行是表头
        let hasHeader = (0..<width).contains { column in
            ratio(column, in: cells.dropFirst()) >= 0.8 && number(cells[0][column]) == nil && !cells[0][column].isEmpty
        }
        let body = hasHeader ? cells.dropFirst() : cells[...]
        guard body.count >= 2, body.count <= maxRows else { return nil }
        let numeric = (0..<width).filter { ratio($0, in: body) >= 0.8 }
        guard !numeric.isEmpty else { return nil }
        // 「1月」「2024」也算数（带单位的数、年份），名字那一列这样找：第一个不全是数的列；
        // 都是数的话，年份、月份、季度这类的列；再没有就第一列（序号）
        func isTime(_ column: Int) -> Bool {
            isTimeColumn(body.map { $0[column] })
        }
        var labelColumn = (0..<width).first { !numeric.contains($0) }
        if labelColumn == nil, width >= 2 {
            labelColumn = (0..<width).first(where: isTime) ?? 0
        }
        var valueColumns = numeric.filter { $0 != labelColumn }
        // 名字在别的列里时，年份、月份这类的列不当成一组数
        if valueColumns.contains(where: { !isTime($0) }) {
            valueColumns.removeAll(where: isTime)
        }
        guard !valueColumns.isEmpty else { return nil }
        var numbers: [Number] = []
        let series = valueColumns.prefix(maxSeries).enumerated().map { index, column -> Series in
            let values = body.map { row -> Double in
                guard let parsed = number(row[column]) else { return 0 }
                numbers.append(parsed)
                return parsed.value
            }
            let name = hasHeader && !cells[0][column].isEmpty ? cells[0][column] : defaultSeriesName(index, count: valueColumns.count)
            return Series(name: name, values: values)
        }
        let labels = body.enumerated().map { index, row -> String in
            guard let labelColumn, !row[labelColumn].isEmpty else { return String(index + 1) }
            return row[labelColumn]
        }
        let labelTitle = hasHeader ? labelColumn.map { cells[0][$0] }.flatMap { $0.isEmpty ? nil : $0 } : nil
        let names = uniqued(series.map(\.name))
        return Dataset(labels: uniqued(labels), series: zip(series, names).map { Series(name: $1, values: $0.values) },
                       labelTitle: labelTitle, unit: commonUnit(numbers), decimals: numbers.map(\.decimals).max() ?? 0)
    }

    private static let trailingNumber = try! NSRegularExpression(
        pattern: #"^(.*?)[\s:：,，=]*(\(?[-+−]?[¥￥$€£]?\s*[-+−]?\d[\d,，]*(?:\.\d+)?\s*(?:%|‰|万|亿|[kK](?![A-Za-z])|[A-Za-z°℃\p{Han}]{1,4})?\)?)$"#)

    /// 一行一个「名字 数值」：每行取最后一个数，前面的是名字；第一行没有数的话当标题
    static func fromLines(_ text: String) -> Dataset? {
        var lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // 两行的「a = 1」这类多半不是要画图的数据
        guard lines.count >= 3, lines.count <= maxRows + 1 else { return nil }
        var title: String?
        if pair(lines[0]) == nil {
            title = lines.removeFirst()
        }
        let pairs = lines.map(pair)
        let found = pairs.compactMap { $0 }
        guard found.count >= 2, Double(found.count) >= Double(lines.count) * 0.8 else { return nil }
        let labels = found.enumerated().map { index, pair in pair.label.isEmpty ? String(index + 1) : pair.label }
        let numbers = found.map(\.number)
        return Dataset(labels: uniqued(labels), series: [Series(name: title ?? String(localized: "数值"), values: numbers.map(\.value))],
                       labelTitle: nil, unit: commonUnit(numbers), decimals: numbers.map(\.decimals).max() ?? 0)
    }

    private static func pair(_ line: String) -> (label: String, number: Number)? {
        let string = line as NSString
        guard let match = trailingNumber.firstMatch(in: line, range: NSRange(location: 0, length: string.length)),
              let parsed = number(string.substring(with: match.range(at: 2))) else { return nil }
        let label = string.substring(with: match.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: " \t:：,，=-—"))
        return (label, parsed)
    }

    /// 一行里的一串数：「12, 15, 9, 20」「12 15 9 20」
    static func fromList(_ text: String) -> Dataset? {
        guard !text.contains(where: \.isNewline) else { return nil }
        let tokens = text.split(whereSeparator: { " \t、;；|".contains($0) || $0 == "," || $0 == "，" }).map(String.init)
        // 「138 0013 8000」是电话号码，「2022 2023 2024」「1月 2月 3月」是日子，都不是要画的数
        guard !tokens.contains(where: { $0.first == "0" && $0.dropFirst().first?.isNumber == true }), !isTimeColumn(tokens) else { return nil }
        let numbers = tokens.compactMap(number)
        guard numbers.count >= 3, numbers.count == tokens.count, numbers.count <= maxRows else { return nil }
        return Dataset(labels: numbers.indices.map { String($0 + 1) }, series: [Series(name: String(localized: "数值"), values: numbers.map(\.value))],
                       labelTitle: nil, unit: commonUnit(numbers), decimals: numbers.map(\.decimals).max() ?? 0)
    }

    /// 名字重了的在后面加 2、3：图表按名字分格子，重名的会叠在一起
    static func uniqued(_ names: [String]) -> [String] {
        var seen: [String: Int] = [:]
        var used = Set(names)
        return names.map { name in
            let count = (seen[name] ?? 0) + 1
            seen[name] = count
            guard count > 1 else { return name }
            var candidate = "\(name) \(count)"
            var next = count
            while used.contains(candidate) {
                next += 1
                candidate = "\(name) \(next)"
            }
            used.insert(candidate)
            return candidate
        }
    }

    private static func defaultSeriesName(_ index: Int, count: Int) -> String {
        count == 1 ? String(localized: "数值") : String(localized: "第 \(index + 1) 组")
    }

    private static func commonUnit(_ numbers: [Number]) -> String? {
        let units = Set(numbers.map(\.unit))
        return units.count == 1 ? units.first ?? nil : nil
    }

    /// 一列都是年份、月份、季度、日期、星期（空格不算）
    private static func isTimeColumn(_ values: [String]) -> Bool {
        let filled = values.filter { !$0.isEmpty }
        return !filled.isEmpty && filled.allSatisfy { value in
            timeline.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) != nil
        }
    }

    // MARK: - 画成什么

    private static let timeline = try! NSRegularExpression(
        pattern: #"^(?:(?:19|20)\d{2}(?:年|\s*[Qq][1-4]|[-/.年]\d{1,2}(?:月|[-/.]\d{1,2}日?)?)?|\d{1,2}月(?:份|\d{1,2}[日号])?|[Qq][1-4]|第[一二三四1-4]季度|(?:周|星期)[一二三四五六日天]|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?|(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\.?|\d{1,2}[/-]\d{1,2})$"#,
        options: [.caseInsensitive])

    /// 名字都是年份、月份、季度、日期、星期：按时间排的，默认画折线
    static func looksLikeTimeline(_ labels: [String]) -> Bool {
        labels.count >= 3 && labels.allSatisfy { label in
            timeline.firstMatch(in: label, range: NSRange(location: 0, length: (label as NSString).length)) != nil
        }
    }

    /// 能画的样子：饼图只给一组、没有负数、不超过 12 块的数据
    static func kinds(for dataset: Dataset) -> [Kind] {
        let total = dataset.series.first?.values.reduce(0, +) ?? 0
        let pie = dataset.series.count == 1 && !dataset.hasNegative && total > 0 && dataset.labels.count <= 12
        return Kind.allCases.filter { $0 != .pie || pie }
    }

    /// 先画成什么：按时间排的画折线；名字长或者很多的画条形图；其他画柱状图
    static func suggestedKind(for dataset: Dataset) -> Kind {
        if looksLikeTimeline(dataset.labels) {
            return .line
        }
        if dataset.labels.count > 12 || (dataset.labels.map(\.count).max() ?? 0) > 8 {
            return .horizontal
        }
        return .bar
    }

    /// 按第一组数从大到小排
    static func sortedDescending(_ dataset: Dataset) -> Dataset {
        guard let first = dataset.series.first else { return dataset }
        let order = first.values.indices.sorted { a, b in
            first.values[a] != first.values[b] ? first.values[a] > first.values[b] : a < b
        }
        var sorted = dataset
        sorted.labels = order.map { dataset.labels[$0] }
        sorted.series = dataset.series.map { series in
            Series(name: series.name, values: order.map { series.values[$0] })
        }
        return sorted
    }

    // MARK: - 写法

    /// 「1,200」「12.5%」「¥3,000」「36 kg」「120元」
    static func format(_ value: Double, decimals: Int, unit: String?) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = decimals
        let text = formatter.string(from: NSNumber(value: abs(value))) ?? String(abs(value))
        let sign = value < 0 ? "-" : ""
        guard let unit else { return sign + text }
        if ["¥", "$", "€", "£"].contains(unit) {
            return sign + unit + text
        }
        if unit == "%" || unit == "‰" || unit.unicodeScalars.contains(where: { $0.properties.isIdeographic }) {
            return sign + text + unit
        }
        return sign + text + " " + unit
    }

    /// 饼图上每块占多少：「35%」「12.5%」
    static func percentText(_ value: Double, total: Double) -> String {
        guard total > 0 else { return "0%" }
        let percent = value / total * 100
        return percent >= 10 || percent == percent.rounded() ? "\(Int(percent.rounded()))%" : String(format: "%.1f%%", percent)
    }
}
