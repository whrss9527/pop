import Foundation

/// 一列（或者一行）数字的合计、平均、中位数、最大、最小。
enum NumberStats {
    struct Summary: Equatable {
        var values: [Double]
        /// 输入里最多有几位小数，合计、最大、最小按它显示
        var decimals: Int

        var count: Int { values.count }
        var sum: Double { values.reduce(0, +) }
        var average: Double { sum / Double(max(count, 1)) }
        var minimum: Double { values.min() ?? 0 }
        var maximum: Double { values.max() ?? 0 }

        var median: Double {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return 0 }
            let middle = sorted.count / 2
            return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        }

        var rows: [ResultCard.Row] {
            let precise = min(decimals + 2, 6)
            return [
                ResultCard.Row(label: String(localized: "合计"), value: NumberStats.format(sum, decimals: decimals)),
                ResultCard.Row(label: String(localized: "平均"), value: NumberStats.format(average, decimals: precise)),
                ResultCard.Row(label: String(localized: "中位数"), value: NumberStats.format(median, decimals: precise)),
                ResultCard.Row(label: String(localized: "最大"), value: NumberStats.format(maximum, decimals: decimals)),
                ResultCard.Row(label: String(localized: "最小"), value: NumberStats.format(minimum, decimals: decimals)),
                ResultCard.Row(label: String(localized: "个数"), value: "\(count)"),
            ]
        }
    }

    /// 一个数：可以带正负号、千分位逗号、小数
    private static let number = try! NSRegularExpression(pattern: #"(?<![\d.])[-+]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?(?!\d)"#)
    /// 一行里数和数之间只能有这些：空白、逗号、分号、顿号、竖线、加号、货币符号、百分号
    private static let separators = CharacterSet(charactersIn: " \t,，;；、|+¥$€£%")

    /// 多行时每行取最后一个数（「苹果 12」「3 月 1,200」），要有八成以上的行带数；
    /// 一行时整行只能是数和分隔符。少于两个数返回 nil
    static func parse(_ text: String) -> Summary? {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var tokens: [String] = []
        if lines.count >= 2 {
            let found = lines.compactMap { numbers(in: $0).last }
            guard found.count >= 2, Double(found.count) >= Double(lines.count) * 0.8 else { return nil }
            tokens = found
        } else if let line = lines.first {
            tokens = numbers(in: line)
            var rest = line
            for token in tokens {
                if let range = rest.range(of: token) {
                    rest.removeSubrange(range)
                }
            }
            guard rest.unicodeScalars.allSatisfy(separators.contains) else { return nil }
        }
        let values = tokens.compactMap { Double($0.replacingOccurrences(of: ",", with: "")) }
        guard values.count >= 2, values.count == tokens.count else { return nil }
        let decimals = tokens.map { token in token.split(separator: ".").dropFirst().first?.count ?? 0 }.max() ?? 0
        return Summary(values: values, decimals: min(decimals, 6))
    }

    static func numbers(in line: String) -> [String] {
        let range = NSRange(line.startIndex..., in: line)
        return number.matches(in: line, range: range).compactMap { match in
            Range(match.range, in: line).map { String(line[$0]) }
        }
    }

    static func format(_ value: Double, decimals: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
