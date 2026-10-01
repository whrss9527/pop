import Foundation
import IOKit
@testable import Pop

/// 连着的蓝牙设备的电量。妙控键盘、鼠标、触控板从 IOKit 的 AppleDeviceManagementHIDEventService 读，马上就有；
/// AirPods 这类耳机（左耳、右耳、充电盒分开）和其他设备从 system_profiler 的蓝牙信息里读，要一两秒。
/// 两边按蓝牙地址合在一起：名字用蓝牙信息里的（用户自己起的），键盘鼠标的电量用 IOKit 的（更新得快）。
enum DeviceBatteries {
    struct Device: Equatable, Identifiable {
        enum Kind: Int, Comparable {
            case keyboard, mouse, trackpad, headphones, other

            static func < (a: Kind, b: Kind) -> Bool {
                a.rawValue < b.rawValue
            }
        }

        /// 蓝牙地址（大写、去掉分隔符），用来把两边读到的合在一起；没有时为 nil
        var address: String?
        var name: String
        var kind: Kind
        /// 键盘、鼠标、头戴式耳机只有一个电量
        var main: Int?
        var left: Int?
        var right: Int?
        var caseLevel: Int?

        var id: String { address ?? name }

        /// 最低的电量：20% 以下标橙
        var lowest: Int? {
            [main, left, right, caseLevel].compactMap { $0 }.min()
        }

        var isLow: Bool {
            (lowest ?? 100) <= 20
        }

        var symbol: String {
            switch kind {
            case .keyboard: return "keyboard"
            case .mouse: return "magicmouse"
            case .trackpad: return "hand.point.up.left"
            case .headphones:
                if name.localizedCaseInsensitiveContains("AirPods Pro") { return "airpodspro" }
                if name.localizedCaseInsensitiveContains("AirPods Max") { return "airpodsmax" }
                if name.localizedCaseInsensitiveContains("AirPods") { return "airpods" }
                return "headphones"
            case .other: return "antenna.radiowaves.left.and.right"
            }
        }

        /// 「85%」「左耳 100% · 右耳 99% · 充电盒 50%」
        var levels: String {
            var parts: [String] = []
            if let main {
                parts.append("\(main)%")
            }
            if let left {
                let value = "\(left)%"
                parts.append(String(localized: "左耳 \(value)"))
            }
            if let right {
                let value = "\(right)%"
                parts.append(String(localized: "右耳 \(value)"))
            }
            if let caseLevel {
                let value = "\(caseLevel)%"
                parts.append(String(localized: "充电盒 \(value)"))
            }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: - IOKit（妙控键盘、鼠标、触控板）

    /// 读 IOKit 里报了电量的输入设备；读不了时为空
    static func hidDevices() -> [Device] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var found: [[String: Any]] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any] {
                found.append(dictionary)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return devices(fromHID: found)
    }

    /// 一个设备可能有好几个 HID 服务，按地址（没有地址时按名字）只留一个
    static func devices(fromHID services: [[String: Any]]) -> [Device] {
        var devices: [Device] = []
        for properties in services {
            guard let percent = BatteryReader.integer(properties["BatteryPercent"]), (0...100).contains(percent),
                  let product = (properties["Product"] as? String)?.trimmingCharacters(in: .whitespaces), !product.isEmpty else { continue }
            let address = (properties["DeviceAddress"] as? String).flatMap(normalizedAddress)
            let device = Device(address: address, name: product, kind: kind(ofName: product), main: percent)
            if !devices.contains(where: { $0.id == device.id }) {
                devices.append(device)
            }
        }
        return devices
    }

    // MARK: - system_profiler（耳机和其他蓝牙设备）

    /// 用 system_profiler 读连着的蓝牙设备；读不了时为 nil
    static func bluetoothDevices() async -> [Device]? {
        let result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/sbin/system_profiler"), arguments: ["SPBluetoothDataType", "-json"],
                                             stdin: nil, environment: [:], timeout: 10)
        guard case .success(let output) = result, output.status == 0, !output.timedOut else { return nil }
        return devices(fromBluetoothJSON: Data(output.stdout.utf8))
    }

    /// 从 system_profiler 的 JSON 里读：device_connected 里每一项是「名字: 属性」，电量写成「85%」
    static func devices(fromBluetoothJSON data: Data) -> [Device]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        var devices: [Device] = []
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let properties = value as? [String: Any] else { continue }
                    let device = Device(address: (properties["device_address"] as? String).flatMap(normalizedAddress),
                                        name: name,
                                        kind: kind(ofMinorType: properties["device_minorType"] as? String, name: name),
                                        main: level(properties["device_batteryLevelMain"]) ?? level(properties["device_batteryLevel"]),
                                        left: level(properties["device_batteryLevelLeft"]),
                                        right: level(properties["device_batteryLevelRight"]),
                                        caseLevel: level(properties["device_batteryLevelCase"]))
                    guard device.lowest != nil, !devices.contains(where: { $0.id == device.id }) else { continue }
                    devices.append(device)
                }
            }
        }
        return devices
    }

    /// 「85%」「85 %」→ 85
    static func level(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return (0...100).contains(number.intValue) ? number.intValue : nil
        }
        guard let text = value as? String else { return nil }
        let digits = text.filter(\.isNumber)
        guard let number = Int(digits), (0...100).contains(number) else { return nil }
        return number
    }

    // MARK: - 合在一起

    /// 按地址合并：蓝牙信息里有的用它的名字和类型，IOKit 读到的主电量更新得快，用 IOKit 的。按类型、名字排
    static func merge(hid: [Device], bluetooth: [Device]) -> [Device] {
        var merged = bluetooth
        for device in hid {
            if let address = device.address, let index = merged.firstIndex(where: { $0.address == address }) {
                merged[index].main = device.main
                if merged[index].kind == .other {
                    merged[index].kind = device.kind
                }
            } else if !merged.contains(where: { $0.id == device.id }) {
                merged.append(device)
            }
        }
        return merged.sorted {
            $0.kind != $1.kind ? $0.kind < $1.kind : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// 「f0-b3-ec-12-34-56」「F0:B3:EC:12:34:56」→「F0B3EC123456」
    static func normalizedAddress(_ address: String) -> String? {
        let hex = address.uppercased().filter(\.isHexDigit)
        return hex.count == 12 ? hex : nil
    }

    static func kind(ofName name: String) -> Device.Kind {
        let lowered = name.lowercased()
        if lowered.contains("keyboard") || name.contains("键盘") { return .keyboard }
        if lowered.contains("mouse") || name.contains("鼠标") { return .mouse }
        if lowered.contains("trackpad") || name.contains("触控板") { return .trackpad }
        if lowered.contains("airpods") || lowered.contains("beats") || lowered.contains("headphone") || name.contains("耳机") { return .headphones }
        return .other
    }

    static func kind(ofMinorType minorType: String?, name: String) -> Device.Kind {
        let type = (minorType ?? "").lowercased()
        if type.contains("keyboard") { return .keyboard }
        if type.contains("mouse") { return .mouse }
        if type.contains("trackpad") { return .trackpad }
        if type.contains("headphone") || type.contains("headset") || type.contains("speaker") { return .headphones }
        return kind(ofName: name)
    }
}
