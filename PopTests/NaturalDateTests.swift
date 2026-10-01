import XCTest
@testable import Pop

final class NaturalDateTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    /// 2026-09-29（周二）10:00
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 10, minute: 0))!
    }

    private func parse(_ text: String) -> NaturalDate.Result? {
        NaturalDate.parse(text, now: now, calendar: calendar)
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testDaysAndTimes() {
        XCTAssertEqual(parse("明天下午3点开会"), NaturalDate.Result(date: date(9, 30, 15), hasTime: true, title: "开会"))
        XCTAssertEqual(parse("今晚8点半看电影"), NaturalDate.Result(date: date(9, 29, 20, 30), hasTime: true, title: "看电影"))
        XCTAssertEqual(parse("后天上午十点一刻体检"), NaturalDate.Result(date: date(10, 1, 10, 15), hasTime: true, title: "体检"))
        XCTAssertEqual(parse("明早提醒我带伞"), NaturalDate.Result(date: date(9, 30, 9), hasTime: true, title: "带伞"))
        XCTAssertEqual(parse("明天晚上吃饭"), NaturalDate.Result(date: date(9, 30, 20), hasTime: true, title: "吃饭"))
        XCTAssertEqual(parse("大后天交房租"), NaturalDate.Result(date: date(10, 2), hasTime: false, title: "交房租"))
    }

    func testClockOnly() {
        // 没说时段的 1–6 点按下午算
        XCTAssertEqual(parse("3点开会"), NaturalDate.Result(date: date(9, 29, 15), hasTime: true, title: "开会"))
        // 已经过了的钟点是明天
        XCTAssertEqual(parse("9:30 站会"), NaturalDate.Result(date: date(9, 30, 9, 30), hasTime: true, title: "站会"))
        XCTAssertEqual(parse("晚上11点睡觉"), NaturalDate.Result(date: date(9, 29, 23), hasTime: true, title: "睡觉"))
    }

    func testWeekdays() {
        XCTAssertEqual(parse("提醒我周五之前交周报"), NaturalDate.Result(date: date(10, 2), hasTime: false, title: "交周报"))
        XCTAssertEqual(parse("下周一 9:30 例会"), NaturalDate.Result(date: date(10, 5, 9, 30), hasTime: true, title: "例会"))
        XCTAssertEqual(parse("下下周三复盘"), NaturalDate.Result(date: date(10, 14), hasTime: false, title: "复盘"))
        // 今天就是周二
        XCTAssertEqual(parse("周二的会议"), NaturalDate.Result(date: date(9, 29), hasTime: false, title: "会议"))
        // 周一已经过了：下一个周一
        XCTAssertEqual(parse("星期一交材料"), NaturalDate.Result(date: date(10, 5), hasTime: false, title: "交材料"))
    }

    func testDatesAndDurations() {
        XCTAssertEqual(parse("10月8日发布新版本"), NaturalDate.Result(date: date(10, 8), hasTime: false, title: "发布新版本"))
        XCTAssertEqual(parse("2026-10-08 14:00 评审"), NaturalDate.Result(date: date(10, 8, 14), hasTime: true, title: "评审"))
        // 没写年份、日子已经过了：明年
        XCTAssertEqual(parse("3月1日续费"), NaturalDate.Result(date: date(3, 1, year: 2027), hasTime: false, title: "续费"))
        XCTAssertEqual(parse("2号还信用卡"), NaturalDate.Result(date: date(10, 2), hasTime: false, title: "还信用卡"))
        XCTAssertEqual(parse("半小时后给妈妈打电话"), NaturalDate.Result(date: date(9, 29, 10, 30), hasTime: true, title: "给妈妈打电话"))
        XCTAssertEqual(parse("两个小时以后出发"), NaturalDate.Result(date: date(9, 29, 12), hasTime: true, title: "出发"))
        XCTAssertEqual(parse("三天后复查"), NaturalDate.Result(date: date(10, 2), hasTime: false, title: "复查"))
    }

    func testNotADate() {
        XCTAssertNil(parse("这是一段普通的文字"))
        XCTAssertNil(parse("会议室在 A 座三楼"))
        XCTAssertNil(parse("   "))
    }

    func testChineseNumbers() {
        XCTAssertEqual(["一", "两", "十", "十二", "二十", "二十三", "九十九"].map(NaturalDate.chineseNumber), [1, 2, 10, 12, 20, 23, 99])
        XCTAssertNil(NaturalDate.chineseNumber("一百"))
    }

    func testOtherLanguages() throws {
        // 英文交给系统识别，以真实的今天为准
        let result = try XCTUnwrap(NaturalDate.parse("Call Alice tomorrow at 3pm"))
        XCTAssertTrue(result.hasTime)
        XCTAssertEqual(result.title, "Call Alice")
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        XCTAssertTrue(Calendar.current.isDate(result.date, inSameDayAs: tomorrow))
        XCTAssertEqual(Calendar.current.component(.hour, from: result.date), 15)
    }

    @MainActor
    func testDraft() {
        let draft = ReminderDraft(text: "明天下午3点开会", now: now, calendar: calendar)
        XCTAssertEqual(draft.title, "开会")
        XCTAssertEqual(draft.date, date(9, 30, 15))
        XCTAssertTrue(draft.hasTime)
        XCTAssertTrue(draft.recognized)
        XCTAssertEqual(draft.notes, "明天下午3点开会")
        XCTAssertEqual(draft.summary(now: now, calendar: calendar), "9月30日 周三 15:00 · 明天")
        // 认不出时间：默认明天上午 9 点，标题就是原文
        let plain = ReminderDraft(text: "买牛奶", now: now, calendar: calendar)
        XCTAssertFalse(plain.recognized)
        XCTAssertEqual(plain.date, date(9, 30, 9))
        XCTAssertNil(plain.notes)
    }

    func testReminderDueDate() {
        let timed = ReminderService.components(date(9, 30, 15), hasTime: true, calendar: calendar)
        XCTAssertEqual(timed.hour, 15)
        XCTAssertEqual(timed.day, 30)
        let allDay = ReminderService.components(date(9, 30), hasTime: false, calendar: calendar)
        XCTAssertNil(allDay.hour)
        XCTAssertEqual(allDay.day, 30)
    }

    @MainActor
    func testPlugin() async {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let outcome = await ReminderPlugin().run(ContentClassifier.classify(.text("明天开会")), context: context)
        guard case .present = outcome else { return XCTFail("应该弹出加到提醒事项的卡片") }
        XCTAssertTrue(ReminderPlugin().info.canHandle(ContentClassifier.classify(.text("周五交周报"))))
        XCTAssertFalse(ReminderPlugin().info.canHandle(ContentClassifier.classify(.text("买牛奶"))))
    }
}
