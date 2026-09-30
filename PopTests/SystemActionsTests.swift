import XCTest
@testable import Pop

final class SystemActionsTests: XCTestCase {
    private func volume(builtIn: Bool = true, ejectable: Bool = false, removable: Bool = false, local: Bool = true,
                        root: Bool = false) -> SystemActions.Volume {
        SystemActions.Volume(url: URL(fileURLWithPath: "/Volumes/磁盘"), isInternal: builtIn, isEjectable: ejectable,
                             isRemovable: removable, isLocal: local, isRoot: root)
    }

    func testWhichVolumesCanBeEjected() {
        // 启动磁盘、内置硬盘上的其他宗卷不推出
        XCTAssertFalse(SystemActions.isEjectable(volume(root: true)))
        XCTAssertFalse(SystemActions.isEjectable(volume()))
        // U 盘、移动硬盘、磁盘映像、网络磁盘
        XCTAssertTrue(SystemActions.isEjectable(volume(builtIn: false, ejectable: true, removable: true)))
        XCTAssertTrue(SystemActions.isEjectable(volume(builtIn: false)))
        XCTAssertTrue(SystemActions.isEjectable(volume(ejectable: true)))
        XCTAssertTrue(SystemActions.isEjectable(volume(local: false)))
    }

    func testReadsTheDesktopIconsSetting() throws {
        let suite = "pop-finder-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // 没设置过就是显示
        XCTAssertTrue(SystemActions.desktopIconsVisible(in: defaults))
        defaults.set(false, forKey: SystemActions.desktopIconsKey)
        XCTAssertFalse(SystemActions.desktopIconsVisible(in: defaults))
        defaults.set("true", forKey: SystemActions.desktopIconsKey)
        XCTAssertTrue(SystemActions.desktopIconsVisible(in: defaults))
        XCTAssertTrue(SystemActions.desktopIconsVisible(in: nil))
    }

    func testCardButtons() {
        let card = SystemActions.card(desktopIconsVisible: true, darkMode: false, ejectable: 0)
        XCTAssertEqual(card.title, "系统操作")
        XCTAssertEqual(card.buttons.map(\.title), ["锁屏", "熄屏", "睡眠", "屏幕保护程序", "换成深色模式", "隐藏桌面图标"])
        XCTAssertEqual(card.buttons.map(\.action), [.system(.lockScreen), .system(.displaySleep), .system(.sleep),
                                                    .system(.screenSaver), .system(.toggleDarkMode), .system(.toggleDesktopIcons)])
        // 深色模式、桌面图标藏起来了、插着磁盘
        let withDisks = SystemActions.card(desktopIconsVisible: false, darkMode: true, ejectable: 2)
        XCTAssertEqual(withDisks.buttons.map(\.title), ["锁屏", "熄屏", "睡眠", "屏幕保护程序", "换成浅色模式", "显示桌面图标", "推出 2 个磁盘"])
        XCTAssertEqual(withDisks.buttons.last?.action, .system(.ejectAll))
        XCTAssertEqual(SystemActions.card(desktopIconsVisible: true, darkMode: false, ejectable: 1).buttons.last?.title, "推出磁盘")
    }

    func testReadsTheAppearance() {
        XCTAssertTrue(SystemActions.isDarkMode(style: "Dark"))
        XCTAssertFalse(SystemActions.isDarkMode(style: nil))
        XCTAssertFalse(SystemActions.isDarkMode(style: "Light"))
    }

    @MainActor
    func testPluginShowsTheCard() async {
        let outcome = await SystemActionsPlugin().run(.empty, context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.title, "系统操作")
        XCTAssertTrue(card.buttons.contains { $0.action == .system(.lockScreen) })
        XCTAssertTrue(SystemActionsPlugin().info.canHandle(.empty))
    }
}
