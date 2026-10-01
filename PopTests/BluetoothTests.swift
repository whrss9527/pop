import XCTest
@testable import Pop

/// 测试用的蓝牙：连接要等测试里手动回调
@MainActor
private final class FakeBluetooth: BluetoothBackend {
    var list: [BluetoothDevices.Device]
    var isDenied = false
    var disconnectWorks = true
    var pending: [String: @MainActor (Bool) -> Void] = [:]
    var connectCalls = 0

    init(_ list: [BluetoothDevices.Device]) {
        self.list = list
    }

    func devices() -> [BluetoothDevices.Device] {
        list
    }

    func connect(_ id: String, completion: @escaping @MainActor (Bool) -> Void) {
        connectCalls += 1
        pending[id] = completion
    }

    func disconnect(_ id: String) -> Bool {
        guard disconnectWorks, let index = list.firstIndex(where: { $0.id == id }) else { return false }
        list[index].isConnected = false
        return true
    }

    func finish(_ id: String, connected: Bool) {
        if connected, let index = list.firstIndex(where: { $0.id == id }) {
            list[index].isConnected = true
        }
        pending.removeValue(forKey: id)?(connected)
    }
}

@MainActor
final class BluetoothTests: XCTestCase {
    private func device(_ id: String, _ name: String, _ kind: BluetoothDevices.Kind, connected: Bool, battery: Int? = nil) -> BluetoothDevices.Device {
        BluetoothDevices.Device(id: id, name: name, kind: kind, isConnected: connected, battery: battery)
    }

    func testKindFromNameAndClass() {
        func kind(_ major: UInt32, _ minor: UInt32, _ name: String = "Device") -> BluetoothDevices.Kind {
            BluetoothDevices.kind(major: major, minor: minor, name: name)
        }
        // 名字里写着的最准
        XCTAssertEqual(kind(0x04, 0x06, "小明的 AirPods Pro"), .airpods)
        XCTAssertEqual(kind(0x05, 0x20, "Magic Trackpad"), .trackpad)
        XCTAssertEqual(kind(0x05, 0x20, "Magic Mouse"), .mouse)
        XCTAssertEqual(kind(0x05, 0x10, "Magic Keyboard with Touch ID"), .keyboard)
        XCTAssertEqual(kind(0x05, 0x02, "Xbox Wireless Controller"), .gamepad)
        // 按设备类别
        XCTAssertEqual(kind(0x04, 0x06), .headphones)
        XCTAssertEqual(kind(0x04, 0x01), .headphones)
        XCTAssertEqual(kind(0x04, 0x05), .speaker)
        XCTAssertEqual(kind(0x04, 0x07), .speaker)
        XCTAssertEqual(kind(0x05, 0x10), .keyboard)
        XCTAssertEqual(kind(0x05, 0x20), .mouse)
        XCTAssertEqual(kind(0x05, 0x30), .keyboard)
        XCTAssertEqual(kind(0x05, 0x02), .gamepad)
        XCTAssertEqual(kind(0x05, 0x00), .other)
        XCTAssertEqual(kind(0x02, 0x03), .phone)
        XCTAssertEqual(kind(0x01, 0x03), .computer)
        XCTAssertEqual(kind(0x1F, 0x00), .other)
        XCTAssertFalse(BluetoothDevices.Kind.trackpad.symbol.isEmpty)
    }

    func testAddressesAndSorting() {
        XCTAssertEqual(BluetoothDevices.normalizedAddress(" A4:C6:F0:11:22:33 "), "a4-c6-f0-11-22-33")
        XCTAssertEqual(BluetoothDevices.normalizedAddress("a4-c6-f0-11-22-33"), "a4-c6-f0-11-22-33")
        let sorted = BluetoothDevices.sorted([
            device("1", "WH-1000XM5", .headphones, connected: false),
            device("2", "Magic Keyboard", .keyboard, connected: true),
            device("3", "AirPods Pro", .airpods, connected: true),
            device("4", "Magic Trackpad", .trackpad, connected: false),
        ])
        XCTAssertEqual(sorted.map(\.name), ["AirPods Pro", "Magic Keyboard", "Magic Trackpad", "WH-1000XM5"])
    }

    func testBatteriesFromHIDServices() {
        let batteries = BluetoothDevices.batteries(fromHID: [
            ["DeviceAddress": "F0:B3:EC:44:55:66", "BatteryPercent": NSNumber(value: 72), "Product": "Magic Keyboard"],
            ["BatteryPercent": NSNumber(value: 50), "Product": "没有地址"],
            ["DeviceAddress": "f0-b3-ec-77-88-99", "BatteryPercent": NSNumber(value: 150)],
            ["DeviceAddress": "f0-b3-ec-77-88-aa"],
        ])
        XCTAssertEqual(batteries, ["f0-b3-ec-44-55-66": 72])
        // 读这台 Mac 的不出错
        _ = BluetoothDevices.hidBatteries()
    }

    func testConnectAndDisconnect() throws {
        let fake = FakeBluetooth([
            device("a", "WH-1000XM5", .headphones, connected: false),
            device("b", "Magic Keyboard", .keyboard, connected: true, battery: 72),
            device("c", "AirPods Pro", .airpods, connected: true),
        ])
        let model = BluetoothModel(backend: fake)
        XCTAssertEqual(model.devices.map(\.name), ["AirPods Pro", "Magic Keyboard", "WH-1000XM5"])
        XCTAssertEqual(model.devices.map { model.status(of: $0) }, ["已连接", "已连接 · 电量 72%", "未连接"])

        // 连接：转圈，连上以后跟着变
        let headphones = model.devices[2]
        model.toggle(headphones)
        XCTAssertTrue(model.connecting.contains("a"))
        XCTAssertEqual(model.status(of: headphones), "正在连接…")
        // 正在连的时候再点不重复连
        model.toggle(headphones)
        XCTAssertEqual(fake.connectCalls, 1)
        fake.finish("a", connected: true)
        XCTAssertTrue(model.connecting.isEmpty)
        XCTAssertNil(model.message)
        XCTAssertEqual(model.devices.filter(\.isConnected).count, 3)

        // 连不上：说一句
        fake.list[0].isConnected = false
        model.refresh()
        model.toggle(try XCTUnwrap(model.devices.first { $0.id == "a" }))
        fake.finish("a", connected: false)
        XCTAssertEqual(model.message, "连不上「WH-1000XM5」：确认它开着、在附近，没有连着别的设备")

        // 断开
        model.toggle(try XCTUnwrap(model.devices.first { $0.id == "b" }))
        XCTAssertNil(model.message)
        XCTAssertFalse(try XCTUnwrap(model.devices.first { $0.id == "b" }).isConnected)
        fake.disconnectWorks = false
        model.toggle(try XCTUnwrap(model.devices.first { $0.id == "c" }))
        XCTAssertEqual(model.message, "断不开「AirPods Pro」")
    }

    func testDeniedPermission() {
        let fake = FakeBluetooth([device("a", "AirPods Pro", .airpods, connected: true)])
        fake.isDenied = true
        let model = BluetoothModel(backend: fake)
        XCTAssertTrue(model.isDenied)
        XCTAssertTrue(model.devices.isEmpty)
        fake.isDenied = false
        model.refresh()
        XCTAssertFalse(model.isDenied)
        XCTAssertEqual(model.devices.count, 1)
    }

    func testDemoDevices() {
        let demo = DemoBluetooth()
        let model = BluetoothModel(backend: demo)
        XCTAssertEqual(model.devices.map(\.name), ["AirPods Pro", "Magic Keyboard", "Magic Trackpad", "WH-1000XM5"])
        XCTAssertTrue(demo.disconnect("f0-b3-ec-44-55-66"))
        model.refresh()
        XCTAssertEqual(model.devices.filter(\.isConnected).map(\.name), ["AirPods Pro"])
        XCTAssertTrue(BluetoothPlugin().info.canHandle(.empty))
        XCTAssertNotNil(BluetoothPlugin.settingsURL)
        XCTAssertNotNil(BluetoothPlugin.privacyURL)
    }
}
