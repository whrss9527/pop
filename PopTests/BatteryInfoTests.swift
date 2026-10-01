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
        let model = BatteryInfoModel(report: BatteryInfoPlugin.demoReport(), sources: .none)
        XCTAssertEqual(model.state, "正在充电")
        XCTAssertEqual(model.power, "43.1 W")
        XCTAssertEqual(model.remaining, "充满还要 0:38")
        XCTAssertEqual(model.rows.map { $0.label }, ["最大容量", "循环次数", "状况", "温度", "电压", "电源适配器"])
        XCTAssertEqual(model.rows.map { $0.value }, ["91%（现在 5530 mAh，出厂 6075 mAh）", "286 次（设计寿命 1000 次）", "正常", "31.2 ℃", "12.61 V",
                                                 "96 W · 96W USB-C Power Adapter"])
        XCTAssertTrue(model.text.hasPrefix("电量 76%，正在充电\n最大容量：91%"))
        // 读不到时保留上一次的
        model.refresh()
        XCTAssertEqual(model.report?.percent, 76)

        var unplugged = BatteryInfoPlugin.demoReport()
        unplugged.isCharging = false
        unplugged.externalConnected = false
        unplugged.minutesToEmpty = 312
        unplugged.amperage = -0.7
        unplugged.fullCapacity = 4500
        unplugged.condition = "Service Recommended"
        let battery = BatteryInfoModel(report: unplugged, sources: .none)
        XCTAssertEqual(battery.state, "用电池")
        XCTAssertEqual(battery.remaining, "还能用 5:12")
        XCTAssertEqual(battery.rows.map { $0.label }, ["最大容量", "循环次数", "状况", "温度", "电压"])
        XCTAssertEqual(battery.rows.filter { $0.warning }.map { $0.label }, ["最大容量", "状况"])
        var paused = BatteryInfoPlugin.demoReport()
        paused.isCharging = false
        XCTAssertEqual(BatteryInfoModel(report: paused, sources: .none).state, "接着电源，暂停充电")
    }

    func testReadsBluetoothDevices() throws {
        // IOKit：同一个键盘有两个 HID 服务，只留一个；没报电量的不要
        let hid = DeviceBatteries.devices(fromHID: [
            ["Product": "Magic Keyboard with Touch ID", "BatteryPercent": 84, "DeviceAddress": "f0-b3-ec-12-34-56"],
            ["Product": "Magic Keyboard with Touch ID", "BatteryPercent": 84, "DeviceAddress": "f0-b3-ec-12-34-56"],
            ["Product": "Magic Mouse", "BatteryPercent": 18],
            ["Product": "USB Receiver"],
        ])
        XCTAssertEqual(hid.map(\.name), ["Magic Keyboard with Touch ID", "Magic Mouse"])
        XCTAssertEqual(hid.map(\.kind), [.keyboard, .mouse])
        XCTAssertEqual(hid[0].address, "F0B3EC123456")

        // system_profiler：只看连着的、报了电量的
        let json = #"""
        {"SPBluetoothDataType": [{
          "controller_properties": {"controller_state": "attrib_on"},
          "device_connected": [
            {"AirPods Pro": {"device_address": "AA:BB:CC:DD:EE:01", "device_batteryLevelCase": "50%", "device_batteryLevelLeft": "100%",
                             "device_batteryLevelRight": "99%", "device_minorType": "Headphones"}},
            {"张三的妙控键盘": {"device_address": "F0:B3:EC:12:34:56", "device_batteryLevelMain": "85%", "device_minorType": "Keyboard"}},
            {"音箱": {"device_address": "AA:BB:CC:DD:EE:02", "device_minorType": "Speaker"}}
          ],
          "device_not_connected": [
            {"旧耳机": {"device_address": "AA:BB:CC:DD:EE:03", "device_batteryLevelMain": "40%", "device_minorType": "Headphones"}}
          ]
        }]}
        """#
        let bluetooth = try XCTUnwrap(DeviceBatteries.devices(fromBluetoothJSON: Data(json.utf8)))
        XCTAssertEqual(Set(bluetooth.map(\.name)), ["AirPods Pro", "张三的妙控键盘"])
        XCTAssertNil(DeviceBatteries.devices(fromBluetoothJSON: Data("不是 JSON".utf8)))

        // 合在一起：键盘用蓝牙里的名字、IOKit 的电量，鼠标只有 IOKit 有；按键盘、鼠标、耳机排
        let merged = DeviceBatteries.merge(hid: hid, bluetooth: bluetooth)
        XCTAssertEqual(merged.map(\.name), ["张三的妙控键盘", "Magic Mouse", "AirPods Pro"])
        XCTAssertEqual(merged.map(\.levels), ["84%", "18%", "左耳 100% · 右耳 99% · 充电盒 50%"])
        XCTAssertEqual(merged.map(\.isLow), [false, true, false])
        XCTAssertEqual(merged.map(\.symbol), ["keyboard", "magicmouse", "airpodspro"])

        XCTAssertEqual(DeviceBatteries.level("85%"), 85)
        XCTAssertEqual(DeviceBatteries.level(NSNumber(value: 40)), 40)
        XCTAssertNil(DeviceBatteries.level("150%"))
        XCTAssertNil(DeviceBatteries.level("满"))
        XCTAssertNil(DeviceBatteries.normalizedAddress("12:34"))
        XCTAssertEqual(DeviceBatteries.kind(ofMinorType: nil, name: "Beats Studio Buds"), .headphones)
        XCTAssertEqual(DeviceBatteries.kind(ofMinorType: "Trackpad", name: "触控板"), .trackpad)
    }

    @MainActor
    func testCardWithDevices() {
        // 台式 Mac：没有电池，只列设备
        let desktop = BatteryInfoModel(report: nil, bluetooth: BatteryInfoPlugin.demoDevices(), sources: .none)
        XCTAssertEqual(desktop.state, "")
        XCTAssertTrue(desktop.rows.isEmpty)
        XCTAssertNil(desktop.power)
        XCTAssertEqual(desktop.text, "妙控键盘：85%\n妙控鼠标：18%\nAirPods Pro：左耳 100% · 右耳 99% · 充电盒 50%")
        // 笔记本：电池在前，设备在后；读不到设备时保留上一次的
        let laptop = BatteryInfoModel(report: BatteryInfoPlugin.demoReport(), bluetooth: BatteryInfoPlugin.demoDevices(), sources: .none)
        laptop.refresh()
        XCTAssertEqual(laptop.devices.count, 3)
        XCTAssertTrue(laptop.text.hasPrefix("电量 76%，正在充电\n"))
        XCTAssertTrue(laptop.text.hasSuffix("\nAirPods Pro：左耳 100% · 右耳 99% · 充电盒 50%"))
        // 键盘、鼠标换了电量
        var hidCalls = 0
        let live = BatteryInfoModel(report: nil, bluetooth: BatteryInfoPlugin.demoDevices(),
                                    sources: BatteryInfoModel.Sources(battery: { nil }, hid: {
                                        hidCalls += 1
                                        return [DeviceBatteries.Device(address: "F0B3EC000002", name: "Magic Mouse", kind: .mouse, main: 17)]
                                    }, bluetooth: { nil }))
        live.refresh()
        XCTAssertEqual(hidCalls, 1)
        XCTAssertEqual(live.devices.map(\.name), ["妙控键盘", "妙控鼠标", "AirPods Pro"])
        XCTAssertEqual(live.devices[1].main, 17)
    }

    func testPluginNeedsNoSelection() {
        XCTAssertTrue(BatteryInfoPlugin().info.canHandle(.empty))
    }
}
