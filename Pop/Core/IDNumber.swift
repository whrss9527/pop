import Foundation

/// 证件号码：居民身份证（18 位和老的 15 位）、港澳台居民居住证、统一社会信用代码、银行卡号。
/// 只检查校验位、读出号码里本来就写着的信息（出生日期、性别、地区、登记管理部门……），不联网查询。
enum IDNumber {
    enum Kind: Equatable {
        case residentID
        /// 港澳台居民居住证（号码格式和身份证一样，地区码是 81、82、83）
        case residencePermit
        /// 1999 年以前的 15 位身份证
        case oldResidentID
        case creditCode
        case bankCard

        var title: String {
            switch self {
            case .residentID: return "居民身份证"
            case .residencePermit: return "港澳台居民居住证"
            case .oldResidentID: return "15 位身份证"
            case .creditCode: return "统一社会信用代码"
            case .bankCard: return "银行卡号"
            }
        }
    }

    struct Info: Equatable {
        var kind: Kind
        /// 去掉空格、横线，字母大写
        var number: String
        var isValid: Bool
        /// 校验不通过时，最后一位应该是什么（银行卡号没有）
        var expectedCheck: String?
        var rows: [ResultCard.Row]
    }

    /// 全角转半角，去掉空格和横线，字母大写
    static func normalize(_ text: String) -> String {
        let halfwidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return halfwidth.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    }

    static func parse(_ text: String, today: Date = Date()) -> Info? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 40, !trimmed.contains("\n") else { return nil }
        let number = normalize(trimmed)
        if let info = residentID(number, today: today) ?? oldResidentID(number, today: today) {
            return info
        }
        let credit = creditCode(number)
        if let credit, credit.isValid || number.contains(where: \.isLetter) {
            return credit
        }
        // 全是数字、两种校验都不通过时，按银行卡号算
        return bankCard(number) ?? credit
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    // MARK: 身份证

    /// 行政区划代码的前两位
    static let provinces: [String: String] = [
        "11": "北京", "12": "天津", "13": "河北", "14": "山西", "15": "内蒙古",
        "21": "辽宁", "22": "吉林", "23": "黑龙江",
        "31": "上海", "32": "江苏", "33": "浙江", "34": "安徽", "35": "福建", "36": "江西", "37": "山东",
        "41": "河南", "42": "湖北", "43": "湖南", "44": "广东", "45": "广西", "46": "海南",
        "50": "重庆", "51": "四川", "52": "贵州", "53": "云南", "54": "西藏",
        "61": "陕西", "62": "甘肃", "63": "青海", "64": "宁夏", "65": "新疆",
        "71": "台湾", "81": "香港", "82": "澳门", "83": "台湾",
    ]

    private static let residentWeights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
    private static let residentCodes = Array("10X98765432")

    /// 前 17 位算出来的校验位
    static func residentCheck(_ first17: String) -> Character? {
        let digits = first17.compactMap { $0.isASCII ? $0.wholeNumberValue : nil }
        guard digits.count == 17 else { return nil }
        let sum = zip(digits, residentWeights).reduce(0) { $0 + $1.0 * $1.1 }
        return residentCodes[sum % 11]
    }

    static func residentID(_ number: String, today: Date) -> Info? {
        guard number.range(of: "^[1-8][0-9]{5}(18|19|20)[0-9]{9}[0-9X]$", options: .regularExpression) != nil else { return nil }
        let digits = Array(number)
        guard let province = provinces[String(digits[0..<2])],
              let birth = date(String(digits[6..<14])) else { return nil }
        let expected = residentCheck(String(digits[0..<17]))
        let isValid = expected == digits[17]
        let permit = ["81", "82", "83"].contains(String(digits[0..<2]))
        var rows = [ResultCard.Row(label: "校验", value: isValid ? "通过" : "不通过")]
        rows += personRows(birth: birth, genderDigit: digits[16], today: today)
        rows.append(ResultCard.Row(label: "地区", value: "\(province)（\(String(digits[0..<6]))）"))
        return Info(kind: permit ? .residencePermit : .residentID, number: number, isValid: isValid,
                    expectedCheck: isValid ? nil : expected.map { String($0) }, rows: rows)
    }

    /// 15 位：6 位地区 + 6 位出生日期（年份只写后两位，都是 19xx 年）+ 3 位顺序码，没有校验位
    static func oldResidentID(_ number: String, today: Date) -> Info? {
        guard number.range(of: "^[1-8][0-9]{14}$", options: .regularExpression) != nil else { return nil }
        let digits = Array(number)
        guard let province = provinces[String(digits[0..<2])],
              let birth = date("19" + String(digits[6..<12])) else { return nil }
        let first17 = String(digits[0..<6]) + "19" + String(digits[6..<15])
        guard let check = residentCheck(first17) else { return nil }
        var rows = personRows(birth: birth, genderDigit: digits[14], today: today)
        rows.append(ResultCard.Row(label: "地区", value: "\(province)（\(String(digits[0..<6]))）"))
        rows.append(ResultCard.Row(label: "18 位号码", value: first17 + String(check)))
        return Info(kind: .oldResidentID, number: number, isValid: true, expectedCheck: nil, rows: rows)
    }

    /// yyyyMMdd，日期要真实存在
    static func date(_ text: String) -> Date? {
        guard text.count == 8, let year = Int(text.prefix(4)), let month = Int(text.dropFirst(4).prefix(2)),
              let day = Int(text.suffix(2)) else { return nil }
        let calendar = Self.calendar
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return parts.year == year && parts.month == month && parts.day == day ? date : nil
    }

    private static func personRows(birth: Date, genderDigit: Character, today: Date) -> [ResultCard.Row] {
        let calendar = Self.calendar
        let parts = calendar.dateComponents([.year, .month, .day], from: birth)
        var rows = [ResultCard.Row(label: "出生日期", value: "\(parts.year ?? 0) 年 \(parts.month ?? 0) 月 \(parts.day ?? 0) 日")]
        if birth <= today, let age = calendar.dateComponents([.year], from: birth, to: today).year {
            rows.append(ResultCard.Row(label: "年龄", value: "\(age) 岁"))
        }
        if let value = genderDigit.wholeNumberValue {
            rows.append(ResultCard.Row(label: "性别", value: value % 2 == 1 ? "男" : "女"))
        }
        return rows
    }

    // MARK: 统一社会信用代码

    private static let creditAlphabet = Array("0123456789ABCDEFGHJKLMNPQRTUWXY")
    private static let creditWeights = [1, 3, 9, 27, 19, 26, 16, 17, 20, 29, 25, 13, 8, 24, 10, 30, 28]

    /// 第 1 位：登记管理部门；第 2 位：机构类别（常见的几种）
    static let registrars: [Character: (name: String, types: [Character: String])] = [
        "1": ("机构编制", ["1": "机关", "2": "事业单位", "3": "中央编办直接管理机构编制的群众团体", "9": "其他"]),
        "2": ("外交", [:]),
        "3": ("司法行政", [:]),
        "4": ("文化", [:]),
        "5": ("民政", ["1": "社会团体", "2": "民办非企业单位", "3": "基金会", "9": "其他"]),
        "6": ("旅游", [:]),
        "7": ("宗教", [:]),
        "8": ("工会", [:]),
        "9": ("市场监管（工商）", ["1": "企业", "2": "个体工商户", "3": "农民专业合作社"]),
        "A": ("中央军委改革和编制办公室", [:]),
        "N": ("农业", [:]),
        "Y": ("其他", [:]),
    ]

    static func creditCheck(_ first17: String) -> Character? {
        var sum = 0
        for (character, weight) in zip(first17, creditWeights) {
            guard let value = creditAlphabet.firstIndex(of: character) else { return nil }
            sum += value * weight
        }
        return creditAlphabet[(31 - sum % 31) % 31]
    }

    static func creditCode(_ number: String) -> Info? {
        guard number.range(of: "^[0-9A-HJ-NPQRTUWXY]{2}[0-9]{6}[0-9A-HJ-NPQRTUWXY]{10}$", options: .regularExpression) != nil else {
            return nil
        }
        let characters = Array(number)
        guard let registrar = registrars[characters[0]], let expected = creditCheck(String(characters[0..<17])) else { return nil }
        let isValid = expected == characters[17]
        var rows = [ResultCard.Row(label: "校验", value: isValid ? "通过" : "不通过"),
                    ResultCard.Row(label: "登记管理部门", value: registrar.name)]
        if let type = registrar.types[characters[1]] {
            rows.append(ResultCard.Row(label: "机构类别", value: type))
        }
        let region = String(characters[2..<8])
        if let province = provinces[String(region.prefix(2))] {
            rows.append(ResultCard.Row(label: "登记地", value: "\(province)（\(region)）"))
        }
        rows.append(ResultCard.Row(label: "组织机构代码", value: String(characters[8..<16]) + "-" + String(characters[16])))
        return Info(kind: .creditCode, number: number, isValid: isValid, expectedCheck: isValid ? nil : String(expected), rows: rows)
    }

    // MARK: 银行卡号

    /// Luhn（模 10）校验
    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (offset, character) in digits.reversed().enumerated() {
            guard character.isASCII, var value = character.wholeNumberValue else { return false }
            if offset % 2 == 1 {
                value *= 2
                if value > 9 {
                    value -= 9
                }
            }
            sum += value
        }
        return sum % 10 == 0
    }

    /// 按开头几位认卡组织
    static func network(of digits: String) -> String? {
        let two = Int(digits.prefix(2)) ?? 0
        let four = Int(digits.prefix(4)) ?? 0
        if digits.hasPrefix("62") {
            return "银联"
        }
        if digits.hasPrefix("4") {
            return "Visa"
        }
        if (51...55).contains(two) || (2221...2720).contains(four) {
            return "Mastercard"
        }
        if (3528...3589).contains(four) {
            return "JCB"
        }
        if digits.hasPrefix("6011") || digits.hasPrefix("65") {
            return "Discover"
        }
        return nil
    }

    static func bankCard(_ number: String) -> Info? {
        guard number.range(of: "^[0-9]{16,19}$", options: .regularExpression) != nil else { return nil }
        let isValid = luhn(number)
        var rows = [ResultCard.Row(label: "校验", value: isValid ? "通过" : "不通过")]
        if let network = network(of: number) {
            rows.append(ResultCard.Row(label: "卡组织", value: network))
        }
        rows.append(ResultCard.Row(label: "位数", value: "\(number.count) 位"))
        rows.append(ResultCard.Row(label: "分组", value: grouped(number)))
        return Info(kind: .bankCard, number: number, isValid: isValid, expectedCheck: nil, rows: rows)
    }

    /// 每 4 位空一格
    static func grouped(_ number: String) -> String {
        var result = ""
        for (index, character) in number.enumerated() {
            if index > 0 && index % 4 == 0 {
                result.append(" ")
            }
            result.append(character)
        }
        return result
    }

    // MARK: 卡片

    static func card(_ info: Info) -> ResultCard {
        let body: String
        if info.isValid {
            body = info.kind == .oldResidentID ? "15 位身份证没有校验位，下面是它对应的 18 位号码" : "校验通过"
        } else if let expected = info.expectedCheck {
            body = "校验不通过：按前面的数字，最后一位应该是 \(expected)，可能输错了"
        } else {
            body = "校验不通过，可能输错了（也有少数卡号不用这种校验）"
        }
        let summary = ([info.kind.title + "：" + info.number] + info.rows.map { "\($0.label)：\($0.value)" }).joined(separator: "\n")
        return ResultCard(title: info.kind.title, body: body, detail: "只根据号码本身推算，不联网查询", copyText: summary, rows: info.rows)
    }
}
