import Foundation

/// 从一段文字里找出链接、邮箱、电话号码和 IP 地址，按出现的顺序、去掉重复。纯逻辑，方便测试。
enum InfoExtractor {
    enum Kind: CaseIterable {
        case link, email, phone, ip

        var title: String {
            switch self {
            case .link: return String(localized: "链接")
            case .email: return String(localized: "邮箱")
            case .phone: return String(localized: "电话")
            case .ip: return String(localized: "IP 地址")
            }
        }
    }

    struct Item: Equatable {
        var kind: Kind
        var value: String
    }

    static let maxLength = 100_000

    private static let email = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}"#)
    private static let ipv4 = try! NSRegularExpression(
        pattern: #"(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?::\d{1,5})?(?!\d)(?!\.\d)"#)
    /// 手机号（可以带 +86、中间用空格或短横线隔开）、带区号的固定电话、400/800 电话、+ 开头的国际号码
    private static let phone = try! NSRegularExpression(pattern: [
        #"(?<![\d+])(?:\+?86[- ]?)?1[3-9]\d(?:[- ]?\d{4}){2}(?!\d)"#,
        #"(?<![\d(])(?:\(0\d{2,3}\)\s?|0\d{2,3}-)\d{7,8}(?:-\d{1,6})?(?!\d)"#,
        #"(?<!\d)[48]00-?\d{3}-?\d{4}(?!\d)"#,
        #"(?<![\w+])\+(?:[1-9]\d{0,2})[- ]?(?:\(\d{1,4}\)[- ]?)?\d{1,4}(?:[- ]?\d{2,4}){2,4}(?!\d)"#,
        #"(?<![\d(])\(\d{3}\)\s?\d{3}-\d{4}(?!\d)"#,
    ].joined(separator: "|"))
    private static let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// 没写 http:// 的网址只认这些常见后缀（免得把 main.py、README.md 这样的文件名当成网址）
    /// （.app、.sh、.cc 这些也是文件扩展名，不算）
    private static let bareDomainSuffixes: Set<String> = [
        "com", "net", "org", "cn", "io", "dev", "ai", "co", "me", "info", "edu", "gov", "xyz", "top", "tech",
        "site", "tv", "uk", "jp", "hk", "tw", "us", "de", "fr", "gg", "link",
    ]

    /// 网址里遇到这些字符就算结束（中文里夹着网址时常见）
    private static let urlTerminators = CharacterSet(charactersIn: "，。！？；：、“”‘’（）【】《》「」『』…　")

    static func extract(_ text: String) -> [Item] {
        guard !text.isEmpty, text.count <= maxLength else { return [] }
        let string = text as NSString
        let full = NSRange(location: 0, length: string.length)
        var found: [(location: Int, item: Item)] = []
        var taken = IndexSet()
        var seen = Set<String>()

        func add(_ kind: Kind, _ value: String, _ range: NSRange) {
            guard !value.isEmpty, !taken.intersects(integersIn: range.location..<NSMaxRange(range)) else { return }
            taken.insert(integersIn: range.location..<NSMaxRange(range))
            let key: String
            switch kind {
            case .phone: key = "phone:" + value.filter(\.isNumber)
            case .link, .email: key = "\(kind):" + value.lowercased()
            case .ip: key = "ip:" + value
            }
            guard seen.insert(key).inserted else { return }
            found.append((range.location, Item(kind: kind, value: value)))
        }

        // 邮箱最先找，免得里面的域名被当成网址
        for match in email.matches(in: text, range: full) {
            add(.email, string.substring(with: match.range), match.range)
        }
        for match in linkDetector.matches(in: text, range: full) {
            guard let url = match.url, let scheme = url.scheme?.lowercased(), scheme != "mailto", scheme != "tel" else { continue }
            var range = match.range
            var value = string.substring(with: range)
            if let cut = value.rangeOfCharacter(from: urlTerminators) {
                value = String(value[..<cut.lowerBound])
                range.length = (value as NSString).length
            }
            guard isLikelyLink(value) else { continue }
            add(.link, value, range)
        }
        for match in ipv4.matches(in: text, range: full) {
            add(.ip, string.substring(with: match.range), match.range)
        }
        for match in phone.matches(in: text, range: full) {
            add(.phone, string.substring(with: match.range), match.range)
        }
        return found.sorted { $0.location < $1.location }.map(\.item)
    }

    /// 带协议的都算；没带协议的要以 www. 开头、带路径，或者是常见的后缀；纯 IP 留给 IP 地址
    private static func isLikelyLink(_ value: String) -> Bool {
        let lowered = value.lowercased()
        if lowered.contains("://") { return true }
        let host = lowered.split(separator: "/", maxSplits: 1).first.map(String.init) ?? lowered
        let hostWithoutPort = host.split(separator: ":").first.map(String.init) ?? host
        if hostWithoutPort.split(separator: ".").allSatisfy({ Int($0) != nil }) { return false }
        if lowered.hasPrefix("www.") { return true }
        guard let suffix = hostWithoutPort.split(separator: ".").last else { return false }
        return bareDomainSuffixes.contains(String(suffix))
    }

    private static let hint = try! NSRegularExpression(pattern: #"@|://|[A-Za-z0-9-]\.[A-Za-z]{2,}|\d\.\d|\d{7,}|\d{3,4}[- ]\d{3,4}"#)

    /// 圆盘里要不要显示「提取信息」：找到两项以上，或者找到的那一项不是选中的全部内容
    static func isWorthExtracting(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 先粗略看一眼，大部分文字不用跑完整的识别；很长的文字只看这一眼
        guard trimmed.count <= maxLength,
              hint.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil else { return false }
        guard trimmed.utf16.count <= 20_000 else { return true }
        let items = extract(trimmed)
        return items.count >= 2 || (items.count == 1 && items[0].value != trimmed)
    }

    /// 结果卡片：每一项一行，按类别编号；每类一个「复制全部」
    static func card(for items: [Item], limit: Int = 60) -> ResultCard {
        var rows: [ResultCard.Row] = []
        var numbers: [Kind: Int] = [:]
        for item in items.prefix(limit) {
            numbers[item.kind, default: 0] += 1
            rows.append(ResultCard.Row(label: "\(item.kind.title) \(numbers[item.kind]!)", value: item.value))
        }
        let groups = Kind.allCases.compactMap { kind -> (Kind, [String])? in
            let values = items.filter { $0.kind == kind }.map(\.value)
            return values.isEmpty ? nil : (kind, values)
        }
        // 「1 个 IP 地址」：英文前面空一格
        let summary = groups.map { group in
            let title = group.0.title
            guard Localization.isChinese else { return "\(title): \(group.1.count)" }
            return "\(group.1.count) 个" + (title.first?.isASCII == true ? " " : "") + title
        }.joined(separator: String(localized: "，"))
        var buttons = groups.filter { $0.1.count > 1 }.map { group in
            CardButton(title: String(localized: "复制全部\(group.0.title)"), action: .copy(group.1.joined(separator: "\n")))
        }
        // 链接不多时可以一起打开
        let links = items.filter { $0.kind == .link }.compactMap { item -> URL? in
            URL(string: item.value.contains("://") ? item.value : "https://" + item.value)
        }
        if (2...10).contains(links.count) {
            buttons.append(CardButton(title: String(localized: "打开全部链接"), action: .openAll(links)))
        }
        let detail = items.count > limit ? String(localized: "\(summary)（只列出前 \(limit) 项，复制全部时包括所有的）") : summary
        return ResultCard(title: String(localized: "提取信息"), detail: detail, rows: rows, rowLineLimit: 1, buttons: buttons)
    }
}
