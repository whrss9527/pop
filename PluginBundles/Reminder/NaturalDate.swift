import Foundation
@testable import Pop

/// 从一句话里认出时间：「明天下午 3 点开会」→ 明天 15:00 和「开会」。
/// 中文的说法自己解析（今天明天后天、周几、下周几、几月几号、几号、几天后、半小时后、上午下午晚上几点几分），
/// 其他语言交给系统的 NSDataDetector。纯逻辑，方便测试。
enum NaturalDate {
    struct Result: Equatable {
        var date: Date
        /// 说了具体几点（否则是全天的事）
        var hasTime: Bool
        /// 去掉时间说法后剩下的事情
        var title: String
    }

    // MARK: - 各种说法

    private static let number = #"(\d{1,2}|[零一二两三四五六七八九十]{1,3})"#

    /// 半小时后、3 天后、两个小时以后
    private static let duration = try! NSRegularExpression(
        pattern: #"(\d+|半|[一二两三四五六七八九十]{1,3})\s*个?\s*(分钟|小时|钟头|天|周|星期|礼拜)\s*(?:以后|之后|后)"#)
    private static let relativeDay = try! NSRegularExpression(pattern: "大后天|后天|明天|明日|今天|今日|今晚|明晚|今早|明早")
    private static let weekday = try! NSRegularExpression(pattern: #"(下下个?|下个?|这个?|本)?\s*(?:周|星期|礼拜)\s*([一二三四五六日天1-7])"#)
    private static let monthDay = try! NSRegularExpression(pattern: #"(?:(\d{4})\s*年\s*)?(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?"#)
    /// 2026-10-08、2026/10/8
    private static let isoDate = try! NSRegularExpression(pattern: #"(?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)"#)
    private static let dayOnly = try! NSRegularExpression(pattern: #"(?<![\d月])(\d{1,2})\s*号(?![楼线码位房门口车])"#)
    /// 上午 9 点半、下午三点一刻、15:30、晚上 8 点（「今晚 8 点」的「今晚」算在日子里）
    private static let time = try! NSRegularExpression(
        pattern: #"(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里)?\s*"# + number
            + #"\s*(?:点|时|:|：)\s*(?:(半)|(一刻)|(三刻)|(\d{1,2})\s*分?|(整))?"#)
    /// 只说了时段没说几点：「明天晚上」按晚上 8 点算
    private static let period = try! NSRegularExpression(pattern: "凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里")

    private static let periodHours: [String: Int] = [
        "凌晨": 6, "早上": 9, "早晨": 9, "上午": 10, "中午": 12, "下午": 15, "傍晚": 18, "晚上": 20, "夜里": 22, "晚": 20,
        "今晚": 20, "明晚": 20, "今早": 9, "明早": 9,
    ]

    /// 句首这些词去掉：「提醒我周五之前交周报」→「交周报」
    private static let fillers = ["提醒我", "提醒", "记得", "别忘了", "之前", "以前", "的时候", "的", "在", "要"]

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Result? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 500 else { return nil }
        // 没有汉字的先交给系统识别（「Meeting at 3:30」里的 at 也会去掉），认不出再按中文的说法试
        if !trimmed.unicodeScalars.contains(where: { $0.properties.isIdeographic }),
           let detected = parseWithDetector(trimmed, now: now) {
            return detected
        }
        if let chinese = parseChinese(trimmed, now: now, calendar: calendar) {
            return chinese
        }
        return parseWithDetector(trimmed, now: now)
    }

    // MARK: - 中文

    private static func parseChinese(_ text: String, now: Date, calendar: Calendar) -> Result? {
        let string = text as NSString
        let full = NSRange(location: 0, length: string.length)
        var used: [NSRange] = []
        func take(_ regex: NSRegularExpression) -> NSTextCheckingResult? {
            for match in regex.matches(in: text, range: full)
            where !used.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                used.append(match.range)
                return match
            }
            return nil
        }
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : string.substring(with: range)
        }

        let today = calendar.startOfDay(for: now)
        var day: Date?
        var hasExplicitDay = false
        var hour: Int?
        var minute = 0
        var periodWord: String?
        var exact: Date?

        // 半小时后、3 天后
        if let match = take(duration), let amountText = group(match, 1), let unit = group(match, 2) {
            let amount = amountText == "半" ? 0.5 : Double(Int(amountText) ?? chineseNumber(amountText) ?? 0)
            switch unit {
            case "分钟":
                exact = now.addingTimeInterval(amount * 60)
            case "小时", "钟头":
                exact = now.addingTimeInterval(amount * 3600)
            case "天":
                day = calendar.date(byAdding: .day, value: Int(amount), to: today)
                hasExplicitDay = true
            default:
                day = calendar.date(byAdding: .day, value: Int(amount * 7), to: today)
                hasExplicitDay = true
            }
        }
        if exact == nil {
            if let match = take(relativeDay) {
                let word = string.substring(with: match.range)
                let offset: Int
                switch word {
                case "大后天": offset = 3
                case "后天": offset = 2
                case "明天", "明日", "明晚", "明早": offset = 1
                default: offset = 0
                }
                day = calendar.date(byAdding: .day, value: offset, to: today)
                hasExplicitDay = true
                if ["今晚", "明晚", "今早", "明早"].contains(word) { periodWord = word }
            } else if let match = take(isoDate) ?? take(monthDay), let month = group(match, 2).flatMap({ Int($0) }),
                      let dayOfMonth = group(match, 3).flatMap({ Int($0) }) {
                var components = calendar.dateComponents([.year], from: now)
                if let year = group(match, 1).flatMap({ Int($0) }) { components.year = year }
                components.month = month
                components.day = dayOfMonth
                if var date = calendar.date(from: components), (1...12).contains(month), (1...31).contains(dayOfMonth) {
                    // 没写年份、日子已经过了：说的是明年
                    if group(match, 1) == nil, date < today, let next = calendar.date(byAdding: .year, value: 1, to: date) {
                        date = next
                    }
                    day = date
                    hasExplicitDay = true
                }
            } else if let match = take(weekday), let target = group(match, 2).flatMap(weekdayIndex) {
                let current = (calendar.component(.weekday, from: today) + 5) % 7 + 1
                let prefix = group(match, 1) ?? ""
                var offset: Int
                if prefix.hasPrefix("下下") {
                    offset = 14 - current + target
                } else if prefix.hasPrefix("下") {
                    offset = 7 - current + target
                } else {
                    offset = target - current
                    if offset < 0 { offset += 7 }
                }
                day = calendar.date(byAdding: .day, value: offset, to: today)
                hasExplicitDay = true
            } else if let match = take(dayOnly), let dayOfMonth = group(match, 1).flatMap({ Int($0) }), (1...31).contains(dayOfMonth) {
                var components = calendar.dateComponents([.year, .month], from: now)
                components.day = dayOfMonth
                if var date = calendar.date(from: components) {
                    if date < today, let next = calendar.date(byAdding: .month, value: 1, to: date) { date = next }
                    day = date
                    hasExplicitDay = true
                }
            }

            if let match = take(time), let hourText = group(match, 2),
               let value = Int(hourText) ?? chineseNumber(hourText), (0...24).contains(value) {
                hour = value
                if let word = group(match, 1) { periodWord = word }
                if group(match, 3) != nil {
                    minute = 30
                } else if group(match, 4) != nil {
                    minute = 15
                } else if group(match, 5) != nil {
                    minute = 45
                } else if let minutes = group(match, 6).flatMap({ Int($0) }), (0...59).contains(minutes) {
                    minute = minutes
                }
            } else if periodWord == nil, let match = take(period) {
                periodWord = string.substring(with: match.range)
            }
        }

        guard exact != nil || day != nil || hour != nil || periodWord != nil else { return nil }
        let title = cleanTitle(text, removing: used)
        if let exact {
            return Result(date: exact, hasTime: true, title: title)
        }
        if hour == nil, let periodWord {
            hour = periodHours[periodWord]
        }
        guard var hour else {
            return day.map { Result(date: $0, hasTime: false, title: title) }
        }
        // 下午、晚上的钟点加 12；没说时段的 1–6 点多半是下午
        let evening = ["下午", "傍晚", "晚上", "夜里", "晚", "今晚", "明晚"]
        if let periodWord, evening.contains(periodWord), hour < 12 {
            hour += 12
        } else if periodWord == "中午", hour < 11 {
            hour += 12
        } else if periodWord == nil, (1...6).contains(hour) {
            hour += 12
        }
        var components = calendar.dateComponents([.year, .month, .day], from: day ?? today)
        components.hour = hour % 24
        components.minute = minute
        guard var date = calendar.date(from: components) else { return nil }
        if hour == 24, let next = calendar.date(byAdding: .day, value: 1, to: date) { date = next }
        // 只说了几点、已经过了：说的是明天
        if !hasExplicitDay, date <= now, let next = calendar.date(byAdding: .day, value: 1, to: date) {
            date = next
        }
        return Result(date: date, hasTime: true, title: title)
    }

    /// 一到日，周日也叫周天
    private static func weekdayIndex(_ text: String) -> Int? {
        switch text {
        case "一", "1": return 1
        case "二", "2": return 2
        case "三", "3": return 3
        case "四", "4": return 4
        case "五", "5": return 5
        case "六", "6": return 6
        case "日", "天", "7": return 7
        default: return nil
        }
    }

    /// 一、两、十、十二、二十三
    static func chineseNumber(_ text: String) -> Int? {
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let characters = Array(text)
        guard !characters.isEmpty else { return nil }
        if let tenIndex = characters.firstIndex(of: "十") {
            let tens = tenIndex == 0 ? 1 : (characters.count > 0 ? digits[characters[0]] : nil)
            let ones = tenIndex + 1 < characters.count ? digits[characters[tenIndex + 1]] : 0
            guard let tens, let ones, tenIndex <= 1, characters.count <= tenIndex + 2 else { return nil }
            return tens * 10 + ones
        }
        guard characters.count == 1 else { return nil }
        return digits[characters[0]]
    }

    private static func cleanTitle(_ text: String, removing ranges: [NSRange]) -> String {
        let result = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            result.replaceCharacters(in: range, with: " ")
        }
        var title = (result as String).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        var changed = true
        while changed {
            changed = false
            for filler in fillers where title.hasPrefix(filler) && title.count > filler.count {
                title = String(title.dropFirst(filler.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                changed = true
            }
        }
        // 中间留下的多个空格合成一个
        return title.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    }

    // MARK: - 其他语言

    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    private static let clockWords = try! NSRegularExpression(
        pattern: #"\d{1,2}:\d{2}|\d{1,2}\s*(?:am|pm|a\.m\.|p\.m\.)|noon|midnight|o'clock"#, options: [.caseInsensitive])

    private static func parseWithDetector(_ text: String, now: Date) -> Result? {
        let full = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, range: full), let date = match.date,
              let range = Range(match.range, in: text) else { return nil }
        let phrase = String(text[range])
        let hasTime = clockWords.firstMatch(in: phrase, range: NSRange(phrase.startIndex..., in: phrase)) != nil
        var title = text.replacingCharacters(in: range, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for filler in ["remind me to ", "remind me ", "at ", "on ", "by "] where title.lowercased().hasPrefix(filler) {
            title = String(title.dropFirst(filler.count))
        }
        for suffix in [" at", " on", " by"] where title.lowercased().hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
        }
        return Result(date: date, hasTime: hasTime, title: title.trimmingCharacters(in: .whitespaces))
    }
}
