import AppKit
import XCTest
@testable import Pop

final class PluginBundleTests: XCTestCase {
    /// 插件包目录里的功能和插件包自己提供的功能对得上；Pop 自带的功能里不再有它们
    func testCatalogMatchesTheBundles() {
        let provided = Set(TestCatalog.bundles.flatMap { $0.makePlugins() }.map(\.info.id))
        XCTAssertEqual(provided, PluginCatalog.functionIDs)
        let core = Set(BuiltinPlugins.make().map(\.info.id))
        XCTAssertTrue(core.isDisjoint(with: PluginCatalog.functionIDs))
        // 每个功能不是 Pop 自带的，就是某个插件包提供的
        XCTAssertEqual(core.union(PluginCatalog.functionIDs), Set(BuiltinPluginID.all))
        XCTAssertEqual(Set(PluginCatalog.packages.map(\.id)).count, PluginCatalog.packages.count)
        for package in PluginCatalog.packages {
            XCTAssertTrue(package.bundleName.hasPrefix("Pop"), package.id)
            XCTAssertNotNil(NSImage(systemSymbolName: package.symbol, accessibilityDescription: nil), package.symbol)
            for id in package.functions {
                XCTAssertEqual(BuiltinCategory.of(id), package.category, id)
                XCTAssertEqual(PluginCatalog.package(providing: id)?.id, package.id)
            }
        }
        XCTAssertNil(PluginCatalog.package(providing: BuiltinPluginID.translate))
    }

    /// 新装的 Pop 只带自带的功能，插件包要用时再装；也不用迁移
    func testFreshInstallHasNoPluginFunctions() {
        var settings = AppSettings()
        XCTAssertTrue(Set(settings.installedPlugins).isDisjoint(with: PluginCatalog.functionIDs))
        XCTAssertTrue(settings.installedPlugins.contains(BuiltinPluginID.translate))
        XCTAssertFalse(settings.adoptPluginBundles(recentlyUsed: [BuiltinPluginID.teleprompter]))
        XCTAssertFalse(settings.isInstalled(BuiltinPluginID.teleprompter))
    }

    /// 老用户升级：在用的功能留着（插件包会自动装上），没在用的去掉；只迁移一次
    func testUpgradeKeepsFunctionsInUse() throws {
        var old = AppSettings()
        old.installedPlugins = BuiltinPluginID.all
        old.ring.place(BuiltinPluginID.screenPen, at: 3)
        old.setHotKey(KeyCombo(keyCode: 1, modifiers: 256), for: BuiltinPluginID.cameraBubble)
        // 旧版本的设置里没有 movedToPlugins
        let data = try JSONEncoder().encode(old)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["movedToPlugins"] = nil
        var settings = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(settings.movedToPlugins.isEmpty)

        XCTAssertTrue(settings.adoptPluginBundles(recentlyUsed: [BuiltinPluginID.teleprompter], onDisk: []))
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.screenPen))
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.cameraBubble))
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.teleprompter))
        XCTAssertFalse(settings.isInstalled(BuiltinPluginID.pointerHighlight))
        // 自带的功能不受影响
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.translate))
        XCTAssertEqual(Set(settings.movedToPlugins), PluginCatalog.functionIDs)
        // 再来一次什么都不变
        XCTAssertFalse(settings.adoptPluginBundles(recentlyUsed: [], onDisk: []))
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.teleprompter))
    }

    /// 这台 Mac 上已经装着的插件包，迁移时留着
    func testUpgradeKeepsBundlesOnDisk() {
        var settings = AppSettings()
        settings.movedToPlugins = []
        settings.installedPlugins.removeAll { $0 == BuiltinPluginID.pointerHighlight }
        XCTAssertTrue(settings.adoptPluginBundles(recentlyUsed: [], onDisk: ["pointerHighlight"]))
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.pointerHighlight))
        XCTAssertFalse(settings.isInstalled(BuiltinPluginID.teleprompter))
    }

    /// 迁移过的插件包在新版本里多了功能：装着这个插件包的把新功能也装上（这台 Mac 上还没下载好也一样），没装的不受影响
    func testInstalledPackageGetsItsNewFunctions() {
        var settings = AppSettings()
        settings.movedToPlugins.removeAll { $0 == BuiltinPluginID.speakToFile }
        settings.installedPlugins.append(BuiltinPluginID.speak)
        XCTAssertTrue(settings.adoptPluginBundles(recentlyUsed: [], onDisk: []))
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.speak))
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.speakToFile))
        XCTAssertTrue(settings.movedToPlugins.contains(BuiltinPluginID.speakToFile))
        XCTAssertFalse(settings.adoptPluginBundles(recentlyUsed: [], onDisk: []))

        var other = AppSettings()
        other.movedToPlugins.removeAll { $0 == BuiltinPluginID.speakToFile }
        XCTAssertTrue(other.adoptPluginBundles(recentlyUsed: [BuiltinPluginID.speak], onDisk: []))
        XCTAssertFalse(other.isInstalled(BuiltinPluginID.speak))
        XCTAssertFalse(other.isInstalled(BuiltinPluginID.speakToFile))
    }

    /// 新版本新加的插件包功能不会自动装上
    func testNewPluginFunctionsAreNotAdopted() {
        var settings = AppSettings()
        settings.knownBuiltinPlugins.removeAll { $0 == BuiltinPluginID.teleprompter || $0 == BuiltinPluginID.translate }
        settings.installedPlugins.removeAll { $0 == BuiltinPluginID.translate }
        settings.adoptNewBuiltinPlugins()
        XCTAssertFalse(settings.isInstalled(BuiltinPluginID.teleprompter))
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.translate))
        XCTAssertTrue(settings.knownBuiltinPlugins.contains(BuiltinPluginID.teleprompter))
    }

    /// 发布页上的插件包列表（scripts/package-plugins.sh 生成的格式）
    func testReleaseIndexDecodes() throws {
        let json = """
        {"format": 1, "version": "0.44.0", "build": "0.44.0+abc", "plugins": [
          {"id": "teleprompter", "bundle": "PopTeleprompter.bundle", "file": "plugin-teleprompter.zip",
           "sha256": "ABC", "size": 1234, "installedSize": 5678}]}
        """
        let index = try JSONDecoder().decode(PluginReleaseIndex.self, from: Data(json.utf8))
        XCTAssertEqual(index.build, "0.44.0+abc")
        XCTAssertEqual(index.entry(id: "teleprompter")?.installedSize, 5678)
        XCTAssertEqual(index.entry(id: "teleprompter")?.file, "plugin-teleprompter.zip")
        XCTAssertNil(index.entry(id: "screenPen"))
    }

    /// 文件夹里只认 Info.plist 里有 PopPluginID 的 .bundle
    func testFindsBundlesInAFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pop-plugins-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        func makeBundle(_ name: String, info: [String: Any]) throws {
            let contents = folder.appendingPathComponent("\(name)/Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        try makeBundle("PopTeleprompter.bundle", info: ["PopPluginID": "teleprompter", "PopBuildID": "1.0+abc"])
        try makeBundle("Other.bundle", info: ["CFBundleIdentifier": "com.example.other"])
        try makeBundle("PopScreenPen.plugin", info: ["PopPluginID": "screenPen"])
        let found = PluginBundles.bundles(in: folder)
        XCTAssertEqual(found.map(\.lastPathComponent), ["PopTeleprompter.bundle"])
        XCTAssertEqual(PluginBundles.pluginID(of: found[0]), "teleprompter")
        XCTAssertEqual(PluginBundles.buildID(of: found[0]), "1.0+abc")
        XCTAssertGreaterThan(PluginManager.size(of: found[0]), 0)
        XCTAssertEqual(PluginBundles.bundles(in: folder.appendingPathComponent("missing")), [])
    }

    /// 演示步骤按顺序排
    @MainActor
    func testDemoScenesAreOrdered() {
        let host = PluginHost.Registrar(owner: "test-owner")
        host.addDemoScene(PluginHost.DemoScene(name: "b", after: "test-step", order: 2, show: { _ in nil }, hide: {}))
        host.addDemoScene(PluginHost.DemoScene(name: "a", after: "test-step", order: 1, show: { _ in nil }, hide: {}))
        XCTAssertEqual(PluginHost.shared.demoScenes(after: "test-step").map(\.name), ["a", "b"])
        PluginHost.shared.removeAll(owner: "test-owner")
        XCTAssertTrue(PluginHost.shared.demoScenes(after: "test-step").isEmpty)
    }
}
