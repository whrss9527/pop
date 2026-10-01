import Foundation
@testable import Pop

/// 日历卡片的数据：一个月六行七列，每格的农历、节气、节日；选中的文字是哪一天。纯逻辑，方便测试。
///
/// 日子都用「从 1970 年 1 月 1 日起的第几天」表示，只看年月日、不管时区（`LunarTable.dayNumber`）。
enum CalendarMonth {
    struct Day: Identifiable, Equatable {
        /// 从 1970 年 1 月 1 日起的第几天
        let number: Int
        let year: Int
        let month: Int
        let day: Int
        /// 1 是星期日，7 是星期六
        let weekday: Int
        /// 在看的这个月里（不是前后两个月补上的）
        let isInMonth: Bool
        let isToday: Bool
        let lunar: LunarCalendar.LunarDate?
        /// 这一天的节日：农历的在前（国庆节碰上中秋节时两个都有）
        let festivals: [String]
        /// 节气在 `SolarTerms.names` 里的序号
        let solarTerm: Int?

        var id: Int { number }

        var isWeekend: Bool { weekday == 1 || weekday == 7 }
    }

    /// 格子里日期下面那一行
    enum Note: Equatable {
        case festival(String)
        case solarTerm(String)
        /// 农历初一写月份：「九月」「闰六月」
        case lunarMonth(String)
        case lunarDay(String)
        case empty

        var text: String {
            switch self {
            case .festival(let text), .solarTerm(let text), .lunarMonth(let text), .lunarDay(let text): return text
            case .empty: return ""
            }
        }
    }

    // MARK: - 日子

    /// 星期几：1 是星期日，7 是星期六（1970 年 1 月 1 日是星期四）
    static func weekday(of number: Int) -> Int {
        ((number % 7 + 7 + 4) % 7) + 1
    }

    static func day(_ number: Int, inMonth month: (year: Int, month: Int)? = nil, today: Int? = nil) -> Day {
        let date = LunarTable.civil(fromDayNumber: number)
        let lunar = LunarCalendar.lunarDate(year: date.year, month: date.month, day: date.day)
        let weekday = Self.weekday(of: number)
        var festivals: [String] = []
        if let name = LunarCalendar.festival(year: date.year, month: date.month, day: date.day) {
            festivals.append(localizedLunarFestival(name))
        }
        festivals += gregorianFestivals(year: date.year, month: date.month, day: date.day, weekday: weekday)
        let isInMonth = month.map { $0.year == date.year && $0.month == date.month } ?? true
        return Day(number: number, year: date.year, month: date.month, day: date.day, weekday: weekday, isInMonth: isInMonth,
                   isToday: number == today, lunar: lunar, festivals: festivals,
                   solarTerm: SolarTerms.term(year: date.year, month: date.month, day: date.day))
    }

    /// 一个月的格子：从包含 1 号的那一周的第一天起，六行七列
    static func days(year: Int, month: Int, firstWeekday: Int, today: Int?) -> [Day] {
        let first = LunarTable.dayNumber(year: year, month: month, day: 1)
        let leading = (weekday(of: first) - firstWeekday + 7) % 7
        let start = first - leading
        return (0..<42).map { day(start + $0, inMonth: (year, month), today: today) }
    }

    /// 某个月有几天
    static func length(year: Int, month: Int) -> Int {
        let next = month == 12 ? (year + 1, 1) : (year, month + 1)
        return LunarTable.dayNumber(year: next.0, month: next.1, day: 1) - LunarTable.dayNumber(year: year, month: month, day: 1)
    }

    /// 格子里写什么：显示农历时依次是节日、节气、农历（初一写月份）；不显示农历时只写公历的节日
    static func note(for day: Day, showsLunar: Bool) -> Note {
        if showsLunar {
            if let festival = day.festivals.first {
                return .festival(festival)
            }
            if let term = day.solarTerm {
                return .solarTerm(SolarTerms.name(term))
            }
            guard let lunar = day.lunar else { return .empty }
            if lunar.day == 1 {
                return .lunarMonth(LunarCalendar.monthName(lunar.month, isLeapMonth: lunar.isLeapMonth))
            }
            return .lunarDay(LunarCalendar.dayName(lunar.day))
        }
        let gregorian = gregorianFestivals(year: day.year, month: day.month, day: day.day, weekday: day.weekday)
        return gregorian.first.map(Note.festival) ?? Note.empty
    }

    // MARK: - 节日

    /// 农历的节日在英文界面里的名字
    static func localizedLunarFestival(_ name: String) -> String {
        switch name {
        case "春节": return String(localized: "春节")
        case "元宵节": return String(localized: "元宵节")
        case "端午节": return String(localized: "端午节")
        case "七夕": return String(localized: "七夕")
        case "中元节": return String(localized: "中元节")
        case "中秋节": return String(localized: "中秋节")
        case "重阳节": return String(localized: "重阳节")
        case "腊八节": return String(localized: "腊八节")
        case "除夕": return String(localized: "除夕")
        default: return name
        }
    }

    /// 公历的节日：固定日子的，和「5 月第二个星期日」这样的
    static func gregorianFestivals(year: Int, month: Int, day: Int, weekday: Int) -> [String] {
        var names: [String] = []
        switch (month, day) {
        case (1, 1): names.append(String(localized: "元旦"))
        case (2, 14): names.append(String(localized: "情人节"))
        case (3, 8): names.append(String(localized: "妇女节"))
        case (3, 12): names.append(String(localized: "植树节"))
        case (5, 1): names.append(String(localized: "劳动节"))
        case (5, 4): names.append(String(localized: "青年节"))
        case (6, 1): names.append(String(localized: "儿童节"))
        case (9, 10): names.append(String(localized: "教师节"))
        case (10, 1): names.append(String(localized: "国庆节"))
        case (12, 24): names.append(String(localized: "平安夜"))
        case (12, 25): names.append(String(localized: "圣诞节"))
        default: break
        }
        // 第几个星期几：母亲节是 5 月第二个星期日，父亲节是 6 月第三个星期日
        let ordinal = (day - 1) / 7 + 1
        if month == 5, weekday == 1, ordinal == 2 {
            names.append(String(localized: "母亲节"))
        }
        if month == 6, weekday == 1, ordinal == 3 {
            names.append(String(localized: "父亲节"))
        }
        return names
    }

    // MARK: - 标题

    /// 「丙午年 八月—九月」：这个月跨了农历的哪几个月；年份不在历表里时为 nil
    static func lunarSpan(year: Int, month: Int) -> String? {
        guard let first = LunarCalendar.lunarDate(year: year, month: month, day: 1),
              let last = LunarCalendar.lunarDate(year: year, month: month, day: length(year: year, month: month)) else { return nil }
        let firstYear = LunarCalendar.yearName(cycleYear: first.cycleYear).prefix(3)
        let firstMonth = LunarCalendar.monthName(first.month, isLeapMonth: first.isLeapMonth)
        let lastMonth = LunarCalendar.monthName(last.month, isLeapMonth: last.isLeapMonth)
        if first.cycleYear != last.cycleYear {
            let lastYear = LunarCalendar.yearName(cycleYear: last.cycleYear).prefix(3)
            return "\(firstYear)\(firstMonth)—\(lastYear)\(lastMonth)"
        }
        return firstMonth == lastMonth ? "\(firstYear) \(firstMonth)" : "\(firstYear) \(firstMonth)—\(lastMonth)"
    }

    /// 从某一天起（不含这一天）的下一个节气：序号和哪一天
    static func nextSolarTerm(after number: Int) -> (index: Int, number: Int)? {
        let date = LunarTable.civil(fromDayNumber: number)
        for year in [date.year, date.year + 1] {
            for index in SolarTerms.names.indices {
                guard let day = SolarTerms.day(ofTerm: index, in: year) else { return nil }
                let term = LunarTable.dayNumber(year: year, month: SolarTerms.month(ofTerm: index), day: day)
                if term > number {
                    return (index, term)
                }
            }
        }
        return nil
    }

    // MARK: - 选中的文字

    /// 选中的文字是哪一天：公历日期（「2026-10-01」「2026年10月1日」「10月1日」「October 1, 2026」）、
    /// 年月（「2026年10月」，取 1 号）、农历日子（「农历八月十五」）、节日和节气（「中秋节」「冬至」，取今天以后最近的那次）
    static func parse(_ text: String, today: Int) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40, !trimmed.contains(where: \.isNewline) else { return nil }
        let year = LunarTable.civil(fromDayNumber: today).year
        if let date = DateParser.parse(trimmed, timeZone: TimeZone(identifier: "UTC") ?? .current) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            if let y = parts.year, let m = parts.month, let d = parts.day {
                return LunarTable.dayNumber(year: y, month: m, day: d)
            }
        }
        if let match = numbers(in: trimmed, pattern: #"^(\d{4})\s*(?:年|[-/.])\s*(\d{1,2})\s*月?$"#), (1...12).contains(match[1]) {
            return LunarTable.dayNumber(year: match[0], month: match[1], day: 1)
        }
        if let match = numbers(in: trimmed, pattern: #"^(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?$"#),
           (1...12).contains(match[0]), (1...length(year: year, month: match[0])).contains(match[1]) {
            return LunarTable.dayNumber(year: year, month: match[0], day: match[1])
        }
        if let number = namedDay(trimmed, today: today) {
            return number
        }
        if let number = lunarDay(trimmed, today: today) {
            return number
        }
        return detectedDate(trimmed)
    }

    private static func numbers(in text: String, pattern: String) -> [Int]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var values: [Int] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text), let value = Int(text[range]) else { return nil }
            values.append(value)
        }
        return values
    }

    /// 节日、节气的名字（中文，或者英文界面里的名字）：今天以后（含今天）最近的那次
    private static func namedDay(_ text: String, today: Int) -> Int? {
        // 「中秋」「端午」「国庆」也认：补上「节」再比
        let wanted = Set([text, text + "节"].map { $0.lowercased() })
        func matches(_ name: String) -> Bool {
            wanted.contains(name.lowercased())
        }
        let term = SolarTerms.names.indices.first { matches(SolarTerms.names[$0]) || matches(SolarTerms.name($0)) }
        let festival = LunarCalendar.festivalDays.first { matches($0.name) || matches(localizedLunarFestival($0.name)) }
        let isEve = matches("除夕") || matches(localizedLunarFestival("除夕"))
        let year = LunarTable.civil(fromDayNumber: today).year
        var candidates: [Int] = []
        for target in [year, year + 1] {
            if let term, let day = SolarTerms.day(ofTerm: term, in: target) {
                candidates.append(LunarTable.dayNumber(year: target, month: SolarTerms.month(ofTerm: term), day: day))
            }
            if let festival, let number = LunarTable.dayNumber(lunarYear: target, month: festival.month, day: festival.day) {
                candidates.append(number)
            }
            if isEve, let next = LunarTable.dayNumber(lunarYear: target + 1, month: 1, day: 1) {
                candidates.append(next - 1)
            }
            for month in 1...12 {
                for day in 1...length(year: target, month: month) {
                    let number = LunarTable.dayNumber(year: target, month: month, day: day)
                    if gregorianFestivals(year: target, month: month, day: day, weekday: weekday(of: number)).contains(where: matches) {
                        candidates.append(number)
                    }
                }
            }
        }
        return candidates.filter { $0 >= today }.min()
    }

    private static let lunarMonths = ["正": 1, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
                                      "十": 10, "冬": 11, "十一": 11, "腊": 12, "十二": 12]

    /// 「农历八月十五」「八月十五」「腊月初八」「闰六月初一」：今天以后（含今天）最近的那次
    private static func lunarDay(_ text: String, today: Int) -> Int? {
        var rest = Substring(text)
        if rest.hasPrefix("农历") {
            rest = rest.dropFirst(2)
        }
        let isLeap = rest.hasPrefix("闰")
        if isLeap {
            rest = rest.dropFirst()
        }
        guard let monthEnd = rest.firstIndex(of: "月") else { return nil }
        guard let month = lunarMonths[String(rest[rest.startIndex..<monthEnd])] else { return nil }
        let dayText = String(rest[rest.index(after: monthEnd)...])
        guard let day = (1...30).first(where: { LunarCalendar.dayName($0) == dayText }) else { return nil }
        let year = LunarTable.civil(fromDayNumber: today).year
        return [year - 1, year, year + 1]
            .compactMap { LunarTable.dayNumber(lunarYear: $0, month: month, day: day, isLeapMonth: isLeap) }
            .filter { $0 >= today }
            .min()
    }

    /// 英文的写法交给系统认（「October 1, 2026」「Oct 1」）：整段都是日期才算。中文的只认上面那几种，免得认错
    private static func detectedDate(_ text: String) -> Int? {
        guard text.unicodeScalars.contains(where: { $0.isASCII && CharacterSet.letters.contains($0) }),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range.length >= (text as NSString).length - 1, let date = match.date else { return nil }
        let zone = match.timeZone ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = parts.year, let m = parts.month, let d = parts.day else { return nil }
        return LunarTable.dayNumber(year: y, month: m, day: d)
    }
}
