import Foundation

/// 两种颜色（文字和背景）的对比度，按 WCAG 2.1 的算法。
enum ColorContrast {
    /// 找出文字里的颜色值：#RGB、#RRGGBB、#RRGGBBAA、rgb()/rgba()、hsl()/hsla()
    private static let token = try! NSRegularExpression(
        pattern: #"#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})\b|(?:rgba?|hsla?)\([^)]*\)"#)

    /// 正好两种颜色时返回它们（前一个当文字，后一个当背景）
    static func pair(in text: String) -> (foreground: ColorValue, background: ColorValue)? {
        guard text.count <= 200 else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let colors = token.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).flatMap { ColorValue.parse(String(text[$0])) }
        }
        guard colors.count == 2 else { return nil }
        return (colors[0], colors[1])
    }

    /// 整段文字就是两个颜色（中间可以有「on」「和」、逗号、斜杠这样的几个字）
    static func isColorPair(_ text: String) -> Bool {
        guard pair(in: text) != nil else { return false }
        let range = NSRange(text.startIndex..., in: text)
        let rest = token.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return rest.trimmingCharacters(in: .whitespacesAndNewlines).count <= 12
    }

    /// 对比度 1–21
    static func ratio(_ first: ColorValue, _ second: ColorValue) -> Double {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// 相对亮度
    static func luminance(_ color: ColorValue) -> Double {
        func linear(_ value: Double) -> Double {
            let c = min(max(value / 255, 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// 12.63 : 1
    static func format(_ ratio: Double) -> String {
        String(format: "%.2f : 1", (ratio * 100).rounded(.down) / 100)
    }

    /// 普通文字要 4.5（AA）/ 7（AAA），大号文字（18pt 以上或 14pt 粗体）要 3 / 4.5
    static func verdict(_ ratio: Double, large: Bool) -> String {
        let aa = ratio >= (large ? 3 : 4.5)
        let aaa = ratio >= (large ? 4.5 : 7)
        let pass = String(localized: "通过"), fail = String(localized: "不通过")
        return "AA \(aa ? pass : fail) · AAA \(aaa ? pass : fail)"
    }

    static func rows(_ foreground: ColorValue, _ background: ColorValue) -> [ResultCard.Row] {
        let value = ratio(foreground, background)
        return [
            ResultCard.Row(label: String(localized: "对比度"), value: format(value)),
            ResultCard.Row(label: String(localized: "普通文字"), value: verdict(value, large: false)),
            ResultCard.Row(label: String(localized: "大号文字"), value: verdict(value, large: true)),
        ]
    }

    /// 单独一种颜色：在白底、黑底上的对比度，放在颜色转换卡片下面
    static func summary(for color: ColorValue) -> String {
        let white = ColorValue(red: 255, green: 255, blue: 255)
        let black = ColorValue(red: 0, green: 0, blue: 0)
        return String(localized: "对白色 \(format(ratio(color, white)))，对黑色 \(format(ratio(color, black)))")
    }
}
