import XCTest
@testable import Pop

final class SystemInfoTests: XCTestCase {
    @MainActor
    func testReadsThisMac() {
        let report = SystemInfo.read()
        XCTAssertFalse(report.modelIdentifier.isEmpty)
        XCTAssertFalse(report.modelName.isEmpty)
        XCTAssertGreaterThan(report.cores, 0)
        XCTAssertGreaterThan(report.memory, 0)
        XCTAssertFalse(report.osBuild.isEmpty)
        XCTAssertTrue(report.osVersion.hasPrefix("\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)."))
        XCTAssertGreaterThan(report.disk?.total ?? 0, 0)
        XCTAssertLessThan(report.bootTime ?? .distantPast, Date())
        XCTAssertGreaterThan(report.bootTime ?? .distantPast, Date(timeIntervalSince1970: 0))
    }

    func testFormatting() throws {
        XCTAssertEqual(SystemInfo.osName("15.6.1"), "macOS Sequoia 15.6.1")
        XCTAssertEqual(SystemInfo.osName("26.0"), "macOS Tahoe 26.0")
        XCTAssertEqual(SystemInfo.osName("27.1"), "macOS 27.1")
        XCTAssertEqual(SystemInfo.osVersionText(major: 15, minor: 6, patch: 1), "15.6.1")
        XCTAssertEqual(SystemInfo.osVersionText(major: 26, minor: 0, patch: 0), "26.0")
        XCTAssertEqual(SystemInfo.cpuText(cores: 10, performance: 6, efficiency: 4), "10 核 CPU（6 性能核 + 4 能效核）")
        XCTAssertEqual(SystemInfo.cpuText(cores: 8, performance: nil, efficiency: nil), "8 核 CPU")
        XCTAssertEqual(SystemInfo.memoryText(16 * 1_073_741_824), "16 GB")
        XCTAssertEqual(SystemInfo.memoryText(1_610_612_736), "1.5 GB")

        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(SystemInfo.uptimeText(since: now.addingTimeInterval(-(3 * 86_400 + 4 * 3_600 + 12 * 60)), now: now), "3 天 4 小时")
        XCTAssertEqual(SystemInfo.uptimeText(since: now.addingTimeInterval(-2 * 86_400), now: now), "2 天")
        XCTAssertEqual(SystemInfo.uptimeText(since: now.addingTimeInterval(-(5 * 3_600 + 12 * 60)), now: now), "5 小时 12 分钟")
        XCTAssertEqual(SystemInfo.uptimeText(since: now.addingTimeInterval(-3 * 3_600), now: now), "3 小时")
        XCTAssertEqual(SystemInfo.uptimeText(since: now.addingTimeInterval(-30), now: now), "1 分钟")

        let disk = SystemInfo.diskText(SystemInfo.Disk(name: "Macintosh HD", total: 494_384_795_648, available: 233_876_123_648))
        XCTAssertTrue(disk.hasPrefix("Macintosh HD · 可用 "), disk)
        XCTAssertTrue(disk.contains("，共 "), disk)

        let builtIn = SystemInfo.Display(name: "内建视网膜显示器", builtIn: true, points: CGSize(width: 1512, height: 982),
                                         pixels: CGSize(width: 3024, height: 1964), refreshRate: 120)
        XCTAssertEqual(SystemInfo.displayText(builtIn), "1512 × 982（像素 3024 × 1964） · 120 Hz")
        let plain = SystemInfo.Display(name: "HDMI", builtIn: false, points: CGSize(width: 1920, height: 1080),
                                       pixels: CGSize(width: 1920, height: 1080), refreshRate: nil)
        XCTAssertEqual(SystemInfo.displayText(plain), "1920 × 1080")
    }

    func testModelNames() {
        XCTAssertEqual(SystemInfo.family(of: "MacBookPro18,3"), "MacBook Pro")
        XCTAssertEqual(SystemInfo.family(of: "MacBookAir10,1"), "MacBook Air")
        XCTAssertEqual(SystemInfo.family(of: "MacBook10,1"), "MacBook")
        XCTAssertEqual(SystemInfo.family(of: "Macmini9,1"), "Mac mini")
        XCTAssertEqual(SystemInfo.family(of: "iMacPro1,1"), "iMac Pro")
        XCTAssertEqual(SystemInfo.family(of: "iMac21,1"), "iMac")
        XCTAssertEqual(SystemInfo.family(of: "MacPro7,1"), "Mac Pro")
        XCTAssertEqual(SystemInfo.family(of: "Mac14,9"), "Mac")
        XCTAssertEqual(SystemInfo.family(of: "VirtualMac2,1"), "Mac")

        XCTAssertEqual(SystemInfo.symbol(for: "MacBook Pro (14-inch, 2023)"), "laptopcomputer")
        XCTAssertEqual(SystemInfo.symbol(for: "Mac mini (2023)"), "macmini")
        XCTAssertEqual(SystemInfo.symbol(for: "Mac Studio (2023)"), "macstudio")
        XCTAssertEqual(SystemInfo.symbol(for: "Mac Pro (2023)"), "macpro.gen3")
        XCTAssertEqual(SystemInfo.symbol(for: "iMac (24-inch, 2023)"), "desktopcomputer")

        // IORegistry 里的 product-name 带 \0 结尾
        XCTAssertEqual(SystemInfo.text(fromRegistryData: Data("MacBook Pro (14-inch, 2023)\0".utf8)), "MacBook Pro (14-inch, 2023)")
        XCTAssertNil(SystemInfo.text(fromRegistryData: Data([0])))

        // 「关于本机」记下的型号：按序列号后四位和界面语言挑
        let names = ["Q6LR-zh-Hans_CN": "MacBook Pro（14 英寸，2023 年）", "Q6LR-en-US_US": "MacBook Pro (14-inch, 2023)", "ZZZZ-en-US_US": "iMac"]
        XCTAssertEqual(SystemInfo.pickModelName(names, serial: "C02XQ6LR", language: "zh"), "MacBook Pro（14 英寸，2023 年）")
        XCTAssertEqual(SystemInfo.pickModelName(names, serial: "C02XQ6LR", language: "en"), "MacBook Pro (14-inch, 2023)")
        XCTAssertEqual(SystemInfo.pickModelName(names, serial: "C02XQ6LR", language: "fr"), "MacBook Pro (14-inch, 2023)")
        XCTAssertNil(SystemInfo.pickModelName(names, serial: "C02X0000", language: "zh"))
        XCTAssertEqual(SystemInfo.pickModelName(["ZZZZ-en-US_US": "iMac"], serial: nil, language: "zh"), "iMac")
    }

    @MainActor
    func testCardRowsAndCopiedText() {
        let model = SystemInfoModel(report: SystemInfoPlugin.demoReport(), now: { SystemInfoPlugin.demoNow })
        XCTAssertEqual(model.symbol, "laptopcomputer")
        XCTAssertEqual(model.osText, "macOS Sequoia 15.6.1（24G90）")
        XCTAssertEqual(model.rows.map { $0.label }, ["型号标识", "芯片型号", "核心", "内存", "macOS", "已开机", "启动磁盘", "内建显示器", "显示器"])
        let values = model.rows.map { $0.value }
        XCTAssertEqual(values[0], "Mac14,9")
        XCTAssertEqual(values[2], "10 核 CPU（6 性能核 + 4 能效核） · 16 核 GPU")
        XCTAssertEqual(values[3], "16 GB")
        XCTAssertEqual(values[5], "3 天 4 小时")
        XCTAssertEqual(values[7], "1512 × 982（像素 3024 × 1964） · 120 Hz")
        XCTAssertEqual(values[8], "Studio Display · 2560 × 1440（像素 5120 × 2880） · 60 Hz")
        XCTAssertTrue(model.rows.allSatisfy { !$0.warning })
        // 序列号露出来了才复制
        XCTAssertTrue(model.text.hasPrefix("MacBook Pro (14-inch, 2023)\nmacOS Sequoia 15.6.1（24G90）\n型号标识：Mac14,9\n芯片型号：Apple M2 Pro"))
        XCTAssertFalse(model.text.contains("macOS：") || model.text.contains("C02XK1ABCD12"))
        model.showsSerial = true
        XCTAssertTrue(model.text.hasSuffix("\n序列号：C02XK1ABCD12"))

        // 启动磁盘剩下不到一成标橙；Intel 的 Mac 没有性能核、能效核和 GPU 核心数
        var full = SystemInfoPlugin.demoReport()
        full.disk = SystemInfo.Disk(name: "Macintosh HD", total: 500_000_000_000, available: 20_000_000_000)
        full.performanceCores = nil
        full.efficiencyCores = nil
        full.gpuCores = nil
        full.bootTime = nil
        full.serial = nil
        let intel = SystemInfoModel(report: full, now: { SystemInfoPlugin.demoNow })
        XCTAssertEqual(intel.rows.filter { $0.warning }.map { $0.label }, ["启动磁盘"])
        XCTAssertEqual(intel.rows.first { $0.label == "核心" }?.value, "10 核 CPU")
        XCTAssertFalse(intel.rows.contains { $0.label == "已开机" })
    }

    func testPluginNeedsNoSelection() {
        XCTAssertTrue(SystemInfoPlugin().info.canHandle(.empty))
    }
}
