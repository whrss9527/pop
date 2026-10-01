import XCTest
@testable import Pop

final class WorldTimeTests: XCTestCase {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let london = TimeZone(identifier: "Europe/London")!
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    /// 北京时间 2026-10-02 10:30（周五）
    private let now = Date(timeIntervalSince1970: 1_790_908_200)

    private func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text)!
    }

    private func parse(_ text: String, local: TimeZone? = nil) -> WorldTime.Parsed? {
        WorldTime.parse(text, now: now, local: local ?? shanghai)
    }

    // MARK: - 认时区

    func testAbbreviations() throws {
        // 洛杉矶这时是 10 月 1 日晚上，下午 3 点已经过了：按接下来的那个下午（10 月 2 日）算；
        // 10 月还在夏令时，PST 也按当地的时间算，另外提示一句
        let pst = try XCTUnwrap(parse("3pm PST"))
        XCTAssertEqual(pst.zone.identifier, "America/Los_Angeles")
        XCTAssertEqual(pst.date, date("2026-10-02T22:00:00Z"))
        XCTAssertEqual(pst.zoneText, "PST")
        XCTAssertTrue(pst.hasTime)
        XCTAssertEqual(pst.hint, "PST 按洛杉矶当地的时间算：这一天那里在用夏令时（UTC−7）")
        // 写对了的 PDT 不提示
        XCTAssertNil(try XCTUnwrap(parse("3pm PDT")).hint)
        XCTAssertEqual(try XCTUnwrap(parse("3:30 PM ET")).date, date("2026-10-02T19:30:00Z"))
        // 东京这时 11:30，9 点过去两个半小时了：算明天的
        XCTAssertEqual(try XCTUnwrap(parse("9:00 JST")).date, date("2026-10-03T00:00:00Z"))
        // 过去不到一小时的还算今天
        XCTAssertEqual(try XCTUnwrap(parse("11:00 JST")).date, date("2026-10-02T02:00:00Z"))
        XCTAssertEqual(try XCTUnwrap(parse("10am BST")).date, date("2026-10-02T09:00:00Z"))
        XCTAssertEqual(try XCTUnwrap(parse("11:00 IST")).zone.identifier, "Asia/Kolkata")
        // 在东八区写 CST 是中国标准时间，在别处是美国中部时间
        XCTAssertEqual(try XCTUnwrap(parse("15:00 CST")).zone.identifier, "Asia/Shanghai")
        XCTAssertEqual(try XCTUnwrap(parse("15:00 CST", local: london)).zone.identifier, "America/Chicago")
        // 小写的 et、pt 是普通的词，不当成时区
        XCTAssertNil(parse("et pt"))
    }

    func testOffsets() throws {
        let utc8 = try XCTUnwrap(parse("10:00 UTC+8", local: losAngeles))
        XCTAssertEqual(utc8.zone.secondsFromGMT(), 8 * 3600)
        XCTAssertEqual(utc8.zoneText, "UTC+8")
        let india = try XCTUnwrap(parse("GMT+05:30 18:00"))
        XCTAssertEqual(india.zone.secondsFromGMT(), 19_800)
        XCTAssertEqual(try XCTUnwrap(parse("9:00 UTC")).date, date("2026-10-02T09:00:00Z"))
        XCTAssertEqual(try XCTUnwrap(parse("东八区 9 点", local: london)).zone.secondsFromGMT(), 8 * 3600)
        XCTAssertEqual(try XCTUnwrap(parse("西五区 9 点")).zone.secondsFromGMT(), -5 * 3600)
        // 带偏移的完整时间戳
        let iso = try XCTUnwrap(parse("2026-10-02T15:00:00-07:00"))
        XCTAssertEqual(iso.date, date("2026-10-02T22:00:00Z"))
        XCTAssertEqual(iso.zone.secondsFromGMT(), -7 * 3600)
        XCTAssertEqual(try XCTUnwrap(parse("2026-10-02T15:00Z")).date, date("2026-10-02T15:00:00Z"))
        XCTAssertEqual(try XCTUnwrap(parse("2026-10-02 15:00:00 +0800")).date, date("2026-10-02T07:00:00Z"))
        XCTAssertEqual(try XCTUnwrap(parse("Fri, 2 Oct 2026 15:00:00 -0700")).date, date("2026-10-02T22:00:00Z"))
    }

    func testChinesePhrasesAndCities() throws {
        let beijing = try XCTUnwrap(parse("北京时间晚上 9 点", local: london))
        XCTAssertEqual(beijing.zone.identifier, "Asia/Shanghai")
        XCTAssertEqual(beijing.date, date("2026-10-02T13:00:00Z"))
        XCTAssertEqual(beijing.zoneText, "北京时间")
        XCTAssertEqual(try XCTUnwrap(parse("美东时间上午 10:30")).date, date("2026-10-02T14:30:00Z"))
        XCTAssertEqual(try XCTUnwrap(parse("日本时间 18:00")).zone.identifier, "Asia/Tokyo")
        XCTAssertEqual(try XCTUnwrap(parse("明天下午 3 点（伦敦时间）")).date, date("2026-10-03T14:00:00Z"))
        XCTAssertEqual(try XCTUnwrap(parse("Pacific Time 9am")).zone.identifier, "America/Los_Angeles")
        XCTAssertEqual(try XCTUnwrap(parse("10am New York time")).date, date("2026-10-02T14:00:00Z"))
        XCTAssertEqual(try XCTUnwrap(parse("伦敦 3pm")).zone.identifier, "Europe/London")
        XCTAssertEqual(try XCTUnwrap(parse("3pm in Paris")).zone.identifier, "Europe/Paris")
        XCTAssertEqual(try XCTUnwrap(parse("America/Sao_Paulo 08:00")).zone.identifier, "America/Sao_Paulo")
        // 当地时间：按本地算
        XCTAssertEqual(try XCTUnwrap(parse("当地时间 8 点", local: tokyo)).zone.identifier, "Asia/Tokyo")
    }

    func testZoneWithoutTimeShowsNow() throws {
        let city = try XCTUnwrap(parse("伦敦"))
        XCTAssertFalse(city.hasTime)
        XCTAssertEqual(city.date, now)
        XCTAssertEqual(city.zone.identifier, "Europe/London")
        XCTAssertEqual(try XCTUnwrap(parse("Tokyo")).zone.identifier, "Asia/Tokyo")
        XCTAssertEqual(try XCTUnwrap(parse("PST")).zone.identifier, "America/Los_Angeles")
        // 英文的城市、国家名要大写开头
        XCTAssertEqual(WorldTime.findZone(in: "Turkey 6pm", local: london, now: now)?.zone.identifier, "Europe/Istanbul")
        XCTAssertNil(WorldTime.findZone(in: "turkey dinner at 6pm", local: london, now: now))
        XCTAssertNil(parse("今天天气不错"))
        XCTAssertNil(parse(""))
    }

    // MARK: - 认时间和日子

    func testTimes() {
        XCTAssertEqual(WorldTime.findTime(in: "15:30"), WorldTime.Time(hour: 15, minute: 30))
        XCTAssertEqual(WorldTime.findTime(in: "3:30 p.m."), WorldTime.Time(hour: 15, minute: 30))
        XCTAssertEqual(WorldTime.findTime(in: "12am"), WorldTime.Time(hour: 0, minute: 0))
        XCTAssertEqual(WorldTime.findTime(in: "12 PM"), WorldTime.Time(hour: 12, minute: 0))
        XCTAssertEqual(WorldTime.findTime(in: "下午三点半"), WorldTime.Time(hour: 15, minute: 30))
        XCTAssertEqual(WorldTime.findTime(in: "上午十点一刻"), WorldTime.Time(hour: 10, minute: 15))
        XCTAssertEqual(WorldTime.findTime(in: "晚上 8 点 20 分"), WorldTime.Time(hour: 20, minute: 20))
        XCTAssertEqual(WorldTime.findTime(in: "中午 1 点"), WorldTime.Time(hour: 13, minute: 0))
        XCTAssertEqual(WorldTime.findTime(in: "凌晨两点"), WorldTime.Time(hour: 2, minute: 0))
        XCTAssertEqual(WorldTime.findTime(in: "晚上 12 点"), WorldTime.Time(hour: 0, minute: 0, nextDay: true))
        XCTAssertEqual(WorldTime.findTime(in: "夜里 1 点"), WorldTime.Time(hour: 1, minute: 0, nextDay: true))
        XCTAssertEqual(WorldTime.findTime(in: "下午 3:15"), WorldTime.Time(hour: 15, minute: 15))
        XCTAssertEqual(WorldTime.findTime(in: "noon"), WorldTime.Time(hour: 12, minute: 0))
        XCTAssertEqual(WorldTime.findTime(in: "10:20:30"), WorldTime.Time(hour: 10, minute: 20, second: 30))
        XCTAssertNil(WorldTime.findTime(in: "25:00"))
        XCTAssertNil(WorldTime.findTime(in: "13pm"))
        XCTAssertNil(WorldTime.findTime(in: "3 小时"))
        // 光写「一点」不是时间
        XCTAssertNil(WorldTime.findTime(in: "晚一点再说"))
        XCTAssertNil(WorldTime.findTime(in: "差一点就赶上了"))
        XCTAssertEqual(WorldTime.findTime(in: "晚一点再说，三点开会"), WorldTime.Time(hour: 3, minute: 0))
        XCTAssertEqual(WorldTime.findTime(in: "一点钟"), WorldTime.Time(hour: 1, minute: 0))
        XCTAssertEqual(WorldTime.findTime(in: "一点半"), WorldTime.Time(hour: 1, minute: 30))
        XCTAssertEqual(WorldTime.findTime(in: "下午一点"), WorldTime.Time(hour: 13, minute: 0))
        XCTAssertEqual(WorldTime.chineseNumber("二十三"), 23)
        XCTAssertEqual(WorldTime.chineseNumber("十"), 10)
        XCTAssertEqual(WorldTime.chineseNumber("两"), 2)
        XCTAssertNil(WorldTime.chineseNumber("一百"))
    }

    func testDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        func day(_ text: String) -> String? {
            guard let parts = WorldTime.findDay(in: text, now: now, calendar: calendar),
                  let year = parts.year, let month = parts.month, let dayOfMonth = parts.day else { return nil }
            return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
        }
        // 今天是 2026-10-02 周五
        XCTAssertEqual(day("2026-10-08 9:00"), "2026-10-08")
        XCTAssertEqual(day("10月3日"), "2026-10-03")
        XCTAssertEqual(day("2027年1月5日"), "2027-01-05")
        XCTAssertEqual(day("Oct 3, 2026"), "2026-10-03")
        XCTAssertEqual(day("3 Oct"), "2026-10-03")
        XCTAssertEqual(day("明天"), "2026-10-03")
        XCTAssertEqual(day("后天"), "2026-10-04")
        XCTAssertEqual(day("昨天"), "2026-10-01")
        XCTAssertEqual(day("tomorrow"), "2026-10-03")
        XCTAssertEqual(day("周五"), "2026-10-02")
        XCTAssertEqual(day("周一"), "2026-10-05")
        XCTAssertEqual(day("下周三"), "2026-10-07")
        XCTAssertEqual(day("本周三"), "2026-09-30")
        XCTAssertEqual(day("next Friday"), "2026-10-09")
        XCTAssertEqual(day("Monday"), "2026-10-05")
        // 没写年份：取离今天最近的那一年
        XCTAssertEqual(day("1月3日"), "2027-01-03")
        XCTAssertEqual(day("9月30日"), "2026-09-30")
        XCTAssertNil(day("2月30日"))
        XCTAssertNil(day("one month"))
    }

    // MARK: - 写法

    func testFormatting() {
        let moment = date("2026-10-01T22:00:00Z")
        XCTAssertEqual(WorldTime.offsetText(losAngeles, at: moment), "UTC−7")
        XCTAssertEqual(WorldTime.offsetText(shanghai, at: moment), "UTC+8")
        XCTAssertEqual(WorldTime.offsetText(TimeZone(identifier: "Asia/Kolkata")!, at: moment), "UTC+5:30")
        XCTAssertEqual(WorldTime.offsetText(TimeZone(identifier: "UTC")!, at: moment), "UTC")
        XCTAssertEqual(WorldTime.timeText(moment, in: shanghai), "06:00")
        XCTAssertEqual(WorldTime.dateText(moment, in: shanghai), "10月2日周五")
        XCTAssertEqual(WorldTime.dayOffset(moment, in: losAngeles, from: shanghai), -1)
        XCTAssertEqual(WorldTime.dayOffset(moment, in: shanghai, from: losAngeles), 1)
        XCTAssertEqual(WorldTime.dayOffset(moment, in: tokyo, from: shanghai), 0)
        XCTAssertEqual(WorldTime.minuteOfDay(moment, in: shanghai), 360)
        XCTAssertEqual(WorldTime.DayPart.of(minute: 600), .work)
        XCTAssertEqual(WorldTime.DayPart.of(minute: 1100), .edge)
        XCTAssertEqual(WorldTime.DayPart.of(minute: 60), .night)
    }

    func testCommonWorkingHours() throws {
        // 北京和伦敦（夏令时）：北京 16:00–18:00 = 伦敦 9:00–11:00
        let day = date("2026-10-01T16:00:00Z") // 北京 10 月 2 日零点
        let both = try XCTUnwrap(WorldTime.commonWorkingHours(on: day, zones: [shanghai, london]))
        XCTAssertEqual(both.start, date("2026-10-02T08:00:00Z"))
        XCTAssertEqual(both.end, date("2026-10-02T10:00:00Z"))
        // 加上纽约就凑不上了
        XCTAssertNil(WorldTime.commonWorkingHours(on: day, zones: [shanghai, london, newYork]))
        // 只有一个时区不算
        XCTAssertNil(WorldTime.commonWorkingHours(on: day, zones: [shanghai]))
    }

    func testSearch() {
        XCTAssertEqual(WorldTime.search("东京").first?.id, "tokyo")
        XCTAssertEqual(WorldTime.search("dj").first?.id, "tokyo")
        XCTAssertEqual(WorldTime.search("Tokyo").first?.id, "tokyo")
        XCTAssertEqual(WorldTime.search("jiujinshan").first?.id, "sanFrancisco")
        XCTAssertTrue(WorldTime.search("PST").contains { $0.id == "losAngeles" })
        XCTAssertTrue(WorldTime.search("日本").contains { $0.id == "tokyo" })
        XCTAssertTrue(WorldTime.search("美国").contains { $0.id == "chicago" })
        XCTAssertFalse(WorldTime.search("东京", excluding: ["tokyo"]).contains { $0.id == "tokyo" })
        // 表里没有的时区按时区标识找
        let boise = WorldTime.search("boise")
        XCTAssertEqual(boise.first?.id, "tz:America/Boise")
        XCTAssertEqual(boise.first?.name, "Boise")
        XCTAssertEqual(WorldTime.city(id: "tz:America/Boise")?.timeZone.identifier, "America/Boise")
        XCTAssertNil(WorldTime.city(id: "nowhere"))
        XCTAssertTrue(WorldTime.search("").isEmpty)
        // 每个城市的时区这个系统上都有
        XCTAssertEqual(WorldTime.cities.count, 69)
        XCTAssertEqual(Set(WorldTime.cities.map(\.id)).count, WorldTime.cities.count)
        for id in WorldTime.defaultCityIDs {
            XCTAssertNotNil(WorldTime.city(id: id), id)
        }
    }

    // MARK: - 卡片

    @MainActor
    func testCardRowsForSelectedTime() throws {
        let model = WorldTimePlugin.demoModel()
        XCTAssertEqual(model.headline, "「3pm PST」是洛杉矶 10月2日周五 15:00")
        XCTAssertNotNil(model.parsed?.hint)
        let rows = model.rows
        // 洛杉矶不在常用城市里：临时放在最上面；本地（北京）也列出来
        XCTAssertEqual(rows.map(\.city.name), ["洛杉矶", "北京", "伦敦", "纽约", "东京"])
        XCTAssertEqual(rows.map(\.time), ["15:00", "06:00", "23:00", "18:00", "07:00"])
        XCTAssertEqual(rows.map(\.dayOffset), [-1, 0, -1, -1, 0])
        XCTAssertTrue(rows[0].isSource)
        XCTAssertFalse(rows[0].isSaved)
        XCTAssertTrue(rows[1].isLocal)
        // 后面跟的缩写（PDT、BST）系统不一定给得出来，给不出来时写「夏令时」
        XCTAssertTrue(rows[0].detail.hasPrefix("UTC−7 · "), rows[0].detail)
        XCTAssertTrue(rows[2].detail.hasPrefix("UTC+1 · "), rows[2].detail)
        XCTAssertEqual(rows[1].detail, "UTC+8")
        // 美国、北京、伦敦凑不上大家都在上班的时间
        XCTAssertNil(model.overlap)
        XCTAssertEqual(model.overlapText, "这几个地方没有都在 9:00–18:00 之间的时间")
        XCTAssertEqual(model.copyText.components(separatedBy: "\n").first, "洛杉矶 10月2日周五 15:00（UTC−7）")
        XCTAssertFalse(model.followsNow)
    }

    @MainActor
    func testShiftingAndOverlap() {
        let model = WorldTimeModel(text: nil, now: { self.now }, local: shanghai, cityIDs: ["london"], usesTimers: false)
        XCTAssertNil(model.headline)
        XCTAssertFalse(model.unrecognized)
        XCTAssertTrue(model.followsNow)
        XCTAssertEqual(model.rows.map(\.city.name), ["北京", "伦敦"])
        XCTAssertEqual(model.shiftText, "拖动换个时间")
        model.setShift(155)
        XCTAssertEqual(model.shiftMinutes, 150)
        XCTAssertEqual(model.shiftText, "+2 小时 30 分钟")
        XCTAssertEqual(model.rows.first?.time, "13:00")
        model.setShift(-45)
        XCTAssertEqual(model.shiftText, "\u{2212}45 分钟")
        model.setShift(5000)
        XCTAssertEqual(model.shiftMinutes, WorldTimeModel.shiftLimit)
        // 北京和伦敦都在上班：北京 16:00–18:00；点「看看那时」跳过去
        model.reset()
        XCTAssertEqual(model.shiftMinutes, 0)
        XCTAssertEqual(model.overlapText, "大家都在上班（9:00–18:00）：本地 16:00–18:00")
        model.jumpToOverlap()
        XCTAssertEqual(model.rows.map(\.time), ["16:00", "09:00"])
    }

    @MainActor
    func testAddingAndRemovingCities() {
        let suite = "WorldTimeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = WorldTimeModel(text: "随便一段话", now: { self.now }, local: shanghai, defaults: defaults, usesTimers: false)
        XCTAssertTrue(model.unrecognized)
        XCTAssertEqual(model.cityIDs, WorldTime.defaultCityIDs)
        // 东京已经在列表里，搜不到；新加坡按拼音首字母搜得到
        model.search = "dj"
        XCTAssertFalse(model.results.contains { $0.id == "tokyo" })
        model.search = "xjp"
        XCTAssertEqual(model.results.first?.id, "singapore")
        model.search = "首尔"
        model.addFirstResult()
        XCTAssertEqual(model.cityIDs.last, "seoul")
        XCTAssertEqual(model.search, "")
        XCTAssertEqual(defaults.stringArray(forKey: WorldTimeModel.citiesKey)?.last, "seoul")
        model.remove("london")
        XCTAssertFalse(model.rows.contains { $0.city.id == "london" })
        // 存下来的城市下次打开还在
        let reopened = WorldTimeModel(now: { self.now }, local: shanghai, defaults: defaults, usesTimers: false)
        XCTAssertEqual(reopened.cityIDs, ["beijing", "newYork", "sanFrancisco", "tokyo", "seoul"])
        // 北京本来就在列表里：标成本地，不另外加一行
        XCTAssertEqual(reopened.rows.filter(\.isLocal).map(\.city.id), ["beijing"])
        XCTAssertEqual(reopened.rows.count, 5)
    }

    @MainActor
    func testSourceZoneAlreadyInList() throws {
        // 选中的时区就在常用城市里：那一行标成选中的，不另外加
        let model = WorldTimeModel(text: "9am JST", now: { self.now }, local: shanghai, cityIDs: ["beijing", "tokyo"], usesTimers: false)
        let rows = model.rows
        XCTAssertEqual(rows.map(\.city.id), ["beijing", "tokyo"])
        XCTAssertEqual(rows.filter(\.isSource).map(\.city.id), ["tokyo"])
        XCTAssertEqual(rows.map(\.time), ["08:00", "09:00"])
        XCTAssertNil(model.parsed?.hint)
    }

    func testPluginNeedsNoSelection() {
        XCTAssertTrue(WorldTimePlugin().info.canHandle(.empty))
    }
}
