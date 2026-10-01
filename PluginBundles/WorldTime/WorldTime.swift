import Foundation
@testable import Pop

/// 时区换算：城市表，从一段文字里认出时间和时区（「3pm PST」「北京时间晚上 9 点」「10:00 UTC+8」），
/// 各地的时间、日期、和本地差几天怎么写。纯逻辑，方便测试。
enum WorldTime {
    struct City: Identifiable, Hashable {
        /// 存进设置里的 key：表里的城市是英文名（newYork），表外的时区是「tz:」加时区标识
        let id: String
        let timeZone: TimeZone
        /// 界面上显示的名字（跟着界面语言）
        let name: String
        /// 中文名、英文名和别的叫法：搜索、认「东京时间」「Tokyo time」都用
        var names: [String] = []
        /// 只用来搜索：国家、地区、附近的城市
        var keywords: [String] = []
    }

    // MARK: - 城市

    /// 常用的城市；同一个时区可以有几个城市（北京、上海）
    static var cities: [City] {
        let table: [City?] = [
            city("utc", "UTC", "UTC", ["UTC", "协调世界时", "世界标准时间"], ["GMT", "Greenwich", "格林尼治", "格林威治", "Zulu"]),
            city("beijing", "Asia/Shanghai", String(localized: "北京"), ["北京", "Beijing", "Peking"], ["中国", "China", "深圳", "Shenzhen", "广州", "Guangzhou"]),
            city("shanghai", "Asia/Shanghai", String(localized: "上海"), ["上海", "Shanghai"], ["中国", "China", "杭州", "Hangzhou"]),
            city("hongKong", "Asia/Hong_Kong", String(localized: "香港"), ["香港", "Hong Kong"], []),
            city("taipei", "Asia/Taipei", String(localized: "台北"), ["台北", "Taipei"], ["台湾", "Taiwan"]),
            city("tokyo", "Asia/Tokyo", String(localized: "东京"), ["东京", "Tokyo"], ["日本", "Japan", "大阪", "Osaka"]),
            city("seoul", "Asia/Seoul", String(localized: "首尔"), ["首尔", "Seoul"], ["韩国", "Korea"]),
            city("singapore", "Asia/Singapore", String(localized: "新加坡"), ["新加坡", "Singapore"], []),
            city("kualaLumpur", "Asia/Kuala_Lumpur", String(localized: "吉隆坡"), ["吉隆坡", "Kuala Lumpur"], ["马来西亚", "Malaysia"]),
            city("bangkok", "Asia/Bangkok", String(localized: "曼谷"), ["曼谷", "Bangkok"], ["泰国", "Thailand"]),
            city("hoChiMinh", "Asia/Ho_Chi_Minh", String(localized: "胡志明市"), ["胡志明市", "胡志明", "Ho Chi Minh City", "Saigon"], ["越南", "Vietnam", "河内", "Hanoi"]),
            city("jakarta", "Asia/Jakarta", String(localized: "雅加达"), ["雅加达", "Jakarta"], ["印度尼西亚", "印尼", "Indonesia"]),
            city("manila", "Asia/Manila", String(localized: "马尼拉"), ["马尼拉", "Manila"], ["菲律宾", "Philippines"]),
            city("newDelhi", "Asia/Kolkata", String(localized: "新德里"), ["新德里", "New Delhi", "Delhi"], ["印度", "India"]),
            city("mumbai", "Asia/Kolkata", String(localized: "孟买"), ["孟买", "Mumbai"], ["印度", "India"]),
            city("bangalore", "Asia/Kolkata", String(localized: "班加罗尔"), ["班加罗尔", "Bangalore", "Bengaluru"], ["印度", "India"]),
            city("kathmandu", "Asia/Kathmandu", String(localized: "加德满都"), ["加德满都", "Kathmandu"], ["尼泊尔", "Nepal"]),
            city("dhaka", "Asia/Dhaka", String(localized: "达卡"), ["达卡", "Dhaka"], ["孟加拉国", "Bangladesh"]),
            city("karachi", "Asia/Karachi", String(localized: "卡拉奇"), ["卡拉奇", "Karachi"], ["巴基斯坦", "Pakistan"]),
            city("dubai", "Asia/Dubai", String(localized: "迪拜"), ["迪拜", "Dubai"], ["阿联酋", "UAE", "阿布扎比", "Abu Dhabi"]),
            city("riyadh", "Asia/Riyadh", String(localized: "利雅得"), ["利雅得", "Riyadh"], ["沙特阿拉伯", "沙特", "Saudi Arabia"]),
            city("tehran", "Asia/Tehran", String(localized: "德黑兰"), ["德黑兰", "Tehran"], ["伊朗", "Iran"]),
            city("telAviv", "Asia/Jerusalem", String(localized: "特拉维夫"), ["特拉维夫", "Tel Aviv", "耶路撒冷", "Jerusalem"], ["以色列", "Israel"]),
            city("istanbul", "Europe/Istanbul", String(localized: "伊斯坦布尔"), ["伊斯坦布尔", "Istanbul"], ["土耳其", "Turkey", "Türkiye"]),
            city("almaty", "Asia/Almaty", String(localized: "阿拉木图"), ["阿拉木图", "Almaty"], ["哈萨克斯坦", "Kazakhstan"]),
            city("ulaanbaatar", "Asia/Ulaanbaatar", String(localized: "乌兰巴托"), ["乌兰巴托", "Ulaanbaatar"], ["蒙古", "Mongolia"]),
            city("moscow", "Europe/Moscow", String(localized: "莫斯科"), ["莫斯科", "Moscow"], ["俄罗斯", "Russia", "圣彼得堡", "Saint Petersburg"]),
            city("london", "Europe/London", String(localized: "伦敦"), ["伦敦", "London"], ["英国", "UK", "Britain", "England"]),
            city("dublin", "Europe/Dublin", String(localized: "都柏林"), ["都柏林", "Dublin"], ["爱尔兰", "Ireland"]),
            city("lisbon", "Europe/Lisbon", String(localized: "里斯本"), ["里斯本", "Lisbon"], ["葡萄牙", "Portugal"]),
            city("paris", "Europe/Paris", String(localized: "巴黎"), ["巴黎", "Paris"], ["法国", "France"]),
            city("berlin", "Europe/Berlin", String(localized: "柏林"), ["柏林", "Berlin"], ["德国", "Germany", "慕尼黑", "Munich", "法兰克福", "Frankfurt"]),
            city("amsterdam", "Europe/Amsterdam", String(localized: "阿姆斯特丹"), ["阿姆斯特丹", "Amsterdam"], ["荷兰", "Netherlands"]),
            city("brussels", "Europe/Brussels", String(localized: "布鲁塞尔"), ["布鲁塞尔", "Brussels"], ["比利时", "Belgium"]),
            city("zurich", "Europe/Zurich", String(localized: "苏黎世"), ["苏黎世", "Zurich", "Zürich"], ["瑞士", "Switzerland", "日内瓦", "Geneva"]),
            city("madrid", "Europe/Madrid", String(localized: "马德里"), ["马德里", "Madrid"], ["西班牙", "Spain", "巴塞罗那", "Barcelona"]),
            city("rome", "Europe/Rome", String(localized: "罗马"), ["罗马", "Rome"], ["意大利", "Italy", "米兰", "Milan"]),
            city("vienna", "Europe/Vienna", String(localized: "维也纳"), ["维也纳", "Vienna"], ["奥地利", "Austria"]),
            city("prague", "Europe/Prague", String(localized: "布拉格"), ["布拉格", "Prague"], ["捷克", "Czechia", "Czech Republic"]),
            city("warsaw", "Europe/Warsaw", String(localized: "华沙"), ["华沙", "Warsaw"], ["波兰", "Poland"]),
            city("stockholm", "Europe/Stockholm", String(localized: "斯德哥尔摩"), ["斯德哥尔摩", "Stockholm"], ["瑞典", "Sweden"]),
            city("helsinki", "Europe/Helsinki", String(localized: "赫尔辛基"), ["赫尔辛基", "Helsinki"], ["芬兰", "Finland"]),
            city("athens", "Europe/Athens", String(localized: "雅典"), ["雅典", "Athens"], ["希腊", "Greece"]),
            city("cairo", "Africa/Cairo", String(localized: "开罗"), ["开罗", "Cairo"], ["埃及", "Egypt"]),
            city("lagos", "Africa/Lagos", String(localized: "拉各斯"), ["拉各斯", "Lagos"], ["尼日利亚", "Nigeria"]),
            city("nairobi", "Africa/Nairobi", String(localized: "内罗毕"), ["内罗毕", "Nairobi"], ["肯尼亚", "Kenya"]),
            city("johannesburg", "Africa/Johannesburg", String(localized: "约翰内斯堡"), ["约翰内斯堡", "Johannesburg"], ["南非", "South Africa", "开普敦", "Cape Town"]),
            city("newYork", "America/New_York", String(localized: "纽约"), ["纽约", "New York", "NYC"],
                 ["美国", "USA", "United States", "华盛顿", "Washington", "波士顿", "Boston", "迈阿密", "Miami", "亚特兰大", "Atlanta"]),
            city("toronto", "America/Toronto", String(localized: "多伦多"), ["多伦多", "Toronto"], ["加拿大", "Canada", "蒙特利尔", "Montreal"]),
            city("chicago", "America/Chicago", String(localized: "芝加哥"), ["芝加哥", "Chicago"],
                 ["美国", "USA", "United States", "达拉斯", "Dallas", "休斯顿", "Houston", "奥斯汀", "Austin"]),
            city("denver", "America/Denver", String(localized: "丹佛"), ["丹佛", "Denver"], ["美国", "USA", "United States", "盐湖城", "Salt Lake City"]),
            city("phoenix", "America/Phoenix", String(localized: "凤凰城"), ["凤凰城", "Phoenix"], ["美国", "USA", "United States", "亚利桑那", "Arizona"]),
            city("losAngeles", "America/Los_Angeles", String(localized: "洛杉矶"), ["洛杉矶", "Los Angeles"], ["美国", "USA", "United States"]),
            city("sanFrancisco", "America/Los_Angeles", String(localized: "旧金山"), ["旧金山", "San Francisco", "硅谷", "Silicon Valley"],
                 ["美国", "USA", "United States", "圣何塞", "San Jose", "库比蒂诺", "Cupertino"]),
            city("seattle", "America/Los_Angeles", String(localized: "西雅图"), ["西雅图", "Seattle"], ["美国", "USA", "United States"]),
            city("vancouver", "America/Vancouver", String(localized: "温哥华"), ["温哥华", "Vancouver"], ["加拿大", "Canada"]),
            city("anchorage", "America/Anchorage", String(localized: "安克雷奇"), ["安克雷奇", "Anchorage"], ["阿拉斯加", "Alaska"]),
            city("honolulu", "Pacific/Honolulu", String(localized: "檀香山"), ["檀香山", "火奴鲁鲁", "Honolulu"], ["夏威夷", "Hawaii"]),
            city("mexicoCity", "America/Mexico_City", String(localized: "墨西哥城"), ["墨西哥城", "Mexico City"], ["墨西哥", "Mexico"]),
            city("bogota", "America/Bogota", String(localized: "波哥大"), ["波哥大", "Bogotá", "Bogota"], ["哥伦比亚", "Colombia"]),
            city("lima", "America/Lima", String(localized: "利马"), ["利马", "Lima"], ["秘鲁", "Peru"]),
            city("buenosAires", "America/Argentina/Buenos_Aires", String(localized: "布宜诺斯艾利斯"), ["布宜诺斯艾利斯", "Buenos Aires"], ["阿根廷", "Argentina"]),
            city("saoPaulo", "America/Sao_Paulo", String(localized: "圣保罗"), ["圣保罗", "São Paulo", "Sao Paulo"], ["巴西", "Brazil", "里约热内卢", "Rio de Janeiro"]),
            city("sydney", "Australia/Sydney", String(localized: "悉尼"), ["悉尼", "Sydney"], ["澳大利亚", "澳洲", "Australia", "堪培拉", "Canberra"]),
            city("melbourne", "Australia/Melbourne", String(localized: "墨尔本"), ["墨尔本", "Melbourne"], ["澳大利亚", "澳洲", "Australia"]),
            city("brisbane", "Australia/Brisbane", String(localized: "布里斯班"), ["布里斯班", "Brisbane"], ["澳大利亚", "澳洲", "Australia"]),
            city("adelaide", "Australia/Adelaide", String(localized: "阿德莱德"), ["阿德莱德", "Adelaide"], ["澳大利亚", "澳洲", "Australia"]),
            city("perth", "Australia/Perth", String(localized: "珀斯"), ["珀斯", "Perth"], ["澳大利亚", "澳洲", "Australia"]),
            city("auckland", "Pacific/Auckland", String(localized: "奥克兰"), ["奥克兰", "Auckland"], ["新西兰", "New Zealand", "惠灵顿", "Wellington"]),
        ]
        return table.compactMap { $0 }
    }

    /// 时区标识在这个系统上没有的城市不列出来
    private static func city(_ id: String, _ zone: String, _ name: String, _ names: [String], _ keywords: [String]) -> City? {
        TimeZone(identifier: zone).map { City(id: id, timeZone: $0, name: name, names: names, keywords: keywords) }
    }

    /// 第一次打开时列出的城市（本地时区另外显示）
    static let defaultCityIDs = ["beijing", "london", "newYork", "sanFrancisco", "tokyo"]

    /// 按设置里存的 key 找城市：表里没有的「tz:时区标识」也认
    static func city(id: String) -> City? {
        if let city = cities.first(where: { $0.id == id }) {
            return city
        }
        if id.hasPrefix("tz:"), let zone = TimeZone(identifier: String(id.dropFirst(3))) {
            return zoneCity(zone)
        }
        return nil
    }

    /// 代表一个时区的城市：表里第一个用这个时区的；没有的话用时区标识里的城市名，固定偏移写成「UTC+8」
    static func representative(for zone: TimeZone, at date: Date = Date()) -> City {
        if let city = cities.first(where: { $0.timeZone.identifier == zone.identifier }) {
            return city
        }
        return zoneCity(zone, at: date)
    }

    private static func zoneCity(_ zone: TimeZone, at date: Date = Date()) -> City {
        let identifier = zone.identifier
        if identifier.contains("/") {
            let name = (identifier.split(separator: "/").last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ")
            return City(id: "tz:" + identifier, timeZone: zone, name: name, names: [name])
        }
        // GMT+0800 这类固定偏移
        return City(id: "tz:" + identifier, timeZone: zone, name: offsetText(zone, at: date))
    }

    // MARK: - 搜索

    /// 每个城市能用来搜的词：名字、拼音、拼音首字母、别名、时区标识、时区缩写
    private static let searchIndex: [String: [String]] = {
        var index: [String: [String]] = [:]
        for city in cities {
            var words = (city.names + city.keywords).map { $0.lowercased() }
            for name in city.names where name.unicodeScalars.contains(where: { $0.properties.isIdeographic }) {
                let syllables = pinyinSyllables(name)
                words.append(syllables.joined())
                words.append(String(syllables.compactMap(\.first)))
            }
            words.append(city.timeZone.identifier.lowercased())
            words += abbreviations.filter { $0.value == city.timeZone.identifier }.map { $0.key.lowercased() }
            index[city.id] = words
        }
        return index
    }()

    private static func pinyinSyllables(_ text: String) -> [String] {
        let latin = text.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? ""
        return latin.lowercased().split(separator: " ").map(String.init)
    }

    /// 按中文名、拼音或首字母、英文名、国家、时区缩写或者时区标识找城市；开头就对上的排在前面
    static func search(_ query: String, excluding: Set<String> = [], limit: Int = 8) -> [City] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        var prefixed: [City] = []
        var contained: [City] = []
        for city in cities where !excluding.contains(city.id) {
            let words = searchIndex[city.id] ?? []
            if words.contains(where: { $0.hasPrefix(needle) }) {
                prefixed.append(city)
            } else if needle.count >= 2, words.contains(where: { $0.contains(needle) }) {
                contained.append(city)
            }
        }
        var result = prefixed + contained
        // 表里没有的时区：按时区标识找（比如 Boise、Reykjavik）
        if result.count < limit, needle.count >= 3 {
            let known = Set(cities.map { $0.timeZone.identifier })
            for identifier in TimeZone.knownTimeZoneIdentifiers where !known.contains(identifier)
                && identifier.lowercased().replacingOccurrences(of: "_", with: " ").contains(needle) {
                guard let zone = TimeZone(identifier: identifier) else { continue }
                let city = zoneCity(zone)
                if !excluding.contains(city.id) {
                    result.append(city)
                }
                if result.count >= limit { break }
            }
        }
        return Array(result.prefix(limit))
    }

    // MARK: - 写法

    /// 「UTC+8」「UTC−7」「UTC+5:30」「UTC」
    static func offsetText(_ zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        guard seconds != 0 else { return "UTC" }
        let sign = seconds > 0 ? "+" : "\u{2212}"
        let minutes = abs(seconds) / 60
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "UTC\(sign)\(hours)" : String(format: "UTC%@%d:%02d", sign, hours, rest)
    }

    /// 时区缩写，比如 PDT、BST；系统只给得出「GMT+8」这种的时候为 nil
    static func abbreviation(_ zone: TimeZone, at date: Date) -> String? {
        guard let text = zone.abbreviation(for: date), !text.isEmpty, text.allSatisfy({ $0.isLetter }) else { return nil }
        // UTC 这一行不用再写一遍 GMT
        if text == "UTC" || (text == "GMT" && zone.identifier == "UTC") {
            return nil
        }
        return text
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter = DateFormatter()

    /// 「21:00」
    static func timeText(_ date: Date, in zone: TimeZone) -> String {
        timeFormatter.timeZone = zone
        return timeFormatter.string(from: date)
    }

    /// 「10月2日周五」「Fri, Oct 2」
    static func dateText(_ date: Date, in zone: TimeZone) -> String {
        dateFormatter.locale = Localization.locale
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        dateFormatter.timeZone = zone
        return dateFormatter.string(from: date)
    }

    /// 那里的日子比本地早一天（-1）、晚一天（+1）还是同一天
    static func dayOffset(_ date: Date, in zone: TimeZone, from local: TimeZone) -> Int {
        dayNumber(date, in: zone) - dayNumber(date, in: local)
    }

    private static func dayNumber(_ date: Date, in zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let day = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) else { return 0 }
        return Int((day.timeIntervalSince1970 / 86_400).rounded())
    }

    /// 那里是一天里的第几分钟（0…1439）
    static func minuteOfDay(_ date: Date, in zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// 上班时间：9:00–18:00
    static let workingMinutes = 540..<1080

    /// 一天里的几段：夜里、早晚、上班时间，画在每一行的时间条上
    enum DayPart: CaseIterable {
        case night, edge, work

        static func of(minute: Int) -> DayPart {
            switch minute {
            case workingMinutes: return .work
            case 420..<540, 1080..<1320: return .edge
            default: return .night
            }
        }
    }

    /// 从 day（本地那天的零点）开始的 24 小时里，所有时区都在上班时间的第一段（按 15 分钟一格算）
    static func commonWorkingHours(on day: Date, zones: [TimeZone]) -> DateInterval? {
        guard zones.count > 1 else { return nil }
        var start: Date?
        for step in 0...96 {
            let moment = day.addingTimeInterval(TimeInterval(step * 900))
            let working = step < 96 && zones.allSatisfy { workingMinutes.contains(minuteOfDay(moment, in: $0)) }
            if working, start == nil {
                start = moment
            } else if !working, let begin = start {
                return DateInterval(start: begin, end: moment)
            }
        }
        return nil
    }

    // MARK: - 认时区

    /// 时区缩写。大多数都按那个地区算（会自己换夏令时），夏令时、冬令时写反了也照当地实际的时间算，另外提示一句
    static let abbreviations: [String: String] = [
        "UTC": "UTC", "GMT": "UTC",
        "PST": "America/Los_Angeles", "PDT": "America/Los_Angeles", "PT": "America/Los_Angeles",
        "MST": "America/Denver", "MDT": "America/Denver", "MT": "America/Denver",
        "CST": "America/Chicago", "CDT": "America/Chicago", "CT": "America/Chicago",
        "EST": "America/New_York", "EDT": "America/New_York", "ET": "America/New_York",
        "AKST": "America/Anchorage", "AKDT": "America/Anchorage", "HST": "Pacific/Honolulu",
        "AST": "America/Halifax", "ADT": "America/Halifax", "NST": "America/St_Johns", "NDT": "America/St_Johns",
        "BST": "Europe/London", "WET": "Europe/Lisbon", "WEST": "Europe/Lisbon",
        "CET": "Europe/Paris", "CEST": "Europe/Paris", "EET": "Europe/Athens", "EEST": "Europe/Athens", "MSK": "Europe/Moscow",
        "IST": "Asia/Kolkata", "PKT": "Asia/Karachi", "ICT": "Asia/Bangkok", "WIB": "Asia/Jakarta", "SGT": "Asia/Singapore",
        "MYT": "Asia/Kuala_Lumpur", "PHT": "Asia/Manila", "HKT": "Asia/Hong_Kong", "JST": "Asia/Tokyo", "KST": "Asia/Seoul",
        "GST": "Asia/Dubai", "AEST": "Australia/Sydney", "AEDT": "Australia/Sydney", "AET": "Australia/Sydney",
        "ACST": "Australia/Adelaide", "ACDT": "Australia/Adelaide", "AWST": "Australia/Perth",
        "NZST": "Pacific/Auckland", "NZDT": "Pacific/Auckland", "BRT": "America/Sao_Paulo", "ART": "America/Argentina/Buenos_Aires",
        "SAST": "Africa/Johannesburg",
    ]

    private static let standardAbbreviations: Set<String> = ["PST", "MST", "CST", "EST", "AKST", "AST", "NST", "WET", "CET", "EET", "AEST", "ACST", "NZST"]
    private static let daylightAbbreviations: Set<String> = ["PDT", "MDT", "CDT", "EDT", "AKDT", "ADT", "NDT", "BST", "WEST", "CEST", "EEST", "AEDT", "ACDT", "NZDT"]

    /// 只写地区不写城市的说法，后面跟「时间」
    private static let chinesePhrases: [String: String] = [
        "美东": "America/New_York", "美国东部": "America/New_York", "东部": "America/New_York",
        "美西": "America/Los_Angeles", "美国西部": "America/Los_Angeles", "西部": "America/Los_Angeles",
        "太平洋": "America/Los_Angeles", "北美太平洋": "America/Los_Angeles",
        "美中": "America/Chicago", "美国中部": "America/Chicago", "中部": "America/Chicago",
        "山地": "America/Denver", "美国山地": "America/Denver",
        "欧洲中部": "Europe/Paris", "中欧": "Europe/Paris", "欧洲东部": "Europe/Athens", "东欧": "Europe/Athens",
        "欧洲西部": "Europe/Lisbon", "西欧": "Europe/Lisbon",
        "澳洲东部": "Australia/Sydney", "澳大利亚东部": "Australia/Sydney",
        "中国标准": "Asia/Shanghai", "格林尼治标准": "UTC", "格林威治标准": "UTC", "格林尼治": "UTC", "格林威治": "UTC",
    ]

    /// 英文的说法，后面跟 time
    private static let englishPhrases: [String: String] = [
        "pacific": "America/Los_Angeles", "pacific standard": "America/Los_Angeles", "pacific daylight": "America/Los_Angeles",
        "eastern": "America/New_York", "eastern standard": "America/New_York", "eastern daylight": "America/New_York",
        "central": "America/Chicago", "central standard": "America/Chicago", "central daylight": "America/Chicago",
        "mountain": "America/Denver", "mountain standard": "America/Denver", "mountain daylight": "America/Denver",
        "alaska": "America/Anchorage", "hawaii": "Pacific/Honolulu", "atlantic": "America/Halifax",
        "greenwich mean": "UTC", "coordinated universal": "UTC", "universal": "UTC", "british summer": "Europe/London",
        "central european": "Europe/Paris", "central european summer": "Europe/Paris",
        "eastern european": "Europe/Athens", "western european": "Europe/Lisbon",
        "india standard": "Asia/Kolkata", "japan standard": "Asia/Tokyo", "korea standard": "Asia/Seoul",
        "china standard": "Asia/Shanghai", "australian eastern": "Australia/Sydney",
    ]

    /// 城市名、只对应一个时区的国家名，加上上面的说法：中文的和英文的分开，长的在前（先认「美国东部」再认「东部」）
    private static let phraseTable: (chinese: [(String, String)], english: [(String, String)]) = {
        var owners: [String: Set<String>] = [:]
        for city in cities {
            for word in city.names + city.keywords {
                owners[word, default: []].insert(city.timeZone.identifier)
            }
        }
        var chinese = chinesePhrases
        var english = englishPhrases
        for (word, zones) in owners where zones.count == 1 {
            guard let zone = zones.first else { continue }
            if word.unicodeScalars.contains(where: { $0.properties.isIdeographic }) {
                chinese[word] = chinese[word] ?? zone
            } else if word.count > 2 {
                english[word.lowercased()] = english[word.lowercased()] ?? zone
            }
        }
        let longestFirst = { (a: (String, String), b: (String, String)) in a.0.count != b.0.count ? a.0.count > b.0.count : a.0 < b.0 }
        return (chinese.map { ($0.key, $0.value) }.sorted(by: longestFirst), english.map { ($0.key, $0.value) }.sorted(by: longestFirst))
    }()

    private static func alternation(_ words: [(String, String)]) -> String {
        words.map { NSRegularExpression.escapedPattern(for: $0.0) }.joined(separator: "|")
    }

    private static let chinesePhrase = try! NSRegularExpression(pattern: "(" + alternation(phraseTable.chinese) + #")\s*时间"#)
    private static let englishPhrase = try! NSRegularExpression(
        pattern: #"(?i)(?<![A-Za-z])("# + alternation(phraseTable.english) + #")\s+time(?![A-Za-z])"#)
    /// 只写了城市名（「伦敦 3pm」）
    private static let chineseCity = try! NSRegularExpression(pattern: "(" + alternation(phraseTable.chinese.filter { !chinesePhrases.keys.contains($0.0) }) + ")")
    private static let englishCity = try! NSRegularExpression(
        pattern: #"(?i)(?<![A-Za-z])("# + alternation(phraseTable.english.filter { !englishPhrases.keys.contains($0.0) }) + #")(?![A-Za-z])"#)
    private static let offsetPattern = try! NSRegularExpression(
        pattern: #"(?i)(?<![A-Za-z])(?:UTC|GMT)\s*([+\-])\s*(\d{1,2})(?::?(\d{2}))?(?!\d)"#)
    private static let chineseOffset = try! NSRegularExpression(pattern: #"([东西])\s*(\d{1,2}|[一二三四五六七八九十]{1,3})\s*区|(零时区|中时区)"#)
    private static let abbreviationPattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])("# + abbreviations.keys.sorted { $0.count > $1.count }.joined(separator: "|") + #")(?![A-Za-z])"#)
    private static let identifierPattern = try! NSRegularExpression(pattern: #"(?<![A-Za-z/])((?:Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)/[A-Za-z_]+(?:/[A-Za-z_]+)?)"#)
    private static let localWords = try! NSRegularExpression(pattern: #"(?i)当地时间|本地时间|(?<![A-Za-z])local time(?![A-Za-z])"#)

    struct ZoneMatch: Equatable {
        var zone: TimeZone
        /// 文字里写时区的那一段
        var text: String
        var range: NSRange
        /// 写的是时区缩写（PST）的话是缩写
        var abbreviation: String?
    }

    /// 找出文字里写的时区。都没写时为 nil
    static func findZone(in text: String, local: TimeZone, now: Date) -> ZoneMatch? {
        let string = text as NSString
        let full = NSRange(location: 0, length: string.length)
        func match(_ regex: NSRegularExpression) -> NSTextCheckingResult? {
            regex.firstMatch(in: text, range: full)
        }
        func group(_ result: NSTextCheckingResult, _ index: Int) -> String? {
            let range = result.range(at: index)
            return range.location == NSNotFound ? nil : string.substring(with: range)
        }
        func found(_ zone: TimeZone?, _ result: NSTextCheckingResult, abbreviation: String? = nil) -> ZoneMatch? {
            zone.map { ZoneMatch(zone: $0, text: string.substring(with: result.range), range: result.range, abbreviation: abbreviation) }
        }

        // UTC+8、GMT-05:00
        if let result = match(offsetPattern), let sign = group(result, 1), let hours = group(result, 2).flatMap({ Int($0) }), hours <= 14 {
            let minutes = group(result, 3).flatMap { Int($0) } ?? 0
            let seconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
            return found(seconds == 0 ? TimeZone(identifier: "UTC") : TimeZone(secondsFromGMT: seconds), result)
        }
        // 东八区、西五区
        if let result = match(chineseOffset) {
            if group(result, 3) != nil {
                return found(TimeZone(identifier: "UTC"), result)
            }
            if let side = group(result, 1), let number = group(result, 2), let hours = Int(number) ?? chineseNumber(number), (1...12).contains(hours) {
                return found(TimeZone(secondsFromGMT: hours * 3600 * (side == "东" ? 1 : -1)), result)
            }
        }
        // 北京时间、Pacific Time、Tokyo time
        if let result = match(chinesePhrase), let word = group(result, 1), let zone = phraseTable.chinese.first(where: { $0.0 == word })?.1 {
            return found(TimeZone(identifier: zone), result)
        }
        if let result = match(englishPhrase), let word = group(result, 1)?.lowercased(), let zone = phraseTable.english.first(where: { $0.0 == word })?.1 {
            return found(TimeZone(identifier: zone), result)
        }
        // 当地时间
        if let result = match(localWords) {
            return found(local, result)
        }
        // PST、JST
        if let result = match(abbreviationPattern), let word = group(result, 1) {
            return found(abbreviationZone(word, local: local, now: now), result, abbreviation: word == "UTC" || word == "GMT" ? nil : word)
        }
        // America/New_York
        if let result = match(identifierPattern), let word = group(result, 1), let zone = TimeZone(identifier: word) {
            return found(zone, result)
        }
        // 只写了城市名：伦敦 3pm、3pm London
        if let result = match(chineseCity), let word = group(result, 1), let zone = phraseTable.chinese.first(where: { $0.0 == word })?.1 {
            return found(TimeZone(identifier: zone), result)
        }
        if let result = match(englishCity), let word = group(result, 1)?.lowercased(), let zone = phraseTable.english.first(where: { $0.0 == word })?.1 {
            return found(TimeZone(identifier: zone), result)
        }
        return nil
    }

    /// 本地用的就是这个缩写的话按本地算（在爱尔兰写 IST 是爱尔兰的时间）；
    /// 在东八区写的 CST 是中国标准时间，在别处是美国中部时间
    static func abbreviationZone(_ word: String, local: TimeZone, now: Date) -> TimeZone? {
        if local.abbreviation(for: now) == word {
            return local
        }
        if word == "CST", local.secondsFromGMT(for: now) == 8 * 3600 {
            return local
        }
        return abbreviations[word].flatMap { TimeZone(identifier: $0) }
    }

    // MARK: - 认日期和时间

    struct Parsed: Equatable {
        /// 认出来的时刻；只写了时区没写时间时是现在
        var date: Date
        /// 按哪个时区理解（没写时区就是本地）
        var zone: TimeZone
        /// 文字里写时区的那一段，比如「PST」「北京时间」；没写时为 nil
        var zoneText: String?
        var hasTime: Bool
        /// 写的是冬令时的缩写、那天却在用夏令时（或者反过来），按当地实际的时间算了，提示一句
        var hint: String?

        var hasZone: Bool { zoneText != nil }
    }

    private static let clockTime = try! NSRegularExpression(
        pattern: #"(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里|夜间|今晚|明晚|今早|明早)?\s*(?<![\d:])(\d{1,2}):(\d{2})(?::(\d{2}))?(?![\d:])\s*([AaPp]\.?\s?[Mm]\.?(?![A-Za-z]))?"#)
    private static let meridiemTime = try! NSRegularExpression(pattern: #"(?<![\d:.])(\d{1,2})\s*([AaPp]\.?\s?[Mm]\.?)(?![A-Za-z])"#)
    private static let chineseTime = try! NSRegularExpression(
        pattern: #"(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里|夜间|今晚|明晚|今早|明早)?\s*(\d{1,2}|[零〇一二两三四五六七八九十]{1,3})\s*[点點时時](?:\s*(半|一刻|三刻|整|(\d{1,2}|[零〇一二两三四五六七八九十]{1,3})\s*分?))?"#)
    private static let namedTime = try! NSRegularExpression(pattern: #"(?i)(?<![A-Za-z])(noon|midday|midnight)(?![A-Za-z])|(正午|午夜|半夜|中午)(?!\s*[\d零〇一二两三四五六七八九十])"#)

    private static let isoDay = try! NSRegularExpression(pattern: #"(?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)"#)
    private static let chineseDay = try! NSRegularExpression(pattern: #"(?:(\d{4})\s*年\s*)?(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?"#)
    private static let monthNames = "january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec"
    private static let englishMonthFirst = try! NSRegularExpression(
        pattern: #"(?i)(?<![A-Za-z])("# + monthNames + #")\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?![\d:])(?:,?\s+(\d{4})(?![\d:]))?"#)
    private static let englishDayFirst = try! NSRegularExpression(
        pattern: #"(?i)(?<![\d:])(\d{1,2})(?:st|nd|rd|th)?\s+("# + monthNames + #")\.?(?![A-Za-z])(?:,?\s+(\d{4})(?![\d:]))?"#)
    private static let relativeDay = try! NSRegularExpression(
        pattern: #"大后天|后天|明天|明日|今天|今日|今晚|明晚|今早|明早|昨天|昨日|昨晚|前天|(?i:(?<![A-Za-z])(today|tonight|tomorrow|yesterday)(?![A-Za-z]))"#)
    private static let chineseWeekday = try! NSRegularExpression(pattern: #"(下下个?|下个?|这个?|本|上个?)?\s*(?:周|星期|礼拜)\s*([一二三四五六日天1-7])"#)
    private static let englishWeekday = try! NSRegularExpression(
        pattern: #"(?i)(?<![A-Za-z])(next\s+|this\s+|last\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tues|tue|wed|thurs|thur|thu|fri|sat|sun)\.?(?![A-Za-z])"#)

    /// 从一段文字里认出时间和时区：「3pm PST」「北京时间晚上 9 点」「明天 10:00 伦敦时间」「2026-10-02T15:00:00-07:00」。
    /// 没写日子的按那个时区接下来的那一次算；只写了时区（或者只选中一个城市名）时看那里现在几点。
    static func parse(_ text: String, now: Date = Date(), local: TimeZone = .current) -> Parsed? {
        let normalized = normalize(text)
        guard !normalized.isEmpty, normalized.count <= 120 else { return nil }
        if let parsed = parseStamp(normalized) {
            return parsed
        }
        var rest = normalized
        let zoneMatch = findZone(in: normalized, local: local, now: now)
        if let zoneMatch {
            rest = (normalized as NSString).replacingCharacters(in: zoneMatch.range, with: " ")
        }
        let zone = zoneMatch?.zone ?? local
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        guard let time = findTime(in: rest) else {
            // 只写了时区，或者只选中了一个城市：看那里现在几点
            guard let zoneMatch else { return nil }
            return Parsed(date: now, zone: zone, zoneText: zoneMatch.text, hasTime: false, hint: nil)
        }
        let day = findDay(in: rest, now: now, calendar: calendar)
        var parts = day ?? calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = time.hour
        parts.minute = time.minute
        parts.second = time.second
        guard var date = calendar.date(from: parts) else { return nil }
        if time.nextDay, let next = calendar.date(byAdding: .day, value: 1, to: date) {
            date = next
        }
        // 没写哪天：按接下来的那一次算（「3pm PST」说的多半是还没到的那个下午），过去不到一小时的还算今天
        if day == nil, date < now.addingTimeInterval(-3600), let next = calendar.date(byAdding: .day, value: 1, to: date) {
            date = next
        }
        let hint = zoneMatch?.abbreviation.flatMap { dstHint(abbreviation: $0, zone: zone, date: date) }
        return Parsed(date: date, zone: zone, zoneText: zoneMatch?.text, hasTime: true, hint: hint)
    }

    /// 全角的冒号、加号、减号、括号换成半角，连续的空白合成一个
    static func normalize(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (from, to) in [("：", ":"), ("＋", "+"), ("－", "-"), ("\u{2212}", "-"), ("\u{2013}", "-"), ("（", "("), ("）", ")"), ("，", ","), ("\u{3000}", " ")] {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// 带着时区偏移的完整时间戳：ISO 8601（2026-10-02T15:00:00-07:00、…Z、到分钟为止也行）、邮件头里的 RFC 2822
    private static func parseStamp(_ text: String) -> Parsed? {
        guard text.count >= 16, stampOffsetText(text) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in stampFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return Parsed(date: date, zone: stampZone(text), zoneText: stampOffsetText(text), hasTime: true, hint: nil)
            }
        }
        return nil
    }

    private static let stampFormats: [String] = {
        var formats: [String] = []
        for separator in ["'T'", " "] {
            for time in ["HH:mm:ss.SSS", "HH:mm:ss", "HH:mm"] {
                for zone in ["XXXXX", "XX", " XXXXX", " Z"] {
                    formats.append("yyyy-MM-dd" + separator + time + zone)
                }
            }
        }
        return formats + ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"]
    }()

    private static let stampOffset = try! NSRegularExpression(pattern: #"(?:([+\-])(\d{2}):?(\d{2})|(Z))$"#)

    private static func stampOffsetText(_ text: String) -> String? {
        let string = text as NSString
        guard let result = stampOffset.firstMatch(in: text, range: NSRange(location: 0, length: string.length)) else { return nil }
        return string.substring(with: result.range)
    }

    private static func stampZone(_ text: String) -> TimeZone {
        let string = text as NSString
        guard let result = stampOffset.firstMatch(in: text, range: NSRange(location: 0, length: string.length)),
              result.range(at: 1).location != NSNotFound,
              let hours = Int(string.substring(with: result.range(at: 2))), let minutes = Int(string.substring(with: result.range(at: 3))) else {
            return TimeZone(identifier: "UTC") ?? .gmt
        }
        let seconds = (hours * 3600 + minutes * 60) * (string.substring(with: result.range(at: 1)) == "-" ? -1 : 1)
        return seconds == 0 ? TimeZone(identifier: "UTC") ?? .gmt : TimeZone(secondsFromGMT: seconds) ?? .gmt
    }

    struct Time: Equatable {
        var hour: Int
        var minute: Int
        var second = 0
        /// 「晚上 12 点」：第二天的 0 点
        var nextDay = false
    }

    static func findTime(in text: String) -> Time? {
        let string = text as NSString
        let full = NSRange(location: 0, length: string.length)
        func group(_ result: NSTextCheckingResult, _ index: Int) -> String? {
            let range = result.range(at: index)
            return range.location == NSNotFound ? nil : string.substring(with: range)
        }
        // 15:30、下午 3:30、3:30 PM
        if let result = clockTime.firstMatch(in: text, range: full), let hour = group(result, 2).flatMap({ Int($0) }),
           let minute = group(result, 3).flatMap({ Int($0) }), minute < 60 {
            let second = group(result, 4).flatMap { Int($0) } ?? 0
            if second < 60, let adjusted = hour24(hour, period: group(result, 5) ?? group(result, 1)) {
                return Time(hour: adjusted.hour, minute: minute, second: second, nextDay: adjusted.nextDay)
            }
        }
        // 3pm、11 a.m.
        if let result = meridiemTime.firstMatch(in: text, range: full), let hour = group(result, 1).flatMap({ Int($0) }),
           let adjusted = hour24(hour, period: group(result, 2)) {
            return Time(hour: adjusted.hour, minute: 0, nextDay: adjusted.nextDay)
        }
        // 晚上 9 点、下午三点半、10 点 15 分
        if let result = chineseTime.firstMatch(in: text, range: full), let hourText = group(result, 2),
           let hour = Int(hourText) ?? chineseNumber(hourText) {
            var minute = 0
            switch group(result, 3) {
            case "半"?: minute = 30
            case "一刻"?: minute = 15
            case "三刻"?: minute = 45
            default:
                if let minuteText = group(result, 4) {
                    minute = Int(minuteText) ?? chineseNumber(minuteText) ?? 60
                }
            }
            if minute < 60, let adjusted = hour24(hour, period: group(result, 1)) {
                return Time(hour: adjusted.hour, minute: minute, nextDay: adjusted.nextDay)
            }
        }
        // noon、午夜
        if let result = namedTime.firstMatch(in: text, range: full) {
            let word = (group(result, 1) ?? group(result, 2) ?? "").lowercased()
            return ["midnight", "午夜", "半夜"].contains(word) ? Time(hour: 0, minute: 0, nextDay: true) : Time(hour: 12, minute: 0)
        }
        return nil
    }

    /// 按上午、下午这类说法换成 24 小时制
    static func hour24(_ hour: Int, period: String?) -> (hour: Int, nextDay: Bool)? {
        guard (0...24).contains(hour) else { return nil }
        guard let period else {
            return hour == 24 ? (0, true) : (hour, false)
        }
        let word = period.lowercased().filter { $0.isLetter }
        switch word {
        case "am", "pm":
            guard (1...12).contains(hour) else { return nil }
            if word == "am" {
                return (hour == 12 ? 0 : hour, false)
            }
            return (hour == 12 ? 12 : hour + 12, false)
        case "凌晨":
            if hour == 12 { return (0, false) }
            return hour <= 6 ? (hour, false) : nil
        case "中午":
            if hour <= 3 { return (hour + 12, false) }
            return hour <= 12 ? (hour, false) : nil
        case "下午", "傍晚":
            if hour < 12 { return (hour + 12, false) }
            return hour <= 23 ? (hour, false) : nil
        case "晚上", "今晚", "明晚", "夜里", "夜间":
            if hour == 12 || hour == 24 { return (0, true) }
            // 夜里两点：过了零点的那个两点
            if hour <= 5, word == "夜里" || word == "夜间" { return (hour, true) }
            if hour < 12 { return (hour + 12, false) }
            return hour <= 23 ? (hour, false) : nil
        default:
            // 早上、早晨、上午、今早、明早
            return hour <= 12 ? (hour, false) : nil
        }
    }

    /// 文字里写的日子（年月日，按 calendar 的时区）；没写为 nil
    static func findDay(in text: String, now: Date, calendar: Calendar) -> DateComponents? {
        let string = text as NSString
        let full = NSRange(location: 0, length: string.length)
        func group(_ result: NSTextCheckingResult, _ index: Int) -> String? {
            let range = result.range(at: index)
            return range.location == NSNotFound ? nil : string.substring(with: range)
        }
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        func day(year: Int?, month: Int, day: Int) -> DateComponents? {
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
            if let year {
                return valid(DateComponents(year: year, month: month, day: day), calendar: calendar)
            }
            // 没写年份：取离今天最近的那一年（12 月底说「1 月 3 日」是明年）
            let thisYear = today.year ?? 2000
            let candidates = [thisYear - 1, thisYear, thisYear + 1].compactMap {
                valid(DateComponents(year: $0, month: month, day: day), calendar: calendar)
            }
            return candidates.min { a, b in
                abs(calendar.date(from: a)?.timeIntervalSince(now) ?? .infinity) < abs(calendar.date(from: b)?.timeIntervalSince(now) ?? .infinity)
            }
        }
        func shifted(_ days: Int) -> DateComponents? {
            guard let start = calendar.date(from: today), let date = calendar.date(byAdding: .day, value: days, to: start) else { return nil }
            return calendar.dateComponents([.year, .month, .day], from: date)
        }

        if let result = isoDay.firstMatch(in: text, range: full), let year = group(result, 1).flatMap({ Int($0) }),
           let month = group(result, 2).flatMap({ Int($0) }), let dayOfMonth = group(result, 3).flatMap({ Int($0) }) {
            return day(year: year, month: month, day: dayOfMonth)
        }
        if let result = chineseDay.firstMatch(in: text, range: full), let month = group(result, 2).flatMap({ Int($0) }),
           let dayOfMonth = group(result, 3).flatMap({ Int($0) }) {
            return day(year: group(result, 1).flatMap { Int($0) }, month: month, day: dayOfMonth)
        }
        if let result = englishMonthFirst.firstMatch(in: text, range: full), let month = group(result, 1).flatMap(monthNumber),
           let dayOfMonth = group(result, 2).flatMap({ Int($0) }) {
            return day(year: group(result, 3).flatMap { Int($0) }, month: month, day: dayOfMonth)
        }
        if let result = englishDayFirst.firstMatch(in: text, range: full), let month = group(result, 2).flatMap(monthNumber),
           let dayOfMonth = group(result, 1).flatMap({ Int($0) }) {
            return day(year: group(result, 3).flatMap { Int($0) }, month: month, day: dayOfMonth)
        }
        if let result = relativeDay.firstMatch(in: text, range: full) {
            switch string.substring(with: result.range).lowercased() {
            case "大后天": return shifted(3)
            case "后天": return shifted(2)
            case "明天", "明日", "明晚", "明早", "tomorrow": return shifted(1)
            case "昨天", "昨日", "昨晚", "yesterday": return shifted(-1)
            case "前天": return shifted(-2)
            default: return shifted(0)
            }
        }
        // 星期一 = 1 … 星期日 = 7
        let current = ((calendar.component(.weekday, from: now) + 5) % 7) + 1
        if let result = chineseWeekday.firstMatch(in: text, range: full), let target = group(result, 2).flatMap(chineseWeekdayNumber) {
            let prefix = group(result, 1) ?? ""
            if prefix.hasPrefix("下下") { return shifted(14 - current + target) }
            if prefix.hasPrefix("下") { return shifted(7 - current + target) }
            if prefix.hasPrefix("上") { return shifted(target - current - 7) }
            if prefix.hasPrefix("这") || prefix == "本" { return shifted(target - current) }
            return shifted((target - current + 7) % 7)
        }
        if let result = englishWeekday.firstMatch(in: text, range: full), let target = group(result, 2).flatMap(englishWeekdayNumber) {
            switch group(result, 1)?.lowercased().trimmingCharacters(in: .whitespaces) {
            case "next"?: return shifted((target - current + 6) % 7 + 1)
            case "last"?: return shifted(-((current - target + 6) % 7 + 1))
            case "this"?: return shifted(target - current)
            default: return shifted((target - current + 7) % 7)
            }
        }
        return nil
    }

    private static func valid(_ parts: DateComponents, calendar: Calendar) -> DateComponents? {
        guard let date = calendar.date(from: parts) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == parts.year && back.month == parts.month && back.day == parts.day ? back : nil
    }

    private static func monthNumber(_ name: String) -> Int? {
        let names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return names.firstIndex(of: String(name.lowercased().prefix(3))).map { $0 + 1 }
    }

    private static func chineseWeekdayNumber(_ text: String) -> Int? {
        if let number = Int(text) { return (1...7).contains(number) ? number : nil }
        return ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7][text]
    }

    private static func englishWeekdayNumber(_ text: String) -> Int? {
        let names = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        return names.firstIndex(of: String(text.lowercased().prefix(3))).map { $0 + 1 }
    }

    /// 零到五十九的中文数字：十、十二、二十、三十五、两
    static func chineseNumber(_ text: String) -> Int? {
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let characters = Array(text)
        guard !characters.isEmpty else { return nil }
        if let ten = characters.firstIndex(of: "十") {
            let tens = ten == 0 ? 1 : (characters.count > ten ? digits[characters[0]] : nil)
            let ones = ten + 1 < characters.count ? digits[characters[ten + 1]] : 0
            guard let tens, let ones, ten <= 1, characters.count <= ten + 2 else { return nil }
            return tens * 10 + ones
        }
        guard characters.count == 1 else { return nil }
        return digits[characters[0]]
    }

    /// 缩写写的是冬令时、那天当地却在用夏令时（或者反过来）
    static func dstHint(abbreviation: String, zone: TimeZone, date: Date) -> String? {
        let daylight = zone.isDaylightSavingTime(for: date)
        guard (standardAbbreviations.contains(abbreviation) && daylight) || (daylightAbbreviations.contains(abbreviation) && !daylight) else {
            return nil
        }
        let name = representative(for: zone, at: date).name
        let offset = offsetText(zone, at: date)
        return daylight
            ? String(localized: "\(abbreviation) 按\(name)当地的时间算：这一天那里在用夏令时（\(offset)）")
            : String(localized: "\(abbreviation) 按\(name)当地的时间算：这一天那里没有夏令时（\(offset)）")
    }
}
