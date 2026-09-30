import Foundation

/// 带单位的数值：识别（5 km、100°F、2 斤、6'2"、1 TB、100 Mbps……）和换算。纯逻辑，方便测试。
enum UnitConverter {
    enum Category: String, CaseIterable {
        case length
        case mass
        case temperature
        case volume
        case area
        case speed
        case dataSize
        case dataRate

        var title: String {
            switch self {
            case .length: return String(localized: "长度")
            case .mass: return String(localized: "重量")
            case .temperature: return String(localized: "温度")
            case .volume: return String(localized: "体积")
            case .area: return String(localized: "面积")
            case .speed: return String(localized: "速度")
            case .dataSize: return String(localized: "数据大小")
            case .dataRate: return String(localized: "传输速率")
            }
        }
    }

    struct UnitSpec: Equatable {
        let id: String
        let category: Category
        /// 显示用的符号，比如 km、°C、斤
        let symbol: String
        /// 结果里每一行的名字，比如 千米
        let name: String
        /// 1 个这个单位等于多少个基本单位：长度是米，重量是千克，体积是升，面积是平方米，速度是米/秒，
        /// 数据大小是字节，传输速率是比特/秒。温度另外换算。
        let factor: Double
        /// 识别用的写法，不区分大小写
        var aliases: [String] = []
        /// 识别用的写法，区分大小写（MB 和 Mb 不是一回事）
        var exactAliases: [String] = []
        /// 换算结果里列出这个单位（不常用的单位只在选中它的时候出现）
        var listed = true
    }

    struct Quantity: Equatable {
        var value: Double
        var unit: UnitSpec
    }

    // MARK: - 单位表

    /// 同一类里的顺序就是换算结果的顺序：公制在前，英制其次，市制最后。
    static let units: [UnitSpec] = [
        // 长度（米）
        UnitSpec(id: "mm", category: .length, symbol: "mm", name: String(localized: "毫米"), factor: 0.001, aliases: ["mm", "毫米"]),
        UnitSpec(id: "cm", category: .length, symbol: "cm", name: String(localized: "厘米"), factor: 0.01, aliases: ["cm", "厘米", "公分"]),
        UnitSpec(id: "m", category: .length, symbol: "m", name: String(localized: "米"), factor: 1,
             aliases: ["米", "公尺", "meter", "meters", "metre", "metres"], exactAliases: ["m"]),
        UnitSpec(id: "km", category: .length, symbol: "km", name: String(localized: "千米"), factor: 1000,
             aliases: ["km", "千米", "公里", "kilometer", "kilometers", "kilometre", "kilometres"]),
        UnitSpec(id: "in", category: .length, symbol: "in", name: String(localized: "英寸"), factor: 0.0254,
             aliases: ["in", "inch", "inches", "英寸", "\"", "″"]),
        UnitSpec(id: "ft", category: .length, symbol: "ft", name: String(localized: "英尺"), factor: 0.3048,
             aliases: ["ft", "foot", "feet", "英尺", "'", "′"]),
        UnitSpec(id: "yd", category: .length, symbol: "yd", name: String(localized: "码"), factor: 0.9144, aliases: ["yd", "yard", "yards"],
             listed: false),
        UnitSpec(id: "mi", category: .length, symbol: "mi", name: String(localized: "英里"), factor: 1609.344, aliases: ["mi", "mile", "miles", "英里"]),
        UnitSpec(id: "nmi", category: .length, symbol: "nmi", name: String(localized: "海里"), factor: 1852,
             aliases: ["nmi", "海里", "nautical mile", "nautical miles"]),
        UnitSpec(id: "chi", category: .length, symbol: "尺", name: String(localized: "尺（市尺）"), factor: 1.0 / 3.0, aliases: ["尺", "市尺"]),
        UnitSpec(id: "li", category: .length, symbol: "里", name: String(localized: "里（市里）"), factor: 500, aliases: ["里", "市里", "华里"]),

        // 重量（千克）
        UnitSpec(id: "mg", category: .mass, symbol: "mg", name: String(localized: "毫克"), factor: 0.000_001, aliases: ["mg", "毫克"], listed: false),
        UnitSpec(id: "g", category: .mass, symbol: "g", name: String(localized: "克"), factor: 0.001, aliases: ["克", "gram", "grams"], exactAliases: ["g"]),
        UnitSpec(id: "kg", category: .mass, symbol: "kg", name: String(localized: "千克"), factor: 1,
             aliases: ["kg", "千克", "公斤", "kilogram", "kilograms", "kilo", "kilos"]),
        UnitSpec(id: "t", category: .mass, symbol: "t", name: String(localized: "吨"), factor: 1000, aliases: ["吨", "公吨", "tonne", "tonnes"], exactAliases: ["t"]),
        UnitSpec(id: "lb", category: .mass, symbol: "lb", name: String(localized: "磅"), factor: 0.453_592_37, aliases: ["lb", "lbs", "pound", "pounds", "磅"]),
        UnitSpec(id: "oz", category: .mass, symbol: "oz", name: String(localized: "盎司"), factor: 0.028_349_523_125, aliases: ["oz", "ounce", "ounces", "盎司"]),
        UnitSpec(id: "ct", category: .mass, symbol: "ct", name: String(localized: "克拉"), factor: 0.0002, aliases: ["ct", "carat", "carats", "克拉"],
             listed: false),
        UnitSpec(id: "jin", category: .mass, symbol: "斤", name: String(localized: "斤"), factor: 0.5, aliases: ["斤", "市斤"]),
        UnitSpec(id: "liang", category: .mass, symbol: "两", name: String(localized: "两"), factor: 0.05, aliases: ["两", "市两"]),

        // 温度
        UnitSpec(id: "C", category: .temperature, symbol: "°C", name: String(localized: "摄氏度"), factor: 1,
             aliases: ["°c", "℃", "摄氏度", "celsius"]),
        UnitSpec(id: "F", category: .temperature, symbol: "°F", name: String(localized: "华氏度"), factor: 1,
             aliases: ["°f", "℉", "华氏度", "fahrenheit"]),
        UnitSpec(id: "K", category: .temperature, symbol: "K", name: String(localized: "开尔文"), factor: 1, aliases: ["开尔文", "kelvin"]),

        // 体积（升）
        UnitSpec(id: "mL", category: .volume, symbol: "mL", name: String(localized: "毫升"), factor: 0.001,
             aliases: ["ml", "毫升", "cc", "cm³", "cm3", "立方厘米"]),
        UnitSpec(id: "L", category: .volume, symbol: "L", name: String(localized: "升"), factor: 1,
             aliases: ["l", "升", "公升", "liter", "liters", "litre", "litres"]),
        UnitSpec(id: "m3", category: .volume, symbol: "m³", name: String(localized: "立方米"), factor: 1000, aliases: ["m³", "m3", "立方米"]),
        UnitSpec(id: "gal", category: .volume, symbol: "gal", name: String(localized: "加仑（美）"), factor: 3.785_411_784,
             aliases: ["gal", "gallon", "gallons", "加仑"]),
        UnitSpec(id: "qt", category: .volume, symbol: "qt", name: String(localized: "夸脱"), factor: 0.946_352_946, aliases: ["qt", "quart", "quarts", "夸脱"],
             listed: false),
        UnitSpec(id: "pint", category: .volume, symbol: "pt", name: String(localized: "品脱"), factor: 0.473_176_473, aliases: ["pint", "pints", "品脱"],
             listed: false),
        UnitSpec(id: "cup", category: .volume, symbol: "cup", name: String(localized: "杯（美）"), factor: 0.236_588_236_5, aliases: ["cup", "cups"],
             listed: false),
        UnitSpec(id: "floz", category: .volume, symbol: "fl oz", name: String(localized: "液量盎司"), factor: 0.029_573_529_562_5,
             aliases: ["fl oz", "floz", "fl. oz", "fl.oz", "液量盎司"]),
        UnitSpec(id: "tbsp", category: .volume, symbol: "tbsp", name: String(localized: "汤匙"), factor: 0.014_786_764_781_25, aliases: ["tbsp", "汤匙"],
             listed: false),
        UnitSpec(id: "tsp", category: .volume, symbol: "tsp", name: String(localized: "茶匙"), factor: 0.004_928_921_593_75, aliases: ["tsp", "茶匙"],
             listed: false),

        // 面积（平方米）
        UnitSpec(id: "cm2", category: .area, symbol: "cm²", name: String(localized: "平方厘米"), factor: 0.0001, aliases: ["cm²", "cm2", "平方厘米"],
             listed: false),
        UnitSpec(id: "m2", category: .area, symbol: "m²", name: String(localized: "平方米"), factor: 1, aliases: ["m²", "m2", "㎡", "平方米", "平米", "sqm"]),
        UnitSpec(id: "km2", category: .area, symbol: "km²", name: String(localized: "平方千米"), factor: 1_000_000,
             aliases: ["km²", "km2", "㎢", "平方千米", "平方公里"]),
        UnitSpec(id: "ha", category: .area, symbol: "ha", name: String(localized: "公顷"), factor: 10_000, aliases: ["ha", "公顷", "hectare", "hectares"]),
        UnitSpec(id: "ft2", category: .area, symbol: "ft²", name: String(localized: "平方英尺"), factor: 0.092_903_04,
             aliases: ["ft²", "ft2", "sq ft", "sqft", "平方英尺"]),
        UnitSpec(id: "in2", category: .area, symbol: "in²", name: String(localized: "平方英寸"), factor: 0.000_645_16, aliases: ["in²", "in2", "sq in", "平方英寸"],
             listed: false),
        UnitSpec(id: "acre", category: .area, symbol: "acre", name: String(localized: "英亩"), factor: 4046.856_422_4, aliases: ["acre", "acres", "英亩"]),
        UnitSpec(id: "mi2", category: .area, symbol: "mi²", name: String(localized: "平方英里"), factor: 2_589_988.110_336,
             aliases: ["mi²", "mi2", "sq mi", "平方英里"]),
        UnitSpec(id: "mu", category: .area, symbol: "亩", name: String(localized: "亩"), factor: 10_000.0 / 15.0, aliases: ["亩", "市亩"]),

        // 速度（米/秒）
        UnitSpec(id: "mps", category: .speed, symbol: "m/s", name: String(localized: "米/秒"), factor: 1, aliases: ["m/s", "米/秒", "米每秒"]),
        UnitSpec(id: "kmh", category: .speed, symbol: "km/h", name: String(localized: "千米/时"), factor: 1000.0 / 3600.0,
             aliases: ["km/h", "kmh", "kph", "km/hr", "公里/小时", "公里每小时", "千米/小时", "千米每小时", "千米/时", "公里/时"]),
        UnitSpec(id: "mph", category: .speed, symbol: "mph", name: String(localized: "英里/时"), factor: 0.447_04,
             aliases: ["mph", "mi/h", "英里/小时", "英里每小时", "英里/时"]),
        UnitSpec(id: "kn", category: .speed, symbol: "kn", name: String(localized: "节"), factor: 1852.0 / 3600.0, aliases: ["kn", "knot", "knots"]),

        // 数据大小（字节）。全小写的 kb、mb、gb 按字节算；Kb、Mb、Gb 是比特
        UnitSpec(id: "bit", category: .dataSize, symbol: "bit", name: String(localized: "比特"), factor: 0.125, aliases: ["bit", "bits", "比特"],
             listed: false),
        UnitSpec(id: "B", category: .dataSize, symbol: "B", name: String(localized: "字节"), factor: 1, aliases: ["byte", "bytes", "字节"],
             exactAliases: ["B"]),
        UnitSpec(id: "KB", category: .dataSize, symbol: "KB", name: "KB", factor: 1e3, exactAliases: ["KB", "kB", "kb"]),
        UnitSpec(id: "MB", category: .dataSize, symbol: "MB", name: "MB", factor: 1e6, exactAliases: ["MB", "mb"]),
        UnitSpec(id: "GB", category: .dataSize, symbol: "GB", name: "GB", factor: 1e9, exactAliases: ["GB", "gb"]),
        UnitSpec(id: "TB", category: .dataSize, symbol: "TB", name: "TB", factor: 1e12, exactAliases: ["TB", "tb"]),
        UnitSpec(id: "PB", category: .dataSize, symbol: "PB", name: "PB", factor: 1e15, exactAliases: ["PB", "pb"], listed: false),
        UnitSpec(id: "KiB", category: .dataSize, symbol: "KiB", name: "KiB", factor: 1024, aliases: ["kib"]),
        UnitSpec(id: "MiB", category: .dataSize, symbol: "MiB", name: "MiB", factor: 1_048_576, aliases: ["mib"]),
        UnitSpec(id: "GiB", category: .dataSize, symbol: "GiB", name: "GiB", factor: 1_073_741_824, aliases: ["gib"]),
        UnitSpec(id: "TiB", category: .dataSize, symbol: "TiB", name: "TiB", factor: 1_099_511_627_776, aliases: ["tib"]),
        UnitSpec(id: "Kb", category: .dataSize, symbol: "Kb", name: String(localized: "Kb（千比特）"), factor: 125, aliases: ["kbit"], exactAliases: ["Kb"],
             listed: false),
        UnitSpec(id: "Mb", category: .dataSize, symbol: "Mb", name: String(localized: "Mb（兆比特）"), factor: 125_000, aliases: ["mbit"], exactAliases: ["Mb"],
             listed: false),
        UnitSpec(id: "Gb", category: .dataSize, symbol: "Gb", name: String(localized: "Gb（吉比特）"), factor: 125_000_000, aliases: ["gbit"],
             exactAliases: ["Gb"], listed: false),

        // 传输速率（比特/秒）。带 ps 的是比特，/s 前面是 B 的是字节
        UnitSpec(id: "bps", category: .dataRate, symbol: "bps", name: "bps", factor: 1, aliases: ["bps", "bit/s"], listed: false),
        UnitSpec(id: "Kbps", category: .dataRate, symbol: "Kbps", name: "Kbps", factor: 1e3, aliases: ["kbps", "kbit/s"],
             exactAliases: ["Kb/s"]),
        UnitSpec(id: "Mbps", category: .dataRate, symbol: "Mbps", name: "Mbps", factor: 1e6, aliases: ["mbps", "mbit/s"],
             exactAliases: ["Mb/s"]),
        UnitSpec(id: "Gbps", category: .dataRate, symbol: "Gbps", name: "Gbps", factor: 1e9, aliases: ["gbps", "gbit/s"],
             exactAliases: ["Gb/s"]),
        UnitSpec(id: "KBps", category: .dataRate, symbol: "KB/s", name: "KB/s", factor: 8e3, exactAliases: ["KB/s", "kB/s", "kb/s"]),
        UnitSpec(id: "MBps", category: .dataRate, symbol: "MB/s", name: "MB/s", factor: 8e6, exactAliases: ["MB/s", "mb/s"]),
        UnitSpec(id: "GBps", category: .dataRate, symbol: "GB/s", name: "GB/s", factor: 8e9, exactAliases: ["GB/s", "gb/s"]),
        UnitSpec(id: "MiBps", category: .dataRate, symbol: "MiB/s", name: "MiB/s", factor: 8_388_608, aliases: ["mib/s"], listed: false),
    ]

    static func unit(id: String) -> UnitSpec? {
        units.first { $0.id == id }
    }

    /// 写法 → 单位。区分大小写的写法优先。
    private static let exactLookup: [String: UnitSpec] = {
        var table: [String: UnitSpec] = [:]
        for unit in units {
            for alias in unit.exactAliases where table[alias] == nil {
                table[alias] = unit
            }
        }
        return table
    }()

    private static let lookup: [String: UnitSpec] = {
        var table: [String: UnitSpec] = [:]
        for unit in units {
            for alias in unit.aliases where table[alias.lowercased()] == nil {
                table[alias.lowercased()] = unit
            }
        }
        return table
    }()

    // MARK: - 识别

    private static let quantityPattern = try! NSRegularExpression(
        pattern: #"^([+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?|[+-]?\.\d+)\s*(\S.*)$"#)
    /// 英尺加英寸，比如 5'11"、6′2″
    private static let feetInchesPattern = try! NSRegularExpression(
        pattern: #"^(\d{1,2})\s*['′]\s*(\d{1,2}(?:\.\d+)?)\s*(?:["″]|'')?$"#)

    static func parse(_ text: String) -> Quantity? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
        guard !trimmed.isEmpty, trimmed.count <= 40, !trimmed.contains(where: \.isNewline) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if let match = feetInchesPattern.firstMatch(in: trimmed, options: [], range: range),
           let feet = Double(substring(trimmed, match.range(at: 1))),
           let inches = Double(substring(trimmed, match.range(at: 2))),
           inches < 12, let foot = unit(id: "ft") {
            return Quantity(value: feet + inches / 12, unit: foot)
        }
        guard let match = quantityPattern.firstMatch(in: trimmed, options: [], range: range),
              let value = Double(substring(trimmed, match.range(at: 1)).replacingOccurrences(of: ",", with: "")),
              let spec = unit(named: substring(trimmed, match.range(at: 2))) else { return nil }
        // 只有温度可以是负数
        guard value >= 0 || spec.category == .temperature else { return nil }
        return Quantity(value: value, unit: spec)
    }

    /// 单位的写法：去掉「/」两边的空格，多个空格算一个
    static func unit(named raw: String) -> UnitSpec? {
        let collapsed = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            .replacingOccurrences(of: " / ", with: "/")
            .replacingOccurrences(of: " /", with: "/")
            .replacingOccurrences(of: "/ ", with: "/")
        guard !collapsed.isEmpty else { return nil }
        if let unit = exactLookup[collapsed] {
            return unit
        }
        return lookup[collapsed.lowercased()]
    }

    private static func substring(_ text: String, _ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }

    // MARK: - 换算

    static func convert(_ quantity: Quantity, to target: UnitSpec) -> Double? {
        guard quantity.unit.category == target.category else { return nil }
        if quantity.unit.category == .temperature {
            let celsius: Double
            switch quantity.unit.id {
            case "F": celsius = (quantity.value - 32) * 5 / 9
            case "K": celsius = quantity.value - 273.15
            default: celsius = quantity.value
            }
            switch target.id {
            case "F": return celsius * 9 / 5 + 32
            case "K": return celsius + 273.15
            default: return celsius
            }
        }
        return quantity.value * quantity.unit.factor / target.factor
    }

    /// 换算结果：同一类里其他常用单位，数值太大或太小（不好读）的不列。
    static func conversions(_ quantity: Quantity, limit: Int = 8) -> [(unit: UnitSpec, value: Double)] {
        let candidates = units.filter { $0.category == quantity.unit.category && $0.listed && $0.id != quantity.unit.id }
        let all = candidates.compactMap { unit in convert(quantity, to: unit).map { (unit: unit, value: $0) } }
        guard quantity.unit.category != .temperature else { return all }
        let readable = all.filter { item in
            let magnitude = abs(item.value)
            return magnitude == 0 || (magnitude >= 0.01 && magnitude <= 1_000_000)
        }
        return Array((readable.count >= 3 ? readable : all).prefix(limit))
    }

    static func rows(for quantity: Quantity) -> [ResultCard.Row] {
        var rows = conversions(quantity).map { ResultCard.Row(label: $0.unit.name, value: display($0.value, $0.unit)) }
        // 身高这类长度再给一个「几英尺几英寸」
        if quantity.unit.category == .length, !["ft", "in", "yd", "mi", "nmi"].contains(quantity.unit.id),
           let meter = unit(id: "m"), let meters = convert(quantity, to: meter), meters >= 0.3, meters < 3 {
            rows.append(ResultCard.Row(label: String(localized: "英尺英寸"), value: feetAndInches(meters: meters)))
        }
        return rows
    }

    /// 1.8 米 → 5' 10.9"
    static func feetAndInches(meters: Double) -> String {
        let totalInches = meters / 0.0254
        var feet = Int(totalInches / 12)
        var inches = ((totalInches - Double(feet) * 12) * 10).rounded() / 10
        if inches >= 12 {
            feet += 1
            inches = 0
        }
        var inchText = String(format: "%.1f", inches)
        if inchText.hasSuffix(".0") {
            inchText.removeLast(2)
        }
        return "\(feet)' \(inchText)\""
    }

    /// 数值加单位：3.10686 mi、37.8°C、2 斤
    static func display(_ value: Double, _ unit: UnitSpec) -> String {
        let number = format(value)
        let tight = unit.symbol.hasPrefix("°") || unit.symbol.unicodeScalars.first.map { $0.value >= 0x2E80 } == true
        return tight ? number + unit.symbol : number + " " + unit.symbol
    }

    /// 最多 6 位有效数字，带千分位
    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesSignificantDigits = true
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = 6
        // 避免显示成 -0
        let normalized = abs(value) < 1e-12 ? 0 : value
        return formatter.string(from: NSNumber(value: normalized)) ?? String(normalized)
    }
}
