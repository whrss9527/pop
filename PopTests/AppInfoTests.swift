import Darwin
import XCTest
@testable import Pop

final class AppInfoTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "pop-appinfo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 单一芯片的 Mach-O 头（小端）：魔数、cputype
    private func thin(_ cpu: UInt32) -> [UInt8] {
        [0xCF, 0xFA, 0xED, 0xFE] + withUnsafeBytes(of: cpu.littleEndian, Array.init) + [UInt8](repeating: 0, count: 24)
    }

    /// 通用二进制的头（大端）：魔数、几种、每种 20 字节
    private func fat(_ cpus: [UInt32]) -> [UInt8] {
        var bytes: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE] + withUnsafeBytes(of: UInt32(cpus.count).bigEndian, Array.init)
        for cpu in cpus {
            bytes += withUnsafeBytes(of: cpu.bigEndian, Array.init) + [UInt8](repeating: 0, count: 16)
        }
        return bytes
    }

    private func makeApp(_ name: String, info extra: [String: Any] = [:], executable: [UInt8], frameworks: [String] = []) throws -> URL {
        let app = root.appending(path: "\(name).app", directoryHint: .isDirectory)
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents.appending(path: "MacOS", directoryHint: .isDirectory), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": "com.example.\(name.lowercased())", "CFBundleName": name, "CFBundleExecutable": name,
                                   "CFBundlePackageType": "APPL"]
        info.merge(extra) { _, new in new }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appending(path: "Info.plist"))
        try Data(executable).write(to: contents.appending(path: "MacOS/\(name)"))
        for framework in frameworks {
            try FileManager.default.createDirectory(at: contents.appending(path: "Frameworks/\(framework)", directoryHint: .isDirectory), withIntermediateDirectories: true)
        }
        return app
    }

    func testArchitecturesFromMachOHeaders() {
        XCTAssertEqual(AppInspector.architecture(header: thin(AppInspector.cpuARM64)), .appleSilicon)
        XCTAssertEqual(AppInspector.architecture(header: thin(AppInspector.cpuX86_64)), .intel)
        XCTAssertEqual(AppInspector.architecture(header: fat([AppInspector.cpuX86_64, AppInspector.cpuARM64])), .universal)
        XCTAssertEqual(AppInspector.architecture(header: fat([AppInspector.cpuARM64])), .appleSilicon)
        XCTAssertEqual(AppInspector.architecture(header: [0x23, 0x21, 0x2F, 0x62, 0x69, 0x6E, 0x2F, 0x73]), .unknown)
        XCTAssertEqual(AppInspector.architecture(header: [0xCF]), .unknown)
    }

    func testSignatureNamesFromCertificates() {
        XCTAssertEqual(AppInspector.classify(leaf: "Developer ID Application: Example Studio (ABCDE12345)", adHoc: false), .developerID("Example Studio"))
        XCTAssertEqual(AppInspector.classify(leaf: "Apple Mac OS Application Signing", adHoc: false), .appStore)
        XCTAssertEqual(AppInspector.classify(leaf: "Software Signing", adHoc: false), .apple)
        XCTAssertEqual(AppInspector.classify(leaf: "Apple Development: someone@example.com (XYZ123)", adHoc: false), .development("someone@example.com"))
        XCTAssertEqual(AppInspector.classify(leaf: "", adHoc: true), .adHoc)
        XCTAssertEqual(AppInspector.classify(leaf: "", adHoc: false), .unsigned)
        XCTAssertEqual(AppInspector.Signature.developerID("Example Studio").title, "Developer ID：Example Studio")
    }

    func testReadsInfoPlistAndBundleContents() throws {
        let url = try makeApp("Sketch", info: [
            "CFBundleShortVersionString": "3.2.1", "CFBundleVersion": "321", "LSMinimumSystemVersion": "12.0",
            "NSCameraUsageDescription": "扫描草图", "NSMicrophoneUsageDescription": "录语音笔记",
            "NSCalendarsUsageDescription": "旧写法", "NSCalendarsFullAccessUsageDescription": "新写法",
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["sketch", "sketch-beta"]], ["CFBundleURLSchemes": ["sketch"]]],
        ], executable: fat([AppInspector.cpuARM64, AppInspector.cpuX86_64]), frameworks: ["Electron Framework.framework", "Sparkle.framework"])
        let report = try AppInspector.inspect(url)
        XCTAssertEqual(report.name, "Sketch")
        XCTAssertEqual(report.bundleID, "com.example.sketch")
        XCTAssertEqual(report.version, "3.2.1（321）")
        XCTAssertEqual(report.architecture, .universal)
        XCTAssertEqual(report.minimumSystem, "macOS 12.0")
        // 没签名
        XCTAssertEqual(report.signature, .unsigned)
        XCTAssertNil(report.notarized)
        XCTAssertFalse(report.sandboxed)
        XCTAssertEqual(report.technologies, ["Electron", "Sparkle 自动更新"])
        // 日历的新旧两种写法算一个，用新的那条说明
        XCTAssertEqual(report.permissions.map(\.name), ["摄像头", "麦克风", "日历"])
        XCTAssertEqual(report.permissions.last?.reason, "新写法")
        XCTAssertEqual(report.urlSchemes, ["sketch://", "sketch-beta://"])
        XCTAssertFalse(report.fromAppStore)
        XCTAssertNil(report.downloadedBy)
        XCTAssertThrowsError(try AppInspector.inspect(root))

        // 版本号和构建号一样时只写一个
        let same = try makeApp("Same", info: ["CFBundleShortVersionString": "2.0", "CFBundleVersion": "2.0"], executable: thin(AppInspector.cpuARM64))
        XCTAssertEqual(try AppInspector.inspect(same).version, "2.0")
    }

    func testQuarantineAndAppStoreReceipt() throws {
        let url = try makeApp("Downloaded", executable: thin(AppInspector.cpuX86_64))
        let value = "0083;66f1a2b3;Safari;F2A3C4D5-0000-1111-2222-333344445555"
        let result = value.withCString { pointer in
            setxattr(url.path(percentEncoded: false), "com.apple.quarantine", pointer, strlen(pointer), 0, 0)
        }
        XCTAssertEqual(result, 0)
        let receipt = url.appending(path: "Contents/_MASReceipt", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: receipt, withIntermediateDirectories: true)
        try Data([1]).write(to: receipt.appending(path: "receipt"))
        let report = try AppInspector.inspect(url)
        XCTAssertEqual(report.architecture, .intel)
        XCTAssertEqual(report.downloadedBy, "Safari")
        XCTAssertTrue(report.fromAppStore)
        XCTAssertEqual(AppInspector.source(report), "App Store")
        XCTAssertGreaterThan(AppInspector.size(of: url), 0)
    }

    @MainActor
    func testCardRowsAndCopiedText() {
        let report = AppInfoPlugin.demoReport()
        let model = AppInfoModel(report: report, icon: nil, size: 412_000_000)
        let rows = model.rows
        XCTAssertEqual(rows.map(\.label), ["芯片", "最低系统", "签名", "公证", "沙盒", "加固运行时", "用什么做的", "来源", "大小", "打开它的链接"])
        XCTAssertEqual(rows[2].value, "Developer ID：Example Studio（ABCDE12345）")
        XCTAssertEqual(rows[7].value, "用「Safari」下载的")
        XCTAssertFalse(rows.contains { $0.warning })
        let text = model.text
        XCTAssertTrue(text.hasPrefix("Sketchpad 3.2.1（321）\n标识符：com.example.sketchpad\n芯片：通用（Apple 芯片和 Intel）"))
        XCTAssertTrue(text.contains("会要的权限：摄像头、麦克风、下载文件夹"))
        // 只给 Intel 做的、没有公证的标出来
        let old = AppInspector.Report(url: report.url, name: "Old", bundleID: nil, version: nil, architecture: .intel, minimumSystem: nil,
                                      signature: .developerID("Someone"), teamID: nil, notarized: false, sandboxed: false, hardenedRuntime: false,
                                      technologies: [], permissions: [], urlSchemes: [], fromAppStore: false, downloadedBy: nil)
        let warnings = AppInfoModel(report: old, icon: nil).rows.filter(\.warning).map(\.label)
        XCTAssertEqual(warnings, ["芯片", "公证"])
    }

    func testPluginTakesApps() {
        let plugin = AppInfoPlugin().info
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/Applications/Fake.app", isDirectory: true)]))))
        XCTAssertFalse(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/a.txt")]))))
        XCTAssertFalse(plugin.canHandle(.empty))
    }
}
