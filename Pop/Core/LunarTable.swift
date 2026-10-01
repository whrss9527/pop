import Foundation

/// 1900–2100 年的农历历表，按中国的历法规定（以北京时间定朔日、中气）推算，每年一个数：
/// 低 4 位是闰几月（0 是没有闰月），从高到低的第 16～5 位是正月到腊月是不是大月（30 天），第 17 位是闰月是不是大月。
///
/// 系统的农历历法在朔日离半夜只差几分钟时会差一天（比如 2027 年、2030 年的春节），所以这个范围里用历表，范围外再用系统的。
enum LunarTable {
    static let firstYear = 1900
    /// 农历 1900 年正月初一是公历 1900 年 1 月 31 日
    private static let firstDay = dayNumber(year: 1900, month: 1, day: 31)

    private static let info: [Int] = [
        0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2,  // 1900
        0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977,  // 1910
        0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970,  // 1920
        0x06566, 0x0d4a0, 0x0ea50, 0x16a95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,  // 1930
        0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557,  // 1940
        0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0,  // 1950
        0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0,  // 1960
        0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6,  // 1970
        0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,  // 1980
        0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x05ac0, 0x0ab60, 0x096d5, 0x092e0,  // 1990
        0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5,  // 2000
        0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,  // 2010
        0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,  // 2020
        0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45,  // 2030
        0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,  // 2040
        0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06aa0, 0x1a6c4, 0x0aae0,  // 2050
        0x092e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4,  // 2060
        0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0,  // 2070
        0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160,  // 2080
        0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252,  // 2090
        0x0d520,  // 2100
    ]

    static var lastYear: Int { firstYear + info.count - 1 }

    /// 每个农历年的正月初一离 1900 年 1 月 31 日几天；最后多一个，是表里最后一年的下一个正月初一
    private static let yearStarts: [Int] = {
        var starts = [0]
        for value in info {
            starts.append(starts[starts.count - 1] + days(inYear: value))
        }
        return starts
    }()

    struct Day: Equatable {
        /// 农历年，按公历的年份写（正月初一起算）
        var year: Int
        var month: Int
        var day: Int
        var isLeapMonth: Bool
    }

    /// 公历的某一天是农历哪一天；不在表的范围里时为 nil
    static func lunar(year: Int, month: Int, day: Int) -> Day? {
        let offset = dayNumber(year: year, month: month, day: day) - firstDay
        guard offset >= 0, let last = yearStarts.last, offset < last else { return nil }
        // 找到这一天在哪个农历年里
        var low = 0
        var high = info.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if yearStarts[middle] <= offset {
                low = middle
            } else {
                high = middle - 1
            }
        }
        let value = info[low]
        var remaining = offset - yearStarts[low]
        let leap = value & 0xF
        for month in 1...12 {
            let length = days(inMonth: month, of: value)
            if remaining < length {
                return Day(year: firstYear + low, month: month, day: remaining + 1, isLeapMonth: false)
            }
            remaining -= length
            if month == leap {
                let leapLength = value & 0x10000 != 0 ? 30 : 29
                if remaining < leapLength {
                    return Day(year: firstYear + low, month: month, day: remaining + 1, isLeapMonth: true)
                }
                remaining -= leapLength
            }
        }
        return nil
    }

    /// 农历某年闰几月；没有闰月或者不在表里时为 nil
    static func leapMonth(inYear year: Int) -> Int? {
        guard (firstYear...lastYear).contains(year) else { return nil }
        let leap = info[year - firstYear] & 0xF
        return leap == 0 ? nil : leap
    }

    /// 农历某年某月有几天（29 或 30）；不在表里时为 nil
    static func monthLength(year: Int, month: Int, isLeapMonth: Bool = false) -> Int? {
        guard (firstYear...lastYear).contains(year), (1...12).contains(month) else { return nil }
        let value = info[year - firstYear]
        if isLeapMonth {
            guard value & 0xF == month else { return nil }
            return value & 0x10000 != 0 ? 30 : 29
        }
        return days(inMonth: month, of: value)
    }

    /// 农历某年某月某日是公历哪一天（从 1970 年 1 月 1 日起的第几天）；不在表里、没有这一天时为 nil
    static func dayNumber(lunarYear year: Int, month: Int, day: Int, isLeapMonth: Bool = false) -> Int? {
        guard (firstYear...lastYear).contains(year), (1...12).contains(month),
              let length = monthLength(year: year, month: month, isLeapMonth: isLeapMonth), (1...length).contains(day) else { return nil }
        let value = info[year - firstYear]
        let leap = value & 0xF
        var offset = yearStarts[year - firstYear]
        for earlier in 1..<month {
            offset += days(inMonth: earlier, of: value)
            if earlier == leap {
                offset += value & 0x10000 != 0 ? 30 : 29
            }
        }
        if isLeapMonth {
            offset += days(inMonth: month, of: value)
        }
        return firstDay + offset + day - 1
    }

    private static func days(inMonth month: Int, of value: Int) -> Int {
        value & (0x8000 >> (month - 1)) != 0 ? 30 : 29
    }

    private static func days(inYear value: Int) -> Int {
        var total = 0
        for month in 1...12 {
            total += days(inMonth: month, of: value)
        }
        if value & 0xF != 0 {
            total += value & 0x10000 != 0 ? 30 : 29
        }
        return total
    }

    /// dayNumber 反过来：从 1970 年 1 月 1 日起的第几天是公历哪一天
    static func civil(fromDayNumber number: Int) -> (year: Int, month: Int, day: Int) {
        let shifted = number + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// 公历日期是从 1970 年 1 月 1 日起的第几天（往前是负数），只看年月日，不管时区
    static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let shifted = month <= 2 ? year - 1 : year
        let era = (shifted >= 0 ? shifted : shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
