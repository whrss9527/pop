import AppKit
import XCTest
@testable import Pop

@MainActor
final class CalendarTests: XCTestCase {
    private func number(_ year: Int, _ month: Int, _ day: Int) -> Int {
        LunarTable.dayNumber(year: year, month: month, day: day)
    }

    private func key(_ code: UInt16, _ characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "PopCalendarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    /// 北京时间 2026 年 10 月 1 日上午 10 点，一周从星期一开始
    private func makeModel(text: String? = nil, defaults: UserDefaults? = nil, showsLunar: Bool? = true) -> CalendarModel {
        CalendarModel(text: text, now: Date(timeIntervalSince1970: 1_790_820_000), timeZone: TimeZone(identifier: "Asia/Shanghai")!,
                      firstWeekday: 2, defaults: defaults, showsLunar: showsLunar)
    }

    // MARK: - 农历历表

    func testLunarTable() {
        XCTAssertEqual(number(1970, 1, 1), 0)
        XCTAssertEqual(number(2026, 10, 1), 20_727)
        for value in [-25_000, -1, 0, 20_727, 47_000] {
            let date = LunarTable.civil(fromDayNumber: value)
            XCTAssertEqual(number(date.year, date.month, date.day), value)
        }
        XCTAssertEqual(LunarTable.lunar(year: 2026, month: 2, day: 17), LunarTable.Day(year: 2026, month: 1, day: 1, isLeapMonth: false))
        XCTAssertEqual(LunarTable.lunar(year: 2026, month: 10, day: 1), LunarTable.Day(year: 2026, month: 8, day: 21, isLeapMonth: false))
        // 朔日离半夜只差几分钟的几处：2027、2030 年的春节
        XCTAssertEqual(LunarTable.lunar(year: 2027, month: 2, day: 5), LunarTable.Day(year: 2026, month: 12, day: 29, isLeapMonth: false))
        XCTAssertEqual(LunarTable.lunar(year: 2027, month: 2, day: 6), LunarTable.Day(year: 2027, month: 1, day: 1, isLeapMonth: false))
        XCTAssertEqual(LunarTable.lunar(year: 2030, month: 2, day: 2), LunarTable.Day(year: 2029, month: 12, day: 30, isLeapMonth: false))
        XCTAssertEqual(LunarTable.lunar(year: 2030, month: 2, day: 3), LunarTable.Day(year: 2030, month: 1, day: 1, isLeapMonth: false))
        // 闰月
        XCTAssertEqual(LunarTable.leapMonth(inYear: 2025), 6)
        XCTAssertNil(LunarTable.leapMonth(inYear: 2026))
        XCTAssertEqual(LunarTable.lunar(year: 2025, month: 7, day: 25), LunarTable.Day(year: 2025, month: 6, day: 1, isLeapMonth: true))
        XCTAssertEqual(LunarTable.lunar(year: 2023, month: 3, day: 22), LunarTable.Day(year: 2023, month: 2, day: 1, isLeapMonth: true))
        // 表的两头
        XCTAssertNil(LunarTable.lunar(year: 1900, month: 1, day: 30))
        XCTAssertEqual(LunarTable.lunar(year: 1900, month: 1, day: 31), LunarTable.Day(year: 1900, month: 1, day: 1, isLeapMonth: false))
        XCTAssertEqual(LunarTable.lunar(year: 2101, month: 1, day: 28), LunarTable.Day(year: 2100, month: 12, day: 29, isLeapMonth: false))
        XCTAssertNil(LunarTable.lunar(year: 2101, month: 1, day: 29))
        // 反过来：农历哪一天是公历哪一天
        XCTAssertEqual(LunarTable.dayNumber(lunarYear: 2026, month: 8, day: 15), number(2026, 9, 25))
        XCTAssertEqual(LunarTable.dayNumber(lunarYear: 2025, month: 6, day: 1, isLeapMonth: true), number(2025, 7, 25))
        XCTAssertNil(LunarTable.dayNumber(lunarYear: 2026, month: 6, day: 1, isLeapMonth: true))
        XCTAssertNil(LunarTable.dayNumber(lunarYear: 2026, month: 1, day: 31))
        // 每一天都对得上
        var day = number(1900, 1, 31)
        while day < number(2101, 1, 29) {
            let date = LunarTable.civil(fromDayNumber: day)
            let lunar = LunarTable.lunar(year: date.year, month: date.month, day: date.day)
            XCTAssertEqual(lunar.flatMap { LunarTable.dayNumber(lunarYear: $0.year, month: $0.month, day: $0.day, isLeapMonth: $0.isLeapMonth) }, day)
            day += 1
        }
    }

    func testLunarCalendarUsesTheTable() throws {
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let formatter = ISO8601DateFormatter()
        let newYear = try XCTUnwrap(formatter.date(from: "2027-02-06T04:00:00Z"))
        XCTAssertEqual(LunarCalendar.describe(newYear, timeZone: shanghai), "丁未年（羊年）正月初一 · 春节")
        XCTAssertEqual(LunarCalendar.festival(year: 2027, month: 2, day: 5), "除夕")
        XCTAssertEqual(LunarCalendar.festival(year: 2026, month: 9, day: 25), "中秋节")
        XCTAssertNil(LunarCalendar.festival(year: 2026, month: 10, day: 1))
        XCTAssertEqual(LunarCalendar.yearName(cycleYear: LunarCalendar.cycleYear(2026)), "丙午年（马年）")
        XCTAssertEqual(LunarCalendar.yearName(cycleYear: LunarCalendar.cycleYear(1984)), "甲子年（鼠年）")
        XCTAssertEqual(LunarCalendar.monthName(6, isLeapMonth: true), "闰六月")
        XCTAssertEqual(LunarCalendar.monthName(11, isLeapMonth: false), "冬月")
        // 历表以外的年份用系统的农历历法
        let far = try XCTUnwrap(formatter.date(from: "2150-06-01T04:00:00Z"))
        XCTAssertNil(LunarCalendar.lunarDate(year: 2150, month: 6, day: 1))
        XCTAssertNotNil(LunarCalendar.lunarDate(far, timeZone: shanghai))
    }

    // MARK: - 节气

    func testSolarTerms() {
        let days2026 = SolarTerms.names.indices.compactMap { SolarTerms.day(ofTerm: $0, in: 2026) }
        XCTAssertEqual(days2026, [5, 20, 4, 18, 5, 20, 5, 20, 5, 21, 5, 21, 7, 23, 7, 23, 7, 23, 8, 23, 7, 22, 7, 22])
        XCTAssertEqual(SolarTerms.term(year: 2026, month: 10, day: 8), 18)
        XCTAssertEqual(SolarTerms.name(18), "寒露")
        XCTAssertEqual(SolarTerms.term(year: 2026, month: 2, day: 4), 2)
        XCTAssertNil(SolarTerms.term(year: 2026, month: 10, day: 9))
        // 离半夜很近的几个
        XCTAssertEqual(SolarTerms.day(ofTerm: 23, in: 2021), 21)
        XCTAssertEqual(SolarTerms.day(ofTerm: 9, in: 2008), 21)
        XCTAssertNil(SolarTerms.day(ofTerm: 0, in: 1899))
        XCTAssertNil(SolarTerms.day(ofTerm: 0, in: 2101))
        // 每年 24 个，一个比一个晚，都在该在的月份里
        for year in SolarTerms.firstYear...SolarTerms.lastYear {
            var previous = Int.min
            for index in SolarTerms.names.indices {
                guard let day = SolarTerms.day(ofTerm: index, in: year) else {
                    XCTFail("\(year) \(index)")
                    continue
                }
                let value = number(year, SolarTerms.month(ofTerm: index), day)
                XCTAssertGreaterThan(value, previous)
                XCTAssertLessThanOrEqual(day, CalendarMonth.length(year: year, month: SolarTerms.month(ofTerm: index)))
                previous = value
            }
        }
    }

    // MARK: - 一个月

    func testMonthGrid() throws {
        let today = number(2026, 10, 1)
        let days = CalendarMonth.days(year: 2026, month: 10, firstWeekday: 2, today: today)
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first.map { [$0.year, $0.month, $0.day] }, [2026, 9, 28])
        XCTAssertEqual(days.last.map { [$0.year, $0.month, $0.day] }, [2026, 11, 8])
        XCTAssertEqual(days.filter(\.isInMonth).count, 31)
        let first = days[3]
        XCTAssertTrue(first.isToday)
        XCTAssertEqual(first.weekday, 5)
        XCTAssertEqual(first.festivals, ["国庆节"])
        XCTAssertEqual(days.filter(\.isToday).count, 1)
        // 一周从星期日开始
        let sunday = CalendarMonth.days(year: 2026, month: 10, firstWeekday: 1, today: nil)
        XCTAssertEqual(sunday.first.map { [$0.month, $0.day] }, [9, 27])
        XCTAssertTrue(sunday[0].isWeekend)

        func note(_ month: Int, _ day: Int, lunar: Bool = true) -> CalendarMonth.Note {
            CalendarMonth.note(for: CalendarMonth.day(number(2026, month, day)), showsLunar: lunar)
        }
        XCTAssertEqual(note(10, 1), .festival("国庆节"))
        XCTAssertEqual(note(10, 2), .lunarDay("廿二"))
        XCTAssertEqual(note(10, 8), .solarTerm("寒露"))
        XCTAssertEqual(note(10, 10), .lunarMonth("九月"))
        XCTAssertEqual(note(10, 18), .festival("重阳节"))
        XCTAssertEqual(note(10, 1, lunar: false), .festival("国庆节"))
        XCTAssertEqual(note(10, 8, lunar: false), .empty)
        XCTAssertEqual(note(10, 18, lunar: false), .empty)
        XCTAssertEqual(note(5, 10, lunar: false), .festival("母亲节"))
        XCTAssertEqual(note(6, 21, lunar: false), .festival("父亲节"))
        XCTAssertEqual(CalendarMonth.day(number(2020, 10, 1)).festivals, ["中秋节", "国庆节"])
        XCTAssertEqual(CalendarMonth.day(number(2027, 2, 5)).festivals, ["除夕"])
    }

    func testMonthTitleAndNextTerm() {
        XCTAssertEqual(CalendarMonth.lunarSpan(year: 2026, month: 10), "丙午年 八月—九月")
        XCTAssertEqual(CalendarMonth.lunarSpan(year: 2026, month: 2), "乙巳年腊月—丙午年正月")
        XCTAssertEqual(CalendarMonth.lunarSpan(year: 2025, month: 8), "乙巳年 闰六月—七月")
        XCTAssertNil(CalendarMonth.lunarSpan(year: 2150, month: 1))
        XCTAssertEqual(CalendarMonth.length(year: 2028, month: 2), 29)
        XCTAssertEqual(CalendarMonth.length(year: 2100, month: 2), 28)
        let next = CalendarMonth.nextSolarTerm(after: number(2026, 10, 1))
        XCTAssertEqual(next?.index, 18)
        XCTAssertEqual(next?.number, number(2026, 10, 8))
        let afterWinter = CalendarMonth.nextSolarTerm(after: number(2026, 12, 22))
        XCTAssertEqual(afterWinter?.index, 0)
        XCTAssertEqual(afterWinter?.number, number(2027, 1, 5))
    }

    // MARK: - 选中的文字

    func testParseSelection() {
        let today = number(2026, 10, 1)
        func parse(_ text: String) -> Int? { CalendarMonth.parse(text, today: today) }
        XCTAssertEqual(parse("2026-10-01"), today)
        XCTAssertEqual(parse(" 2026年10月1日 "), today)
        XCTAssertEqual(parse("2026/10/01 14:30"), today)
        XCTAssertEqual(parse("2027年2月"), number(2027, 2, 1))
        XCTAssertEqual(parse("2027-02"), number(2027, 2, 1))
        XCTAssertEqual(parse("12月25日"), number(2026, 12, 25))
        XCTAssertEqual(parse("2月30日"), nil)
        // 节日、节气、农历日子：今天以后最近的那次
        XCTAssertEqual(parse("国庆节"), today)
        XCTAssertEqual(parse("中秋节"), number(2027, 9, 15))
        XCTAssertEqual(parse("中秋"), number(2027, 9, 15))
        XCTAssertEqual(parse("春节"), number(2027, 2, 6))
        XCTAssertEqual(parse("除夕"), number(2027, 2, 5))
        XCTAssertEqual(parse("冬至"), number(2026, 12, 22))
        XCTAssertEqual(parse("母亲节"), number(2027, 5, 9))
        XCTAssertEqual(parse("农历八月十五"), number(2027, 9, 15))
        XCTAssertEqual(parse("腊月初八"), number(2027, 1, 15))
        XCTAssertEqual(CalendarMonth.parse("闰六月初一", today: number(2025, 1, 1)), number(2025, 7, 25))
        XCTAssertEqual(parse("October 1, 2026"), today)
        // 时间戳用写着的年月日，不按时区换算
        XCTAssertEqual(parse("2026-10-01T00:30:00+08:00"), today)
        XCTAssertEqual(parse("2026-10-01 23:59:59 -0700"), today)
        // 「清明节」「七夕节」去掉「节」也认
        XCTAssertEqual(parse("清明节"), number(2027, 4, 5))
        XCTAssertEqual(parse("七夕节"), number(2027, 8, 8))
        // 公历一二月里，快到的除夕、腊八还是上一个农历年的
        XCTAssertEqual(CalendarMonth.parse("除夕", today: number(2027, 1, 10)), number(2027, 2, 5))
        XCTAssertEqual(CalendarMonth.parse("腊八", today: number(2026, 1, 10)), number(2026, 1, 26))
        XCTAssertNil(parse("你好"))
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("2026-10-01\n2026-10-02"))
    }

    // MARK: - 卡片

    func testCardText() {
        let model = makeModel()
        XCTAssertEqual(model.year, 2026)
        XCTAssertEqual(model.month, 10)
        XCTAssertEqual(model.selected, number(2026, 10, 1))
        XCTAssertFalse(model.unrecognized)
        XCTAssertEqual(model.title, "2026年10月")
        XCTAssertEqual(model.lunarSubtitle, "丙午年 八月—九月")
        XCTAssertEqual(model.weekdaySymbols, ["一", "二", "三", "四", "五", "六", "日"])
        XCTAssertTrue(model.dateText.contains("2026年10月1日"))
        XCTAssertTrue(model.dateText.contains("星期四"))
        XCTAssertEqual(model.relativeText, "今天")
        XCTAssertEqual(model.lunarText, "农历丙午年（马年）八月廿一")
        XCTAssertEqual(model.eventsText, "国庆节")
        XCTAssertEqual(model.weekText, "第 40 周 · 全年第 274 天")
        XCTAssertEqual(model.nextTermText, "下一个节气：寒露，10月8日，还有 7 天")
        XCTAssertEqual(model.copyText, "\(model.dateText) 农历丙午年（马年）八月廿一 国庆节")

        // 节气那天
        model.select(number(2026, 10, 8))
        XCTAssertEqual(model.eventsText, "寒露")
        XCTAssertEqual(model.relativeText, "7 天后")
        model.select(number(2026, 9, 29))
        XCTAssertEqual(model.relativeText, "2 天前")
        XCTAssertEqual(model.month, 9)

        // 不显示农历：只剩公历的节日
        model.showsLunar = false
        model.select(number(2026, 10, 8))
        XCTAssertNil(model.lunarSubtitle)
        XCTAssertNil(model.lunarText)
        XCTAssertNil(model.eventsText)
        XCTAssertNil(model.nextTermText)
        model.select(number(2026, 10, 1))
        XCTAssertEqual(model.eventsText, "国庆节")
    }

    func testKeysAndMonths() {
        var copied: [String] = []
        let model = makeModel()
        model.onCopy = { copied.append($0) }
        XCTAssertTrue(model.handleKey(key(124)))
        XCTAssertEqual(model.relativeText, "明天")
        XCTAssertTrue(model.handleKey(key(125)))
        XCTAssertEqual(model.selected, number(2026, 10, 9))
        XCTAssertTrue(model.handleKey(key(126)))
        XCTAssertTrue(model.handleKey(key(123)))
        XCTAssertEqual(model.selected, number(2026, 10, 1))
        XCTAssertTrue(model.handleKey(key(123)))
        XCTAssertEqual(model.relativeText, "昨天")
        XCTAssertEqual(model.month, 9)
        // PageDown、⌘→ 换月，几号不变
        XCTAssertTrue(model.handleKey(key(121)))
        XCTAssertEqual(model.selected, number(2026, 10, 30))
        XCTAssertTrue(model.handleKey(key(124, "", modifiers: .command)))
        XCTAssertEqual(model.selected, number(2026, 11, 30))
        XCTAssertTrue(model.handleKey(key(116)))
        XCTAssertEqual(model.selected, number(2026, 10, 30))
        // T、Home 回到今天
        XCTAssertTrue(model.handleKey(key(17, "t")))
        XCTAssertTrue(model.isShowingToday)
        model.move(by: 40)
        XCTAssertTrue(model.handleKey(key(115)))
        XCTAssertTrue(model.isShowingToday)
        // ⌘C 复制这一天
        XCTAssertTrue(model.handleKey(key(8, "c", modifiers: .command)))
        XCTAssertEqual(copied, [model.copyText])
        XCTAssertFalse(model.handleKey(key(0, "a")))

        // 1 月 31 日往后翻一个月是 2 月的最后一天；跨年
        model.select(number(2027, 1, 31))
        model.showMonth(offset: 1)
        XCTAssertEqual(model.selected, number(2027, 2, 28))
        model.select(number(2026, 12, 15))
        model.showMonth(offset: 1)
        XCTAssertEqual([model.year, model.month], [2027, 1])
        // 只能翻到 1900–2100 年
        model.select(number(1800, 1, 1))
        XCTAssertEqual(model.selected, number(1900, 1, 1))
        model.select(number(2100, 12, 20))
        model.showMonth(offset: 1)
        XCTAssertEqual([model.year, model.month], [2100, 12])
    }

    func testSelectionAndSettings() {
        let opened = makeModel(text: "中秋节")
        XCTAssertEqual(opened.selected, number(2027, 9, 15))
        XCTAssertEqual([opened.year, opened.month], [2027, 9])
        XCTAssertEqual(opened.eventsText, "中秋节")
        XCTAssertEqual(opened.relativeText, "349 天后")
        let unknown = makeModel(text: "你好")
        XCTAssertTrue(unknown.unrecognized)
        XCTAssertFalse(unknown.outOfRange)
        XCTAssertTrue(unknown.isShowingToday)
        // 1900–2100 年以外的日子翻不到：停在今天，说一声
        let far = makeModel(text: "2150-01-01")
        XCTAssertTrue(far.outOfRange)
        XCTAssertFalse(far.unrecognized)
        XCTAssertTrue(far.isShowingToday)
        // 下一个节气就在明天
        opened.select(number(2026, 10, 7))
        XCTAssertEqual(opened.nextTermText, "下一个节气：寒露，10月8日，就是明天")

        // 显不显示农历会记住；没设过时中文界面默认显示
        let defaults = freshDefaults()
        let first = makeModel(defaults: defaults, showsLunar: nil)
        XCTAssertTrue(first.showsLunar)
        first.showsLunar = false
        XCTAssertFalse(makeModel(defaults: defaults, showsLunar: nil).showsLunar)
    }

    func testPluginAndDemo() {
        XCTAssertTrue(CalendarPlugin().info.canHandle(.empty))
        let demo = CalendarPlugin.demoModel()
        XCTAssertTrue(demo.isShowingToday)
        XCTAssertEqual(demo.eventsText, "国庆节")
        XCTAssertTrue(demo.showsLunar)
    }
}
