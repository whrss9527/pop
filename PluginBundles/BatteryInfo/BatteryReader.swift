import Foundation
import IOKit
import IOKit.ps
@testable import Pop

/// 电池信息：从 IOKit 的 AppleSmartBattery 读电量、最大容量、循环次数、温度、电压电流和充电器，
/// 再从电源信息里读系统给的电池状况（「建议维修」）。没有电池的 Mac 读出来是 nil。
enum BatteryReader {
    struct Report: Equatable {
        /// 电量（%）
        var percent: Int
        var isCharging: Bool
        /// 接着电源
        var externalConnected: Bool
        var fullyCharged: Bool
        var cycleCount: Int?
        /// 设计寿命（循环次数）
        var designCycles: Int?
        /// 出厂时的容量和现在充满能有多少（毫安时）
        var designCapacity: Int?
        var fullCapacity: Int?
        /// 摄氏度
        var temperature: Double?
        /// 伏
        var voltage: Double?
        /// 安，充电时是正的，用电池时是负的
        var amperage: Double?
        var minutesToFull: Int?
        var minutesToEmpty: Int?
        var adapterWatts: Int?
        var adapterName: String?
        /// 系统给的状况：Service Recommended 之类；正常时为 nil
        var condition: String?

        /// 最大容量：现在充满能有出厂时的百分之几
        var health: Int? {
            guard let designCapacity, let fullCapacity, designCapacity > 0 else { return nil }
            return Int((Double(fullCapacity) / Double(designCapacity) * 100).rounded())
        }

        /// 正在进出电池的功率（瓦）：充电时是正的
        var watts: Double? {
            guard let voltage, let amperage else { return nil }
            return voltage * amperage
        }

        var needsService: Bool {
            condition != nil
        }
    }

    /// 读这台 Mac 的电池；没有电池时为 nil
    static func read() -> Report? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        return report(from: dictionary, condition: condition())
    }

    /// 电源信息里电池的状况：正常时为 nil
    static func condition() -> String? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            if let condition = description["BatteryHealthCondition"] as? String, !condition.isEmpty {
                return condition
            }
            if let health = description[kIOPSBatteryHealthKey] as? String, health != kIOPSGoodValue {
                return health
            }
        }
        return nil
    }

    /// 从 AppleSmartBattery 的属性里读出来。Apple 芯片的 Mac 上 CurrentCapacity、MaxCapacity 是百分比，
    /// 毫安时在 AppleRawCurrentCapacity、AppleRawMaxCapacity、NominalChargeCapacity 里；Intel 的直接是毫安时
    static func report(from properties: [String: Any], condition: String?) -> Report? {
        guard properties["BatteryInstalled"] as? Bool != false,
              let current = integer(properties["CurrentCapacity"]), let maximum = integer(properties["MaxCapacity"]), maximum > 0 else { return nil }
        let percent = maximum == 100 ? current : Int((Double(current) / Double(maximum) * 100).rounded())
        let full = integer(properties["NominalChargeCapacity"]) ?? integer(properties["AppleRawMaxCapacity"]) ?? (maximum > 100 ? maximum : nil)
        let adapter = properties["AdapterDetails"] as? [String: Any]
        let minutes: (String) -> Int? = { key in
            // 65535 表示还在算
            guard let value = integer(properties[key]), value > 0, value < 65535 else { return nil }
            return value
        }
        let amperage = integer(properties["InstantAmperage"]) ?? integer(properties["Amperage"])
        let adapterName = (adapter?["Name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Report(percent: min(max(percent, 0), 100),
                      isCharging: properties["IsCharging"] as? Bool ?? false,
                      externalConnected: properties["ExternalConnected"] as? Bool ?? false,
                      fullyCharged: properties["FullyCharged"] as? Bool ?? false,
                      cycleCount: integer(properties["CycleCount"]),
                      designCycles: integer(properties["DesignCycleCount9C"]) ?? integer(properties["DesignCycleCount"]),
                      designCapacity: integer(properties["DesignCapacity"]),
                      fullCapacity: full,
                      temperature: integer(properties["Temperature"]).map { Double($0) / 100 },
                      voltage: integer(properties["Voltage"]).map { Double($0) / 1000 },
                      amperage: amperage.map { Double($0) / 1000 },
                      minutesToFull: minutes("AvgTimeToFull"),
                      minutesToEmpty: minutes("AvgTimeToEmpty") ?? minutes("TimeRemaining"),
                      adapterWatts: integer(adapter?["Watts"]).flatMap { $0 > 0 ? $0 : nil },
                      adapterName: adapterName,
                      condition: condition)
    }

    /// 数字：有的属性（比如电流）是按无符号存的负数，转回有符号
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let unsigned = number.uint64Value
        if unsigned > UInt64(Int64.max) {
            return Int(Int64(bitPattern: unsigned))
        }
        return number.intValue
    }

    /// 「1:05」「0:45」（小时:分）
    static func duration(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
