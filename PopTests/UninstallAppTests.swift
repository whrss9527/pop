import AppKit
import XCTest
@testable import Pop

final class UninstallAppTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "pop-uninstall-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var library: URL {
        root.appending(path: "Library", directoryHint: .isDirectory)
    }

    /// 一个最简单的 App：Contents/Info.plist 和可执行文件，可以带一个扩展
    private func makeApp(_ name: String, id: String, extensionID: String? = nil) throws -> URL {
        let app = root.appending(path: "Applications/\(name).app", directoryHint: .isDirectory)
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents.appending(path: "MacOS", directoryHint: .isDirectory), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleExecutable": name,
                                   "CFBundleShortVersionString": "1.2", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appending(path: "Info.plist"))
        try Data(repeating: 1, count: 5000).write(to: contents.appending(path: "MacOS/\(name)"))
        if let extensionID {
            let appex = contents.appending(path: "PlugIns/Share.appex/Contents", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: appex, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": extensionID, "CFBundlePackageType": "XPC!"], format: .xml, options: 0)
                .write(to: appex.appending(path: "Info.plist"))
        }
        return app
    }

    /// 在假的「资源库」里放一个文件（中间的文件夹一起建好）
    private func touch(_ path: String, bytes: Int = 100) throws {
        let url = library.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    /// 「地方 相对路径 有没有疑问」
    private func describe(_ items: [AppUninstaller.Item]) -> [String] {
        let base = library.path(percentEncoded: false)
        return items.map { item in
            var path = item.url.path(percentEncoded: false)
            if path.hasSuffix("/") { path.removeLast() }
            let relative = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : (path as NSString).lastPathComponent
            let doubt = item.doubt.map { $0 == .prefix ? " ?" : " 共用" } ?? ""
            return "\(item.place.rawValue) \(relative)\(doubt)"
        }
    }

    func testReadsTheAppAndItsExtensions() throws {
        let url = try makeApp("Fake", id: "com.example.fake", extensionID: "com.example.fake.share")
        let app = try AppUninstaller.app(at: url)
        XCTAssertEqual(app.name, "Fake")
        XCTAssertEqual(app.bundleID, "com.example.fake")
        XCTAssertEqual(app.version, "1.2")
        XCTAssertEqual(app.executable, "Fake")
        XCTAssertEqual(app.relatedIDs, ["com.example.fake", "com.example.fake.share"])
        XCTAssertFalse(app.isApple)
        // 没签名的 App 读不出开发者团队和 App 组
        XCTAssertNil(app.teamID)
        XCTAssertEqual(app.groups, [])
        XCTAssertThrowsError(try AppUninstaller.app(at: root.appending(path: "Applications", directoryHint: .isDirectory)))

        let apple = AppUninstaller.App(url: URL(fileURLWithPath: "/Applications/Safari.app"), name: "Safari", bundleID: "com.apple.Safari",
                                       version: nil, executable: nil, relatedIDs: [], groups: [], teamID: nil)
        XCTAssertTrue(apple.isApple)
        let system = AppUninstaller.App(url: URL(fileURLWithPath: "/System/Applications/Notes.app"), name: "Notes", bundleID: nil,
                                        version: nil, executable: nil, relatedIDs: [], groups: [], teamID: nil)
        XCTAssertTrue(system.isApple)
    }

    func testFindsLeftoversByBundleIDAndName() throws {
        let url = try makeApp("Fake", id: "com.example.fake", extensionID: "com.example.fake.share")
        let app = try AppUninstaller.app(at: url)
        try touch("Application Support/com.example.fake/a.db")
        try touch("Application Support/Fake/b.db")
        try touch("Application Support/Other/c.db")
        try touch("Caches/com.example.fake/cache.db", bytes: 10_000)
        try touch("HTTPStorages/com.example.fake.binarycookies")
        try touch("Preferences/com.example.fake.plist")
        try touch("Preferences/com.example.fake.pro.plist")
        try touch("Preferences/com.example.fakeish.plist")
        try touch("Preferences/ByHost/com.example.fake.0A1B2C3D-0000-1111-2222-333344445555.plist")
        try touch("Containers/com.example.fake.share/Data/x")
        try touch("Containers/com.example.other/Data/x")
        try touch("Group Containers/ABCDE12345.com.example.fake/y")
        try touch("Saved Application State/com.example.fake.savedState/window.data")
        try touch("Logs/Fake/log.txt")
        try touch("LaunchAgents/com.example.fake.helper.plist")

        let items = AppUninstaller.scan(app, library: library)
        XCTAssertEqual(items.first?.url, url)
        XCTAssertEqual(Array(describe(items).dropFirst()), [
            "support Application Support/Fake",
            "support Application Support/com.example.fake",
            "caches Caches/com.example.fake",
            "caches HTTPStorages/com.example.fake.binarycookies",
            "preferences Preferences/com.example.fake.plist",
            "preferences Preferences/com.example.fake.pro.plist ?",
            "preferences Preferences/ByHost/com.example.fake.0A1B2C3D-0000-1111-2222-333344445555.plist",
            "containers Containers/com.example.fake.share",
            "groupContainers Group Containers/ABCDE12345.com.example.fake 共用",
            "savedState Saved Application State/com.example.fake.savedState",
            "logs Logs/Fake",
            "launchAgents LaunchAgents/com.example.fake.helper.plist ?",
        ])

        // 大小：文件夹里的都算上，App 本身也算
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(AppUninstaller.size(of: library.appending(path: "Caches/com.example.fake"))), 10_000)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(AppUninstaller.size(of: url)), 5000)
        XCTAssertNil(AppUninstaller.size(of: library.appending(path: "没有这个")))
    }

    func testDisplayPathStartsFromHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertEqual(AppUninstaller.displayPath(home.appending(path: "Library/Caches/com.example.fake", directoryHint: .isDirectory)),
                       "~/Library/Caches/com.example.fake")
        XCTAssertEqual(AppUninstaller.displayPath(URL(fileURLWithPath: "/Applications/Fake.app", isDirectory: true)), "/Applications/Fake.app")
    }

    @MainActor
    func testCardChecksSureItemsQuitsTheAppAndMovesThemToTheTrash() async throws {
        let (app, items, sizes) = UninstallAppPlugin.demo()
        var running = true
        var quitAsked = false
        var recycled: [URL] = []
        let model = UninstallAppModel(app: app, icon: nil, items: items, sizes: sizes,
                                      isRunning: { running }, quit: { quitAsked = true; running = false },
                                      recycle: { urls in
                                          recycled = urls
                                          // 日志没能移走
                                          return urls.filter { !$0.path(percentEncoded: false).contains("/Logs/") }
                                      })
        XCTAssertTrue(model.running)
        XCTAssertFalse(model.measuring)
        XCTAssertEqual(model.leftovers, 8)
        XCTAssertEqual(model.actionTitle, "退出并卸载")
        // 共享容器有疑问，默认不勾
        XCTAssertEqual(model.checked.count, 8)
        XCTAssertFalse(model.isChecked(items[5]))
        XCTAssertEqual(model.total, 2_054_248_000)
        XCTAssertEqual(model.summary, "把勾上的 8 项（\(AppUninstaller.format(2_054_248_000))）移到废纸篓；需要时可以从废纸篓放回原处")
        // 只清掉留下的文件，App 留着
        model.toggle(items[0])
        XCTAssertEqual(model.actionTitle, "清掉这些文件")
        XCTAssertEqual(model.summary, "把勾上的 7 项（\(AppUninstaller.format(2_054_248_000 - 412_000_000))）移到废纸篓，App 留着，下次打开就像刚装好一样")
        model.toggle(items[0])

        model.uninstall()
        XCTAssertEqual(model.phase, .working)
        for _ in 0..<200 where model.phase == .working {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(quitAsked)
        XCTAssertEqual(recycled, items.filter { model.isChecked($0) }.map(\.url))
        XCTAssertEqual(model.phase, .done(trashed: 7, freed: 2_054_248_000 - 3_100_000, failed: ["~/Library/Logs/Sketchpad"]))
    }

    @MainActor
    func testCardGivesUpWhenTheAppDoesNotQuit() async throws {
        let (app, items, sizes) = UninstallAppPlugin.demo()
        var recycled = false
        let model = UninstallAppModel(app: app, icon: nil, items: items, sizes: sizes, isRunning: { true }, quit: {},
                                      recycle: { urls in recycled = true; return urls }, patience: 0.2)
        model.uninstall()
        for _ in 0..<200 where model.phase == .working {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.phase, .failed("「Sketchpad」还没有退出（可能在问要不要存文稿），退出以后再卸载"))
        XCTAssertFalse(recycled)
    }

    @MainActor
    func testCardMeasuresSizesInTheBackground() async throws {
        let url = try makeApp("Fake", id: "com.example.fake")
        try touch("Caches/com.example.fake/cache.db", bytes: 20_000)
        let app = try AppUninstaller.app(at: url)
        let model = UninstallAppModel(app: app, icon: nil, items: AppUninstaller.scan(app, library: library),
                                      isRunning: { false }, quit: {}, recycle: { $0 })
        XCTAssertTrue(model.measuring)
        XCTAssertEqual(model.summary, "正在算大小…")
        XCTAssertEqual(model.actionTitle, "移到废纸篓")
        model.measure()
        for _ in 0..<300 where model.measuring {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.measuring)
        XCTAssertGreaterThanOrEqual(model.total, 25_000)
    }

    func testPluginTakesApps() {
        let plugin = UninstallAppPlugin().info
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/Applications/Fake.app", isDirectory: true)]))))
        XCTAssertFalse(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/说明.txt")]))))
        XCTAssertFalse(plugin.canHandle(.empty))
        let (app, items, sizes) = UninstallAppPlugin.demo()
        XCTAssertEqual(app.name, "Sketchpad")
        XCTAssertEqual(items.count, 9)
        XCTAssertEqual(sizes.count, 9)
    }
}
