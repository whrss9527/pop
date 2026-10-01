import AppKit
import XCTest
@testable import Pop

final class ChartTests: XCTestCase {
    func testNumbers() throws {
        func number(_ text: String) -> ChartData.Number? { ChartData.number(text) }
        XCTAssertEqual(number("1,200"), ChartData.Number(value: 1200, unit: nil, decimals: 0))
        XCTAssertEqual(number("12.5%"), ChartData.Number(value: 12.5, unit: "%", decimals: 1))
        XCTAssertEqual(number("¥3,000"), ChartData.Number(value: 3000, unit: "¥", decimals: 0))
        XCTAssertEqual(number("￥3,000")?.unit, "¥")
        XCTAssertEqual(number("$1.5k"), ChartData.Number(value: 1500, unit: "$", decimals: 0))
        XCTAssertEqual(number("12K")?.value, 12000)
        XCTAssertEqual(number("1.2万")?.value, 12000)
        XCTAssertEqual(number("3亿")?.value, 300_000_000)
        XCTAssertEqual(number("-8")?.value, -8)
        XCTAssertEqual(number("\u{2212}8")?.value, -8)
        XCTAssertEqual(number("(1,200)")?.value, -1200)
        XCTAssertEqual(number("36 kg"), ChartData.Number(value: 36, unit: "kg", decimals: 0))
        XCTAssertEqual(number("120元"), ChartData.Number(value: 120, unit: "元", decimals: 0))
        XCTAssertNil(number("abc"))
        XCTAssertNil(number("12 apples"))
        XCTAssertNil(number("2026-10-02"))
        XCTAssertNil(number("1.2.3"))
        XCTAssertNil(number(""))
    }

    func testTableWithHeader() throws {
        let data = try XCTUnwrap(ChartData.parse("月份\t销售额\t成本\n1月\t120\t82\n2月\t135\t86\n3月\t162\t95"))
        XCTAssertEqual(data.labels, ["1月", "2月", "3月"])
        XCTAssertEqual(data.series, [ChartData.Series(name: "销售额", values: [120, 135, 162]), ChartData.Series(name: "成本", values: [82, 86, 95])])
        XCTAssertEqual(data.labelTitle, "月份")
        XCTAssertNil(data.unit)
        XCTAssertEqual(data.decimals, 0)
        // CSV、Markdown 表格也认
        let csv = try XCTUnwrap(ChartData.parse("Name,Score\nAlice,90\nBob,85.5"))
        XCTAssertEqual(csv.labels, ["Alice", "Bob"])
        XCTAssertEqual(csv.series.first?.values, [90, 85.5])
        XCTAssertEqual(csv.decimals, 1)
        let markdown = try XCTUnwrap(ChartData.parse("| 浏览器 | 占比 |\n| --- | --- |\n| Chrome | 65.2% |\n| Safari | 18.6% |"))
        XCTAssertEqual(markdown.labels, ["Chrome", "Safari"])
        XCTAssertEqual(markdown.unit, "%")
        XCTAssertEqual(markdown.series.first?.name, "占比")
    }

    func testTableWithoutHeader() throws {
        // 从表格软件里只复制了数据，没有表头
        let data = try XCTUnwrap(ChartData.parse("北京\t21\n上海\t25\n广州\t28"))
        XCTAssertEqual(data.labels, ["北京", "上海", "广州"])
        XCTAssertEqual(data.series, [ChartData.Series(name: "数值", values: [21, 25, 28])])
        XCTAssertNil(data.labelTitle)
        // 都是数：第一列（年份）当名字
        let years = try XCTUnwrap(ChartData.parse("2022\t310\n2023\t356\n2024\t402"))
        XCTAssertEqual(years.labels, ["2022", "2023", "2024"])
        XCTAssertEqual(years.series.first?.values, [310, 356, 402])
        // 第一列是年份、名字在后面：年份不当成一组数；重名的加上 2
        let regions = try XCTUnwrap(ChartData.parse("年份,地区,销售额\n2024,华东,120\n2024,华南,90\n2025,华东,150"))
        XCTAssertEqual(regions.labels, ["华东", "华南", "华东 2"])
        XCTAssertEqual(regions.series.map(\.name), ["销售额"])
        // 月份那一列在后面：「1月」也像数，还是当名字
        let months = try XCTUnwrap(ChartData.parse("销售额,月份\n120,1月\n135,2月\n162,3月"))
        XCTAssertEqual(months.labels, ["1月", "2月", "3月"])
        XCTAssertEqual(months.series, [ChartData.Series(name: "销售额", values: [120, 135, 162])])
        XCTAssertEqual(months.labelTitle, "月份")
        // 只有一行数据的表画不成图
        XCTAssertNil(ChartData.parse("名字,分数\n张三,90"))
    }

    func testLinesAndLists() throws {
        let fruits = try XCTUnwrap(ChartData.parse("苹果 12\n香蕉：8\n橙子, 15"))
        XCTAssertEqual(fruits.labels, ["苹果", "香蕉", "橙子"])
        XCTAssertEqual(fruits.series.first?.values, [12, 8, 15])
        // 第一行没有数：当标题
        let titled = try XCTUnwrap(ChartData.parse("水果销量\n苹果 12\n香蕉 8"))
        XCTAssertEqual(titled.series.first?.name, "水果销量")
        XCTAssertEqual(titled.labels, ["苹果", "香蕉"])
        let browsers = try XCTUnwrap(ChartData.parse("Chrome 65.2%\nSafari 18.6%\nEdge 5.1%\n其他 11.1%"))
        XCTAssertEqual(browsers.unit, "%")
        XCTAssertEqual(browsers.decimals, 1)
        XCTAssertEqual(ChartData.kinds(for: browsers), [.bar, .horizontal, .line, .pie])
        XCTAssertEqual(ChartData.suggestedKind(for: browsers), .bar)
        // 一串数
        let list = try XCTUnwrap(ChartData.parse("12, 15, 9, 20"))
        XCTAssertEqual(list.labels, ["1", "2", "3", "4"])
        XCTAssertEqual(list.series.first?.values, [12, 15, 9, 20])
        XCTAssertEqual(try XCTUnwrap(ChartData.parse("12 15 9 20")).series.first?.values.count, 4)
        XCTAssertEqual(try XCTUnwrap(ChartData.parse("0% 15% 30%")).series.first?.values, [0, 15, 30])
        // 画不了的
        XCTAssertNil(ChartData.parse("今天天气不错"))
        XCTAssertNil(ChartData.parse("42"))
        XCTAssertNil(ChartData.parse("3 apples and 5 pears"))
        XCTAssertNil(ChartData.parse("上海市徐汇区漕溪北路 88 号 12 楼"))
        XCTAssertNil(ChartData.parse("{\n  \"a\": 1,\n  \"b\": 2\n}"))
        // 两个数、两行、电话号码、一串年份：不是要画的数据
        XCTAssertNil(ChartData.parse("3 5"))
        XCTAssertNil(ChartData.parse("a = 1\nb = 2"))
        XCTAssertNil(ChartData.parse("138 0013 8000"))
        XCTAssertNil(ChartData.parse("2022 2023 2024"))
    }

    func testKindsAndOrder() throws {
        XCTAssertTrue(ChartData.looksLikeTimeline(["1月", "2月", "3月"]))
        XCTAssertTrue(ChartData.looksLikeTimeline(["2022", "2023", "2024"]))
        XCTAssertTrue(ChartData.looksLikeTimeline(["Q1", "Q2", "Q3", "Q4"]))
        XCTAssertTrue(ChartData.looksLikeTimeline(["Jan", "Feb", "Mar"]))
        XCTAssertTrue(ChartData.looksLikeTimeline(["周一", "周二", "周三"]))
        XCTAssertTrue(ChartData.looksLikeTimeline(["2024-01", "2024-02", "2024-03"]))
        XCTAssertFalse(ChartData.looksLikeTimeline(["苹果", "香蕉", "橙子"]))
        XCTAssertFalse(ChartData.looksLikeTimeline(["1月", "2月"]))

        let months = try XCTUnwrap(ChartData.parse(ChartPlugin.demoText))
        XCTAssertEqual(ChartData.suggestedKind(for: months), .line)
        // 两组数不能画饼图
        XCTAssertEqual(ChartData.kinds(for: months), [.bar, .horizontal, .line])
        let negative = try XCTUnwrap(ChartData.parse("一月 12\n二月 -3\n三月 8"))
        XCTAssertFalse(ChartData.kinds(for: negative).contains(.pie))
        let many = try XCTUnwrap(ChartData.parse((1...13).map { "第 \($0) 组 \($0 * 10)" }.joined(separator: "\n")))
        XCTAssertEqual(ChartData.suggestedKind(for: many), .horizontal)
        XCTAssertFalse(ChartData.kinds(for: many).contains(.pie))

        let fruits = try XCTUnwrap(ChartData.parse("苹果 12\n香蕉 8\n橙子 15"))
        let sorted = ChartData.sortedDescending(fruits)
        XCTAssertEqual(sorted.labels, ["橙子", "苹果", "香蕉"])
        XCTAssertEqual(sorted.series.first?.values, [15, 12, 8])
        XCTAssertEqual(ChartData.uniqued(["A", "B", "A", "A 2"]), ["A", "B", "A 3", "A 2"])
    }

    func testFormatting() {
        XCTAssertEqual(ChartData.format(1200, decimals: 0, unit: nil), "1,200")
        XCTAssertEqual(ChartData.format(12.5, decimals: 1, unit: "%"), "12.5%")
        XCTAssertEqual(ChartData.format(3000, decimals: 0, unit: "¥"), "¥3,000")
        XCTAssertEqual(ChartData.format(-8, decimals: 0, unit: nil), "-8")
        XCTAssertEqual(ChartData.format(36, decimals: 0, unit: "kg"), "36 kg")
        XCTAssertEqual(ChartData.format(120, decimals: 0, unit: "元"), "120元")
        XCTAssertEqual(ChartData.format(2, decimals: 2, unit: nil), "2")
        XCTAssertEqual(ChartData.percentText(1, total: 3), "33%")
        XCTAssertEqual(ChartData.percentText(1, total: 40), "2.5%")
        XCTAssertEqual(ChartData.percentText(5, total: 100), "5%")
        XCTAssertEqual(ChartData.percentText(1, total: 0), "0%")
    }

    @MainActor
    func testCardModelAndImage() throws {
        let suite = "ChartTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ChartPlugin.demoModel(defaults: defaults)
        XCTAssertEqual(model.kind, .line)
        XCTAssertEqual(model.kinds, [.bar, .horizontal, .line])
        XCTAssertEqual(model.summary, "6 项 · 2 组数")
        XCTAssertTrue(model.showsValues)
        XCTAssertEqual(model.fileName, "上半年销售额和成本（万元）")
        // 折线不排；换成柱状图后可以从大到小
        XCTAssertFalse(model.canSort)
        model.kind = .bar
        model.sortsDescending = true
        XCTAssertEqual(model.dataset.labels, ["6月", "5月", "3月", "4月", "2月", "1月"])
        model.showsValues = false
        XCTAssertEqual(defaults.object(forKey: ChartModel.valuesKey) as? Bool, false)

        // 存成的图片是 1920 × 1200 像素
        for kind in [ChartData.Kind.bar, .horizontal, .line] {
            model.kind = kind
            let png = try XCTUnwrap(model.png(), kind.rawValue)
            let image = try XCTUnwrap(NSBitmapImageRep(data: png))
            XCTAssertEqual(image.pixelsWide, 1920)
            XCTAssertEqual(image.pixelsHigh, 1200)
        }
        let pie = ChartModel(dataset: try XCTUnwrap(ChartData.parse("Chrome 65%\nSafari 19%\n其他 16%")), defaults: defaults)
        pie.kind = .pie
        XCTAssertNotNil(pie.png())
        XCTAssertEqual(pie.title, "")
        XCTAssertTrue(pie.fileName.hasPrefix("图表 "))
        // 一组数、带着表头：表头当标题
        let titled = ChartModel(dataset: try XCTUnwrap(ChartData.parse("城市,气温\n北京,21\n上海,25")), defaults: defaults)
        XCTAssertEqual(titled.title, "气温")
        XCTAssertEqual(titled.summary, "2 项")
    }

    func testPluginShowsUpOnlyForData() {
        let plugin = ChartPlugin()
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.text("月份\t销售额\n1月\t120\n2月\t135"))))
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.text("苹果 12\n香蕉 8\n橙子 15"))))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.text("Hello world"))))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.text("port = 8080\ntimeout = 30"))))
        XCTAssertFalse(plugin.info.canHandle(.empty))
    }
}
