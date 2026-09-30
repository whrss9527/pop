import Foundation

/// 解读 5 段式 cron 表达式（分 时 日 月 周），说成中文，并算出接下来几次运行的时间。
struct CronExpression: Equatable {
    /// 每一段允许的值
    var minutes: Set<Int>
    var hours: Set<Int>
    var days: Set<Int>
    var months: Set<Int>
    /// 0 是周日
    var weekdays: Set<Int>
    /// 「日」「周」两段是不是写了 *（都限定时，满足其中一个就运行）
    var anyDay: Bool
    var anyWeekday: Bool
    /// 原来的每一段，描述时用
    var fields: [String]

    private static let macros = [
        "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *", "@weekly": "0 0 * * 0",
        "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@hourly": "0 * * * *",
    ]
    private static let monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    private static let weekdayNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let expanded = Self.macros[trimmed.lowercased()] {
            trimmed = expanded
        }
        let fields = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard fields.count == 5 else { return nil }
        guard let minutes = Self.values(fields[0], range: 0...59),
              let hours = Self.values(fields[1], range: 0...23),
              let days = Self.values(fields[2], range: 1...31),
              let months = Self.values(fields[3], range: 1...12, names: Self.monthNames, firstName: 1),
              var weekdays = Self.values(fields[4], range: 0...7, names: Self.weekdayNames, firstName: 0) else { return nil }
        // 7 也是周日
        if weekdays.remove(7) != nil {
            weekdays.insert(0)
        }
        self.minutes = minutes
        self.hours = hours
        self.days = days
        self.months = months
        self.weekdays = weekdays
        anyDay = fields[2] == "*" || fields[2] == "?"
        anyWeekday = fields[4] == "*" || fields[4] == "?"
        self.fields = fields
    }

    /// 一段里的值：* ? a a-b */n a-b/n a/n，用逗号隔开；月和周可以写英文缩写
    private static func values(_ field: String, range: ClosedRange<Int>, names: [String] = [], firstName: Int = 0) -> Set<Int>? {
        var result = Set<Int>()
        for part in field.split(separator: ",", omittingEmptySubsequences: false) {
            let pieces = part.split(separator: "/", omittingEmptySubsequences: false)
            guard pieces.count <= 2, let base = pieces.first, !base.isEmpty else { return nil }
            var step = 1
            if pieces.count == 2 {
                guard let value = Int(pieces[1]), value > 0 else { return nil }
                step = value
            }
            let lower: Int
            let upper: Int
            if base == "*" || base == "?" {
                lower = range.lowerBound
                upper = range.upperBound
            } else {
                let bounds = base.split(separator: "-", omittingEmptySubsequences: false)
                guard bounds.count <= 2, let start = number(bounds[0], names: names, firstName: firstName) else { return nil }
                lower = start
                if bounds.count == 2 {
                    guard let end = number(bounds[1], names: names, firstName: firstName) else { return nil }
                    upper = end
                } else {
                    // a/n 表示从 a 开始每隔 n
                    upper = pieces.count == 2 ? range.upperBound : start
                }
            }
            guard range.contains(lower), range.contains(upper), lower <= upper else { return nil }
            result.formUnion(stride(from: lower, through: upper, by: step))
        }
        return result.isEmpty ? nil : result
    }

    private static func number(_ text: Substring, names: [String], firstName: Int) -> Int? {
        if let value = Int(text) { return value }
        guard let index = names.firstIndex(of: text.uppercased()) else { return nil }
        return index + firstName
    }

    // MARK: - 什么时候运行

    func matches(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
        guard let minute = parts.minute, let hour = parts.hour, let day = parts.day, let month = parts.month,
              let weekday = parts.weekday else { return false }
        return minutes.contains(minute) && hours.contains(hour) && months.contains(month) && dayMatches(day, weekday - 1)
    }

    /// 日和周都限定时满足其中一个就算（和 cron 的规矩一样）
    private func dayMatches(_ day: Int, _ weekday: Int) -> Bool {
        switch (anyDay, anyWeekday) {
        case (true, true): return true
        case (false, true): return days.contains(day)
        case (true, false): return weekdays.contains(weekday)
        case (false, false): return days.contains(day) || weekdays.contains(weekday)
        }
    }

    /// after 之后接下来的 count 次（最多往后找 5 年）
    func nextRuns(after start: Date, count: Int, calendar: Calendar) -> [Date] {
        var results: [Date] = []
        guard var day = calendar.dateInterval(of: .day, for: start)?.start else { return [] }
        let sortedHours = hours.sorted()
        let sortedMinutes = minutes.sorted()
        for _ in 0..<(366 * 5) {
            let parts = calendar.dateComponents([.day, .month, .weekday], from: day)
            if let dayOfMonth = parts.day, let month = parts.month, let weekday = parts.weekday,
               months.contains(month), dayMatches(dayOfMonth, weekday - 1) {
                for hour in sortedHours {
                    for minute in sortedMinutes {
                        guard let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                              date > start else { continue }
                        results.append(date)
                        if results.count == count { return results }
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return results
    }

    // MARK: - 说成中文

    /// 用界面的语言说出这个表达式什么时候运行
    var summary: String {
        Localization.isChinese ? chineseSummary : englishSummary
    }

    var chineseSummary: String {
        let when = dayDescription
        let time = timeDescription
        // 每天都运行、时间又是「每……」开头的，不用再说「每天」
        if when == "每天", time.hasPrefix("每") {
            return time
        }
        return "\(when) \(time)"
    }

    /// 哪些天：每天、每个工作日、每月 1 日、1 月 1 日……
    private var dayDescription: String {
        let monthText = fields[3] == "*" ? nil : Self.list(months, unit: " 月")
        let dayText = Self.list(days, unit: " 日")
        switch (anyDay, anyWeekday) {
        case (true, true):
            return monthText.map { "\($0)的每天" } ?? "每天"
        case (false, true):
            return monthText.map { "\($0) \(dayText)" } ?? "每月 \(dayText)"
        case (true, false):
            return monthText.map { "\($0)的每\(weekdayDescription)" } ?? "每\(weekdayDescription)"
        case (false, false):
            return (monthText.map { "\($0) " } ?? "每月 ") + "\(dayText)和每\(weekdayDescription)"
        }
    }

    private var weekdayDescription: String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        // 周一排在最前面，周日排在最后
        let sorted = weekdays.sorted { ($0 == 0 ? 7 : $0) < ($1 == 0 ? 7 : $1) }
        if sorted == [1, 2, 3, 4, 5] { return "个工作日（周一到周五）" }
        if sorted == [6, 0] { return "个周末" }
        if sorted.count > 2, Self.isRange(sorted.map { $0 == 0 ? 7 : $0 }), let first = sorted.first, let last = sorted.last {
            return "\(names[first])到\(names[last])"
        }
        return sorted.map { names[$0] }.joined(separator: "、")
    }

    /// 几点几分：09:30、每小时的整点、每 15 分钟、9 点到 18 点每 30 分钟……
    private var timeDescription: String {
        // 一天里只有几个固定的时刻：直接列出来
        if minutes.count == 1, hours.count <= 6, let minute = minutes.first {
            return hours.sorted().map { String(format: "%02d:%02d", $0, minute) }.joined(separator: "、")
        }
        let minuteField = fields[0]
        let minutePart: String
        if minuteField == "*" {
            minutePart = "每分钟"
        } else if minuteField.hasPrefix("*/"), let step = Int(minuteField.dropFirst(2)) {
            minutePart = "每 \(step) 分钟"
        } else if minutes == [0] {
            minutePart = "整点"
        } else {
            minutePart = "第 " + Self.list(minutes, unit: "") + " 分钟"
        }
        let everyMinute = minutePart.hasPrefix("每")
        if hours.count == 24 {
            return everyMinute ? minutePart : "每小时的\(minutePart)"
        }
        let hourField = fields[1]
        let hourPart: String
        if hourField.hasPrefix("*/"), let step = Int(hourField.dropFirst(2)) {
            hourPart = "每 \(step) 小时"
        } else if hours.count > 2, Self.isRange(hours.sorted()), let first = hours.min(), let last = hours.max() {
            hourPart = "\(first) 点到 \(last) 点"
        } else {
            hourPart = Self.list(hours, unit: " 点")
        }
        return everyMinute ? "\(hourPart)\(minutePart)" : "\(hourPart)的\(minutePart)"
    }

    // MARK: - 说成英文

    var englishSummary: String {
        let when = englishDayDescription
        let time = englishTimeDescription
        if when == "every day", time.hasPrefix("every") {
            return time
        }
        return "\(when) \(time)"
    }

    private static let englishMonths = ["January", "February", "March", "April", "May", "June", "July",
                                        "August", "September", "October", "November", "December"]
    private static let englishWeekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private var englishDayDescription: String {
        let monthNames = Self.englishMonths
        let monthText = fields[3] == "*" ? nil : Self.list(months, unit: "", separator: ", ") { monthNames[($0 - 1) % 12] }
        let dayText = Self.list(days, unit: "", separator: ", ")
        switch (anyDay, anyWeekday) {
        case (true, true):
            return monthText.map { "every day in \($0)" } ?? "every day"
        case (false, true):
            return monthText.map { "on day \(dayText) of \($0)" } ?? "on day \(dayText) of every month"
        case (true, false):
            return "every \(englishWeekdayDescription)" + (monthText.map { " in \($0)" } ?? "")
        case (false, false):
            return "on day \(dayText) and every \(englishWeekdayDescription)" + (monthText.map { " in \($0)" } ?? "")
        }
    }

    private var englishWeekdayDescription: String {
        let names = Self.englishWeekdays
        let sorted = weekdays.sorted { ($0 == 0 ? 7 : $0) < ($1 == 0 ? 7 : $1) }
        if sorted == [1, 2, 3, 4, 5] { return "weekday (Monday to Friday)" }
        if sorted == [6, 0] { return "weekend day" }
        if sorted.count > 2, Self.isRange(sorted.map { $0 == 0 ? 7 : $0 }), let first = sorted.first, let last = sorted.last {
            return "\(names[first]) to \(names[last])"
        }
        return sorted.map { names[$0] }.joined(separator: ", ")
    }

    private var englishTimeDescription: String {
        if minutes.count == 1, hours.count <= 6, let minute = minutes.first {
            return "at " + hours.sorted().map { String(format: "%02d:%02d", $0, minute) }.joined(separator: ", ")
        }
        let minuteField = fields[0]
        let minutePart: String
        if minuteField == "*" {
            minutePart = "every minute"
        } else if minuteField.hasPrefix("*/"), let step = Int(minuteField.dropFirst(2)) {
            minutePart = "every \(step) minutes"
        } else if minutes == [0] {
            minutePart = "on the hour"
        } else {
            minutePart = "at minute " + Self.list(minutes, unit: "", separator: ", ")
        }
        if hours.count == 24 {
            return minutePart.hasPrefix("every") ? minutePart : "every hour \(minutePart)"
        }
        let hourField = fields[1]
        let hourPart: String
        if hourField.hasPrefix("*/"), let step = Int(hourField.dropFirst(2)) {
            hourPart = "every \(step) hours"
        } else if hours.count > 2, Self.isRange(hours.sorted()), let first = hours.min(), let last = hours.max() {
            hourPart = "during hours \(first)–\(last)"
        } else {
            hourPart = "during hours " + Self.list(hours, unit: "", separator: ", ")
        }
        return "\(minutePart) \(hourPart)"
    }

    private static func isRange(_ sorted: [Int]) -> Bool {
        zip(sorted, sorted.dropFirst()).allSatisfy { $1 == $0 + 1 }
    }

    /// 1,2,3,4,10 → 「1–4、10」，每一项后面加上单位
    private static func list(_ values: Set<Int>, unit: String, separator: String = "、",
                             name: (Int) -> String = { String($0) }) -> String {
        let sorted = values.sorted()
        var parts: [String] = []
        var index = 0
        while index < sorted.count {
            var end = index
            while end + 1 < sorted.count, sorted[end + 1] == sorted[end] + 1 { end += 1 }
            if end - index >= 2 {
                parts.append("\(name(sorted[index]))–\(name(sorted[end]))\(unit)")
            } else {
                parts += sorted[index...end].map { "\(name($0))\(unit)" }
            }
            index = end + 1
        }
        return parts.joined(separator: separator)
    }
}
