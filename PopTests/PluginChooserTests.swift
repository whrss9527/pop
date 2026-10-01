import XCTest
@testable import Pop

@MainActor
final class PluginChooserTests: XCTestCase {
    private func info(_ id: String, _ name: String) -> PluginInfo {
        PluginInfo(id: id, name: name, symbol: "star", summary: "\(name)的说明", accepts: [])
    }

    func testListsUninstalledPackagesOnlyWhenSearching() {
        let packages = PluginCatalog.packages.filter { ["regexTest", "zip"].contains($0.id) }
        let model = PluginChooserModel(plugins: [info("translate", "翻译")], packages: packages)
        XCTAssertEqual(model.results.map(\.id), ["translate"])
        XCTAssertTrue(model.packages.isEmpty)
        // 插件包的 ID、功能 ID 和名字的拼音首字母都能搜到
        model.query = "zip"
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertEqual(model.packages.map(\.id), ["zip"])
        model.query = "zzcs"
        XCTAssertEqual(model.packages.map(\.id), ["regexTest"])
        model.query = "  "
        XCTAssertEqual(model.results.map(\.id), ["translate"])
        XCTAssertTrue(model.packages.isEmpty)
    }

    func testSelectionRunsActionsAndInstallsPackages() {
        let packages = PluginCatalog.packages.filter { $0.id == "regexTest" }
        let model = PluginChooserModel(plugins: [info("textStats", "字数统计"), info("regexDemo", "正则演示")], packages: packages)
        var ran: [String] = []
        var installed: [String] = []
        model.onRun = { ran.append($0.id) }
        model.onInstall = { installed.append($0.id) }
        model.query = "正则"
        XCTAssertEqual(model.results.map(\.id), ["regexDemo"])
        XCTAssertEqual(model.packages.map(\.id), ["regexTest"])
        XCTAssertEqual(model.selectedRowID, "regexDemo")
        // 已装的功能后面接着没装的插件包
        model.move(1)
        XCTAssertEqual(model.selectedRowID, "package-regexTest")
        model.move(1)
        XCTAssertEqual(model.selection, 1)
        model.activate(model.selection)
        model.activate(0)
        XCTAssertEqual(installed, ["regexTest"])
        XCTAssertEqual(ran, ["regexDemo"])
        // 没有插件管理时当作没装，也不知道下载多大
        XCTAssertEqual(model.status(of: packages[0]), .notInstalled)
        XCTAssertNil(model.downloadSize(of: packages[0]))
    }
}
