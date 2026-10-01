import XCTest
@testable import Pop

final class BatteryInfoTests: XCTestCase {
    /// Apple 芯片的 MacBook：CurrentCapacity、MaxCapacity 是百分比，电流按无符号存
    private let appleSilicon: [String: Any] = [
        "BatteryInstalled": true, "CurrentCapacity": 76, "MaxCapacity": 100, "AppleRawCurrentCapacity": 4210, "AppleRawMaxCapacity": 5540,
        "NominalChargeCapacity": 5530, "DesignCapacity": 6075, "CycleCount": 286, "DesignCycleCount9C": 1000, "Temperature": 3120,
        "Voltage": 12610, "InstantAmperage": NSNumber(value: UInt64(3420)), "IsCharging": true, "ExternalConnected": true, "FullyCharged": false,
        "AvgTimeToFull": 38, "AvgTimeToEmpty": 65535, "AdapterDetails": ["Watts": 96, "Name": "96W USB-C Power Adapter"] as [String: Any],
    ]

    func testReadsAppleSiliconBatteries() throws {
        let report = try XCTUnwrap(BatteryReader.report(from: appleSilicon, condition: nil))
        XCTAssertEqual(report.percent, 76)
        XCTAssertEqual(report.health, 91)
        XCTAssertEqual(report.cycleCount, 286)
        XCTAssertEqual(report.designCycles, 1000)
        XCTAssertEqual(try XCTUnwrap(report.temperature), 31.2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(report.watts), 12.61 * 3.42, accuracy: 0.001)
        XCTAssertEqual(report.minutesToFull, 38)
        XCTAssertNil(report.minutesToEmpty)
        XCTAssertEqual(report.adapterWatts, 96)
        XCTAssertFalse(report.needsService)
    }

    func testReadsIntelBatteriesAndNegativeCurrents() throws {
        // Intel：容量直接是毫安时；用电池时电流是负的（按无符号存成很大的数）
        let intel: [String: Any] = [
            "CurrentCapacity": 2600, "MaxCapacity": 5200, "DesignCapacity": 6600, "CycleCount": 812, "Temperature": 2950, "Voltage": 11400,
            "Amperage": NSNumber(value: UInt64(bitPattern: -1200)), "IsCharging": false, "ExternalConnected": false, "FullyCharged": false,
            "AvgTimeToEmpty": 125, "AvgTimeToFull": 65535,
        ]
        let report = try XCTUnwrap(BatteryReader.report(from: intel, condition: "Service Recommended"))
        XCTAssertEqual(report.percent, 50)
        XCTAssertEqual(report.fullCapacity, 5200)
        XCTAssertEqual(report.health, 79)
        XCTAssertEqual(try XCTUnwrap(report.amperage), -1.2, accuracy: 0.0001)
        XCTAssertLessThan(try XCTUnwrap(report.watts), 0)
        XCTAssertEqual(report.minutesToEmpty, 125)
        XCTAssertNil(report.minutesToFull)
        XCTAssertNil(report.designCycles)
        XCTAssertTrue(report.needsService)
        // 没有电池
        XCTAssertNil(BatteryReader.report(from: ["BatteryInstalled": false, "CurrentCapacity": 0, "MaxCapacity": 100], condition: nil))
        XCTAssertNil(BatteryReader.report(from: [:], condition: nil))
        XCTAssertEqual(BatteryReader.integer(NSNumber(value: -5)), -5)
        XCTAssertNil(BatteryReader.integer("12"))
        XCTAssertEqual(BatteryReader.duration(minutes: 65), "1:05")
        // CI 的机器没有电池，读出来是 nil；有电池的 Mac 上读得出电量
        if let real = BatteryReader.read() {
            XCTAssertTrue((0...100).contains(real.percent))
        }
    }

    @MainActor
    func testCardRows() throws {
        let model = BatteryInfoModel(report: BatteryInfoPlugin.demoReport(), read: { nil })
        XCTAssertEqual(model.state, "正在充电")
        XCTAssertEqual(model.power, "43.1 W")
        XCTAssertEqual(model.remaining, "充满还要 0:38")
        XCTAssertEqual(model.rows.map { $0.label }, ["最大容量", "循环次数", "状况", "温度", "电压", "电源适配器"])
        XCTAssertEqual(model.rows.map { $0.value }, ["91%（现在 5530 mAh，出厂 6075 mAh）", "286 次（设计寿命 1000 次）", "正常", "31.2 ℃", "12.61 V",
                                                 "96 W · 96W USB-C Power Adapter"])
        XCTAssertTrue(model.text.hasPrefix("电量 76%，正在充电\n最大容量：91%"))
        // 读不到时保留上一次的
        model.refresh()
        XCTAssertEqual(model.report.percent, 76)

        var unplugged = BatteryInfoPlugin.demoReport()
        unplugged.isCharging = false
        unplugged.externalConnected = false
        unplugged.minutesToEmpty = 312
        unplugged.amperage = -0.7
        unplugged.fullCapacity = 4500
        unplugged.condition = "Service Recommended"
        let battery = BatteryInfoModel(report: unplugged, read: { nil })
        XCTAssertEqual(battery.state, "用电池")
        XCTAssertEqual(battery.remaining, "还能用 5:12")
        XCTAssertEqual(battery.rows.map { $0.label }, ["最大容量", "循环次数", "状况", "温度", "电压"])
        XCTAssertEqual(battery.rows.filter { $0.warning }.map { $0.label }, ["最大容量", "状况"])
        var paused = BatteryInfoPlugin.demoReport()
        paused.isCharging = false
        XCTAssertEqual(BatteryInfoModel(report: paused, read: { nil }).state, "接着电源，暂停充电")
    }

    func testPluginNeedsNoSelection() {
        XCTAssertTrue(BatteryInfoPlugin().info.canHandle(.empty))
    }
}
