import Foundation
import IOKit
@testable import Pop

/// 蓝牙设备：配对过的设备是什么（耳机、键盘……）、地址怎么写、输入设备的电量。纯逻辑的部分，方便测试
enum BluetoothDevices {
    enum Kind: Equatable {
        case airpods, headphones, speaker, keyboard, mouse, trackpad, gamepad, phone, computer, other

        var symbol: String {
            switch self {
            case .airpods: return "airpodspro"
            case .headphones: return "headphones"
            case .speaker: return "hifispeaker"
            case .keyboard: return "keyboard"
            case .mouse: return "computermouse"
            case .trackpad: return "rectangle.and.hand.point.up.left"
            case .gamepad: return "gamecontroller"
            case .phone: return "iphone"
            case .computer: return "laptopcomputer"
            case .other: return "dot.radiowaves.left.and.right"
            }
        }
    }

    struct Device: Identifiable, Equatable {
        /// 蓝牙地址（小写、用「-」连起来），也当 id
        let id: String
        let name: String
        let kind: Kind
        var isConnected: Bool
        /// 输入设备报的电量（0～100）；读不到时为 nil
        var battery: Int?
    }

    /// 按名字和蓝牙的设备类别（Class of Device 里的主类、次类）认是什么设备：名字里写着的最准
    static func kind(major: UInt32, minor: UInt32, name: String) -> Kind {
        let lower = name.lowercased()
        if lower.contains("airpods") {
            return .airpods
        }
        if lower.contains("trackpad") || lower.contains("触控板") {
            return .trackpad
        }
        if lower.contains("mouse") || lower.contains("鼠标") {
            return .mouse
        }
        if lower.contains("keyboard") || lower.contains("键盘") {
            return .keyboard
        }
        if lower.contains("controller") || lower.contains("手柄") {
            return .gamepad
        }
        switch major {
        case 0x01:
            return .computer
        case 0x02:
            return .phone
        case 0x04:
            // 音频：0x05 扬声器、0x07 便携音箱，其他（耳机、免提）都算耳机
            return minor == 0x05 || minor == 0x07 ? .speaker : .headphones
        case 0x05:
            // 外设：高两位是键盘（01）、指针（10）、两个都有（11），低四位里 1、2 是摇杆、手柄
            let pointing = minor & 0x20 != 0
            let keyboard = minor & 0x10 != 0
            if keyboard {
                return .keyboard
            }
            if pointing {
                return .mouse
            }
            return [0x01, 0x02].contains(minor & 0x0F) ? .gamepad : .other
        default:
            return .other
        }
    }

    /// 地址统一成小写、用「-」连：IOBluetooth 给「aa-bb-cc-…」，IOKit 有时给「AA:BB:CC:…」
    static func normalizedAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ":", with: "-")
    }

    /// 连着的放前面，再按名字排
    static func sorted(_ devices: [Device]) -> [Device] {
        devices.sorted { a, b in
            if a.isConnected != b.isConnected {
                return a.isConnected
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - 电量

    /// 妙控键盘、鼠标、触控板这类输入设备在 IOKit 里报的电量，按地址
    static func hidBatteries() -> [String: Int] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else {
            return [:]
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
        return batteries(fromHID: found)
    }

    static func batteries(fromHID services: [[String: Any]]) -> [String: Int] {
        var result: [String: Int] = [:]
        for properties in services {
            guard let address = properties["DeviceAddress"] as? String, !address.isEmpty,
                  let percent = (properties["BatteryPercent"] as? NSNumber)?.intValue, (0...100).contains(percent) else { continue }
            result[normalizedAddress(address)] = percent
        }
        return result
    }
}
