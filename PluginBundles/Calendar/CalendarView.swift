import AppKit
import SwiftUI
@testable import Pop

/// 「日历」卡片的状态：看的是哪个月、选中了哪一天、显不显示农历
@MainActor
final class CalendarModel: ObservableObject {
    static let lunarKey = "pop.calendar.lunar"
    /// 能翻到的范围（农历、节气的历表是 1900–2100 年）
    static let years = 1900...2100

    @Published private(set) var year: Int
    @Published private(set) var month: Int
    /// 选中的那天（从 1970 年 1 月 1 日起的第几天）
    @Published private(set) var selected: Int
    @Published var showsLunar: Bool {
        didSet { defaults?.set(showsLunar, forKey: Self.lunarKey) }
    }
    @Published private(set) var days: [CalendarMonth.Day] = []

    let today: Int
    /// 一周从星期几开始：1 是星期日，2 是星期一
    let firstWeekday: Int
    /// 选中了文字，但是没认出是哪一天
    let unrecognized: Bool
    /// 选中的日子不在 1900–2100 年里：翻不到，停在今天
    let outOfRange: Bool
    var onCopy: (String) -> Void = { _ in }
    private let defaults: UserDefaults?

    /// defaults 为 nil 时不读也不存设置（演示和测试用）
    init(text: String? = nil, now: Date = Date(), timeZone: TimeZone = .current,
         firstWeekday: Int = Calendar.current.firstWeekday, defaults: UserDefaults? = .standard, showsLunar: Bool? = nil) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let today = LunarTable.dayNumber(year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1)
        self.today = today
        let parsed = text.flatMap { CalendarMonth.parse($0, today: today) }
        unrecognized = parsed == nil && !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isOutOfRange = parsed.map { CalendarModel.clamped($0) != $0 } ?? false
        outOfRange = isOutOfRange
        let selected = Self.clamped(isOutOfRange ? today : parsed ?? today)
        self.selected = selected
        let date = LunarTable.civil(fromDayNumber: selected)
        year = date.year
        month = date.month
        self.firstWeekday = (1...7).contains(firstWeekday) ? firstWeekday : 1
        self.defaults = defaults
        // 中文界面默认显示农历
        self.showsLunar = showsLunar ?? (defaults?.object(forKey: Self.lunarKey) as? Bool ?? Localization.isChinese)
        rebuild()
    }

    private static func clamped(_ number: Int) -> Int {
        let first = LunarTable.dayNumber(year: years.lowerBound, month: 1, day: 1)
        let last = LunarTable.dayNumber(year: years.upperBound, month: 12, day: 31)
        return min(max(number, first), last)
    }

    private func rebuild() {
        days = CalendarMonth.days(year: year, month: month, firstWeekday: firstWeekday, today: today)
    }

    // MARK: - 翻

    func select(_ number: Int) {
        let number = Self.clamped(number)
        selected = number
        let date = LunarTable.civil(fromDayNumber: number)
        if date.year != year || date.month != month {
            year = date.year
            month = date.month
            rebuild()
        }
    }

    func move(by days: Int) {
        select(selected + days)
    }

    /// 往前、往后翻几个月，选中的还是几号（那个月没有这一天时选最后一天）
    func showMonth(offset: Int) {
        let index = year * 12 + (month - 1) + offset
        let target = (year: index / 12, month: index % 12 + 1)
        guard Self.years.contains(target.year) else { return }
        let day = min(LunarTable.civil(fromDayNumber: selected).day, CalendarMonth.length(year: target.year, month: target.month))
        select(LunarTable.dayNumber(year: target.year, month: target.month, day: day))
    }

    func goToday() {
        select(today)
    }

    var isShowingToday: Bool {
        selected == today
    }

    // MARK: - 写在卡片上的

    private static func date(_ number: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(number) * 86_400 + 43_200)
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Localization.locale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    /// 「2026年10月」
    var title: String {
        Self.formatter("yMMMM").string(from: Self.date(LunarTable.dayNumber(year: year, month: month, day: 1)))
    }

    /// 「丙午年 八月—九月」
    var lunarSubtitle: String? {
        showsLunar ? CalendarMonth.lunarSpan(year: year, month: month) : nil
    }

    /// 表头：按一周的第一天排好的星期
    var weekdaySymbols: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Localization.locale
        let symbols = Localization.isChinese ? calendar.veryShortStandaloneWeekdaySymbols : calendar.shortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        return Array(symbols[(firstWeekday - 1)...] + symbols[..<(firstWeekday - 1)])
    }

    var selectedDay: CalendarMonth.Day {
        CalendarMonth.day(selected, today: today)
    }

    /// 「2026年10月1日 星期四」
    var dateText: String {
        Self.formatter("yMMMMdEEEE").string(from: Self.date(selected))
    }

    /// 「今天」「3 天后」「5 天前」
    var relativeText: String {
        let difference = selected - today
        switch difference {
        case 0: return String(localized: "今天")
        case 1: return String(localized: "明天")
        case -1: return String(localized: "昨天")
        case let count where count > 0: return String(localized: "\(count) 天后")
        default: return String(localized: "\(-difference) 天前")
        }
    }

    /// 「丙午年（马年）八月廿一」
    var lunarText: String? {
        guard showsLunar, let lunar = selectedDay.lunar else { return nil }
        return String(localized: "农历\(LunarCalendar.describe(lunar))")
    }

    /// 这一天的节日和节气：「国庆节 · 中秋节」「寒露」
    var eventsText: String? {
        let day = selectedDay
        var names = showsLunar ? day.festivals
            : CalendarMonth.gregorianFestivals(year: day.year, month: day.month, day: day.day, weekday: day.weekday)
        if showsLunar, let term = day.solarTerm {
            names.append(SolarTerms.name(term))
        }
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    /// 「第 40 周 · 全年第 274 天」
    var weekText: String {
        LunarCalendar.weekAndDay(Self.date(selected), timeZone: TimeZone(identifier: "UTC") ?? .current)
    }

    /// 「下一个节气：寒露，10月8日，还有 7 天」
    var nextTermText: String? {
        guard showsLunar, let next = CalendarMonth.nextSolarTerm(after: selected) else { return nil }
        let name = SolarTerms.name(next.index)
        let date = Self.formatter("MMMMd").string(from: Self.date(next.number))
        let days = next.number - selected
        return days == 1
            ? String(localized: "下一个节气：\(name)，\(date)，就是明天")
            : String(localized: "下一个节气：\(name)，\(date)，还有 \(days) 天")
    }

    /// 复制的那一行：「2026年10月1日 星期四 农历丙午年（马年）八月廿一 国庆节」
    var copyText: String {
        [dateText, lunarText, eventsText].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: - 按键

    /// 方向键换一天、一周，PageUp、PageDown（或者 ⌘← ⌘→）换月，T 回到今天，⌘C 复制这一天
    func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 123: // ←
            if command {
                showMonth(offset: -1)
            } else {
                move(by: -1)
            }
            return true
        case 124: // →
            if command {
                showMonth(offset: 1)
            } else {
                move(by: 1)
            }
            return true
        case 125: // ↓
            move(by: 7)
            return true
        case 126: // ↑
            move(by: -7)
            return true
        case 116: // PageUp
            showMonth(offset: -1)
            return true
        case 121: // PageDown
            showMonth(offset: 1)
            return true
        case 115: // Home
            goToday()
            return true
        default:
            break
        }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if command, key == "c" {
            onCopy(copyText)
            return true
        }
        if !command, key == "t" {
            goToday()
            return true
        }
        return false
    }
}

struct CalendarView: View {
    @ObservedObject var model: CalendarModel
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "万年历"), width: 380, onClose: onClose) {
            if model.outOfRange {
                Text("万年历只能查 1900–2100 年，下面是这个月")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.unrecognized {
                Text("没认出选中的文字是哪一天，下面是这个月")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            header
            grid
            Divider()
            detail
            footer
        }
        .controlSize(.small)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: model.title)
                    .font(.title3.weight(.semibold))
                if let subtitle = model.lunarSubtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                model.showMonth(offset: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("上个月")
            Button("今天", action: model.goToday)
                .disabled(model.isShowingToday)
            Button {
                model.showMonth(offset: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("下个月")
        }
    }

    private var grid: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(model.days[(row * 7)..<(row * 7 + 7)]) { day in
                        DayCell(day: day, note: CalendarMonth.note(for: day, showsLunar: model.showsLunar),
                                isSelected: day.number == model.selected) {
                            model.select(day.number)
                        }
                    }
                }
            }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: model.dateText)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                Text(verbatim: model.relativeText)
                    .font(.caption)
                    .foregroundStyle(model.isShowingToday ? Color.accentColor : .secondary)
            }
            if let lunar = model.lunarText {
                Text(verbatim: lunar)
                    .font(.caption)
            }
            if let events = model.eventsText {
                Text(verbatim: events)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
            }
            Text(verbatim: model.weekText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let next = model.nextTermText {
                Text(verbatim: next)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 中文排一行；英文的开关和按键说明都长，按键说明换到下一行（开关不折行）
    @ViewBuilder
    private var footer: some View {
        if Localization.isChinese {
            HStack(spacing: 8) {
                lunarToggle
                Spacer(minLength: 8)
                keyHint
                copyButton
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    lunarToggle
                    Spacer(minLength: 8)
                    copyButton
                }
                keyHint
            }
        }
    }

    private var lunarToggle: some View {
        Toggle("农历和节气", isOn: $model.showsLunar)
            .toggleStyle(.checkbox)
            .fixedSize()
    }

    private var keyHint: some View {
        Text("方向键换一天 · PageUp/Down 换月 · T 今天")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var copyButton: some View {
        Button("复制") { model.onCopy(model.copyText) }
    }
}

/// 一格：几号，下面是节日、节气或者农历；今天的日期画在一个蓝色的圆角块上，选中的一格带底色
private struct DayCell: View {
    let day: CalendarMonth.Day
    let note: CalendarMonth.Note
    let isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "\(day.day)")
                .font(.system(size: 14, weight: day.isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(day.isToday ? Color.white : (day.isWeekend ? Color.secondary : Color.primary))
                .frame(minWidth: 24, minHeight: 20)
                .padding(.horizontal, 2)
                .background(Capsule().fill(day.isToday ? Color.accentColor : Color.clear))
            Text(verbatim: note.text.isEmpty ? " " : note.text)
                .font(.system(size: 9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(noteColor)
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovering ? 0.06 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1))
        .opacity(day.isInMonth ? 1 : 0.35)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        // 读屏时一格是一个按钮：念出日期和格子里的农历、节日
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : [])
        .accessibilityAction { action() }
    }

    private var noteColor: Color {
        switch note {
        case .festival: return .red
        case .solarTerm: return .green
        case .lunarMonth: return .accentColor
        case .lunarDay, .empty: return .secondary
        }
    }
}
