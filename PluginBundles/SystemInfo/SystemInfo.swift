import AppKit
import Foundation
import IOKit
@testable import Pop

/// 这台 Mac 的基本情况：型号、芯片和核心数、内存、macOS 版本、开机多久、启动磁盘、显示器、序列号。
/// 都从 sysctl、IOKit、NSScreen 直接读，不用等 system_profiler。
enum SystemInfo {
    struct Display: Equatable {
        var name: String
        var builtIn: Bool
        /// 看起来像多大（点）
        var points: CGSize
        /// 实际渲染的像素
        var pixels: CGSize
        var refreshRate: Int?
    }

    struct Disk: Equatable {
        var name: String
        var total: Int64
        var available: Int64
    }

    struct Report: Equatable {
        /// 「MacBook Pro (14-inch, 2023)」；读不到具体型号时是「MacBook Pro」「Mac」
        var modelName: String
        /// 「Mac14,9」
        var modelIdentifier: String
        /// 「Apple M2 Pro」
        var chip: String
        var cores: Int
        var performanceCores: Int?
        var efficiencyCores: Int?
        var gpuCores: Int?
        /// 字节
        var memory: UInt64
        /// 「15.6.1」
        var osVersion: String
        /// 「24G90」
        var osBuild: String
        var bootTime: Date?
        var disk: Disk?
        var displays: [Display]
        var serial: String?
    }

    // MARK: - 读

    @MainActor
    static func read() -> Report {
        let identifier = sysctlString("hw.model") ?? ""
        let serial = platformString("IOPlatformSerialNumber")
        let name = cachedModelName(serial: serial) ?? productName() ?? family(of: identifier)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Report(modelName: name,
                      modelIdentifier: identifier,
                      chip: sysctlString("machdep.cpu.brand_string") ?? "",
                      cores: sysctlInt("hw.physicalcpu") ?? ProcessInfo.processInfo.processorCount,
                      performanceCores: (sysctlInt("hw.nperflevels") ?? 0) > 1 ? sysctlInt("hw.perflevel0.physicalcpu") : nil,
                      efficiencyCores: (sysctlInt("hw.nperflevels") ?? 0) > 1 ? sysctlInt("hw.perflevel1.physicalcpu") : nil,
                      gpuCores: gpuCores(),
                      memory: ProcessInfo.processInfo.physicalMemory,
                      osVersion: osVersionText(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion),
                      osBuild: sysctlString("kern.osversion") ?? "",
                      bootTime: bootTime(),
                      disk: startupDisk(),
                      displays: displays(),
                      serial: serial.flatMap { $0.isEmpty ? nil : $0 })
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = buffer.withUnsafeBufferPointer { pointer in pointer.baseAddress.map { String(cString: $0) } }
        return text?.trimmingCharacters(in: .whitespaces)
    }

    /// 整数：有的是 32 位、有的是 64 位，按返回的长度读
    static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return size == MemoryLayout<Int32>.size ? Int(Int32(truncatingIfNeeded: value)) : Int(value)
    }

    static func bootTime() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }

    /// IOPlatformExpertDevice 上的属性：序列号是字符串，Apple 芯片的 product-name 是带 \0 结尾的数据
    static func platformString(_ key: String) -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        if let text = value as? String {
            return text
        }
        if let data = value as? Data {
            return text(fromRegistryData: data)
        }
        return nil
    }

    /// Apple 芯片的 Mac 上 IORegistry 里写着的型号：「MacBook Pro (14-inch, 2023)」
    static func productName() -> String? {
        platformString("product-name").flatMap { $0.isEmpty ? nil : $0 }
    }

    /// 「MacBook Pro (14-inch, 2023)\0」→ 去掉结尾的 \0
    static func text(fromRegistryData data: Data) -> String? {
        let bytes = data.prefix { $0 != 0 }
        let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// 打开过「关于本机」后，系统把这台 Mac 的型号（按语言）记在 com.apple.SystemProfiler 的 CPU Names 里，
    /// key 是序列号的后四位加语言（「Q6LR-zh-Hans_CN」）。有界面语言的那份用它
    static func cachedModelName(serial: String?) -> String? {
        guard let names = UserDefaults(suiteName: "com.apple.SystemProfiler")?.dictionary(forKey: "CPU Names") as? [String: String] else { return nil }
        return pickModelName(names, serial: serial, language: Localization.locale.language.languageCode?.identifier ?? "en")
    }

    static func pickModelName(_ names: [String: String], serial: String?, language: String) -> String? {
        let suffix = serial.map { String($0.suffix(4)) }
        let mine = names.filter { key, value in !value.isEmpty && (suffix.map { key.hasPrefix($0 + "-") } ?? true) }
        guard !mine.isEmpty else { return nil }
        let sorted = mine.sorted { $0.key < $1.key }
        return (sorted.first { $0.key.dropFirst(5).hasPrefix(language) } ?? sorted.first)?.value
    }

    /// 型号标识里看得出的系列：「MacBookPro18,3」→「MacBook Pro」；新的「Mac14,9」看不出，就叫「Mac」
    static func family(of identifier: String) -> String {
        let families = [("MacBookPro", "MacBook Pro"), ("MacBookAir", "MacBook Air"), ("MacBook", "MacBook"), ("Macmini", "Mac mini"),
                        ("MacPro", "Mac Pro"), ("iMacPro", "iMac Pro"), ("iMac", "iMac")]
        // 「iMacPro」要排在「iMac」前面比
        for (prefix, name) in families.sorted(by: { $0.0.count > $1.0.count }) where identifier.hasPrefix(prefix) {
            return name
        }
        return "Mac"
    }

    /// 型号对应的图标
    static func symbol(for modelName: String) -> String {
        if modelName.contains("MacBook") { return "laptopcomputer" }
        if modelName.contains("mini") { return "macmini" }
        if modelName.contains("Studio") { return "macstudio" }
        if modelName.contains("Mac Pro") { return "macpro.gen3" }
        return "desktopcomputer"
    }

    /// Apple 芯片的 GPU 核心数（AGXAccelerator 的 gpu-core-count）；Intel 和虚拟机上没有
    static func gpuCores() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (value as? NSNumber)?.intValue
    }

    static func startupDisk() -> Disk? {
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys), let total = values.volumeTotalCapacity else { return nil }
        return Disk(name: values.volumeLocalizedName ?? "Macintosh HD", total: Int64(total),
                    available: values.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    @MainActor
    static func displays() -> [Display] {
        NSScreen.screens.map { screen in
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let scale = screen.backingScaleFactor
            let rate = screen.maximumFramesPerSecond
            return Display(name: screen.localizedName, builtIn: number != 0 && CGDisplayIsBuiltin(number) != 0,
                           points: screen.frame.size,
                           pixels: CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale),
                           refreshRate: rate > 0 ? rate : nil)
        }
    }

    // MARK: - 写法

    /// 「15.6.1」「26.0」
    static func osVersionText(major: Int, minor: Int, patch: Int) -> String {
        patch > 0 ? "\(major).\(minor).\(patch)" : "\(major).\(minor)"
    }

    /// 「macOS Sequoia 15.6.1」：认得的大版本写上名字
    static func osName(_ version: String) -> String {
        let names = [15: "Sequoia", 26: "Tahoe"]
        let major = Int(version.split(separator: ".").first ?? "") ?? 0
        return names[major].map { "macOS \($0) \(version)" } ?? "macOS \(version)"
    }

    /// 「10 核 CPU（6 性能核 + 4 能效核）」
    static func cpuText(cores: Int, performance: Int?, efficiency: Int?) -> String {
        let total = String(cores)
        guard let performance, let efficiency else { return String(localized: "\(total) 核 CPU") }
        let fast = String(performance)
        let slow = String(efficiency)
        return String(localized: "\(total) 核 CPU（\(fast) 性能核 + \(slow) 能效核）")
    }

    /// 「16 GB」：内存按 1024 算整数
    static func memoryText(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_073_741_824
        let rounded = gigabytes.rounded()
        return abs(gigabytes - rounded) < 0.05 ? "\(Int(rounded)) GB" : String(format: "%.1f GB", gigabytes)
    }

    /// 开机多久：「3 天 4 小时」「5 小时 12 分钟」「8 分钟」
    static func uptimeText(since boot: Date, now: Date = Date()) -> String {
        let minutes = max(Int(now.timeIntervalSince(boot) / 60), 0)
        let days = minutes / 1440
        let hours = minutes % 1440 / 60
        let rest = minutes % 60
        if days > 0 {
            return hours > 0 ? String(localized: "\(days) 天 \(hours) 小时") : String(localized: "\(days) 天")
        }
        if hours > 0 {
            return rest > 0 ? String(localized: "\(hours) 小时 \(rest) 分钟") : String(localized: "\(hours) 小时")
        }
        return String(localized: "\(max(rest, 1)) 分钟")
    }

    /// 「Macintosh HD · 可用 234 GB，共 494 GB」：容量按 1000 算，和访达一样
    static func diskText(_ disk: Disk) -> String {
        let available = ByteCountFormatter.string(fromByteCount: disk.available, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: disk.total, countStyle: .file)
        return String(localized: "\(disk.name) · 可用 \(available)，共 \(total)")
    }

    /// 「1512 × 982（像素 3024 × 1964）· 120 Hz」
    static func displayText(_ display: Display) -> String {
        let looks = "\(Int(display.points.width.rounded())) × \(Int(display.points.height.rounded()))"
        var text = looks
        if display.pixels != display.points {
            let pixels = "\(Int(display.pixels.width.rounded())) × \(Int(display.pixels.height.rounded()))"
            text += String(localized: "（像素 \(pixels)）")
        }
        if let rate = display.refreshRate {
            text += " · \(rate) Hz"
        }
        return text
    }
}
