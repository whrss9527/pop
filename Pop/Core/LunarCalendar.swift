import Foundation

/// 农历日期（干支纪年、生肖、月、日）和传统节日，用系统的农历历法计算。纯逻辑，方便测试。
enum LunarCalendar {
    private static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let zodiacs = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]
    private static let months = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let festivals: [String: String] = [
        "1-1": "春节", "1-15": "元宵节", "5-5": "端午节", "7-7": "七夕", "7-15": "中元节",
        "8-15": "中秋节", "9-9": "重阳节", "12-8": "腊八节",
    ]

    struct LunarDate: Equatable {
        /// 六十甲子里的第几年（1 是甲子）
        var cycleYear: Int
        var month: Int
        var day: Int
        var isLeapMonth: Bool
    }

    static func lunarDate(_ date: Date, timeZone: TimeZone = .current) -> LunarDate? {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day,
              (1...60).contains(year), (1...12).contains(month), (1...30).contains(day) else { return nil }
        return LunarDate(cycleYear: year, month: month, day: day, isLeapMonth: components.isLeapMonth ?? false)
    }

    static func dayName(_ day: Int) -> String {
        let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        switch day {
        case 1...10: return "初" + digits[day]
        case 11...19: return "十" + digits[day - 10]
        case 20: return "二十"
        case 21...29: return "廿" + digits[day - 20]
        case 30: return "三十"
        default: return ""
        }
    }

    /// 「丙午年（马年）八月十五 · 中秋节」
    static func describe(_ date: Date, timeZone: TimeZone = .current) -> String? {
        guard let lunar = lunarDate(date, timeZone: timeZone) else { return nil }
        let index = lunar.cycleYear - 1
        let year = stems[index % 10] + branches[index % 12] + "年（\(zodiacs[index % 12])年）"
        let month = (lunar.isLeapMonth ? "闰" : "") + months[lunar.month - 1]
        var text = year + month + dayName(lunar.day)
        if let name = festival(date, timeZone: timeZone) {
            text += " · " + name
        }
        return text
    }

    static func festival(_ date: Date, timeZone: TimeZone = .current) -> String? {
        guard let lunar = lunarDate(date, timeZone: timeZone) else { return nil }
        if !lunar.isLeapMonth, let name = festivals["\(lunar.month)-\(lunar.day)"] {
            return name
        }
        // 除夕：第二天是正月初一
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if lunar.month == 12, let next = calendar.date(byAdding: .day, value: 1, to: date),
           let following = lunarDate(next, timeZone: timeZone), following.month == 1, following.day == 1, !following.isLeapMonth {
            return "除夕"
        }
        return nil
    }

    /// 「第 40 周 · 全年第 272 天」（按 ISO 8601，周一是一周的第一天）
    static func weekAndDay(_ date: Date, timeZone: TimeZone = .current) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = timeZone
        let week = iso.component(.weekOfYear, from: date)
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let day = gregorian.ordinality(of: .day, in: .year, for: date) ?? 0
        return "第 \(week) 周 · 全年第 \(day) 天"
    }
}
