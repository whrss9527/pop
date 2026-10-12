import XCTest
@testable import Pop

final class PopLinkTests: XCTestCase {
    private func link(_ string: String) -> PopLink? {
        URL(string: string).flatMap(PopLink.init(url:))
    }

    func testRunLinks() {
        XCTAssertEqual(link("pop://run?plugin=translate&text=Hello%20world"),
                       .run(pluginID: "translate", text: "Hello world", files: []))
        XCTAssertEqual(link("pop://run/textStats?text=%E4%BD%A0%E5%A5%BD"), .run(pluginID: "textStats", text: "你好", files: []))
        XCTAssertEqual(link("pop:run/textStats"), .run(pluginID: "textStats", text: nil, files: []))
        // 不带文字：处理当前选中的内容
        XCTAssertEqual(link("pop://run?plugin=translate"), .run(pluginID: "translate", text: nil, files: []))
        // 文字里的 & 和 + 要编码；+ 不当成空格
        XCTAssertEqual(link("pop://run?plugin=calculate&text=1+2%263"), .run(pluginID: "calculate", text: "1+2&3", files: []))
        XCTAssertEqual(link("pop://translate?text=Bonjour"), .run(pluginID: BuiltinPluginID.translate, text: "Bonjour", files: []))

        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        guard case .run(_, _, let files)? = link("pop://run?plugin=revealInFinder&file=/tmp/a%20b.txt&file=~/c.pdf&file=") else {
            return XCTFail("应该认得出文件")
        }
        XCTAssertEqual(files.map { $0.path(percentEncoded: false) },
                       ["/tmp/a b.txt", (home.hasSuffix("/") ? home : home + "/") + "c.pdf"])

        XCTAssertNil(link("pop://run"))
        XCTAssertNil(link("pop://run?text=hi"))
    }

    func testOtherLinks() {
        XCTAssertEqual(link("pop://ring"), .ring)
        XCTAssertEqual(link("POP://Clipboard"), .clipboard)
        XCTAssertEqual(link("pop://settings"), .settings(nil))
        XCTAssertEqual(link("pop://settings/translation"), .settings(.translation))
        XCTAssertEqual(link("pop://settings/hotkeys"), .settings(.hotKeys))
        XCTAssertEqual(link("pop://plugin-library"), .pluginLibrary)
        XCTAssertNil(link("pop://settings/nothing"))
        XCTAssertNil(link("pop://unknown"))
        XCTAssertNil(link("pop://"))
        XCTAssertNil(link("https://example.com/run?plugin=translate"))
    }

    func testWidgetLinksAllowOnlyExplicitInteractiveTools() {
        for tool in WidgetAction.allCases {
            XCTAssertEqual(PopLink(url: tool.url), .widget(tool))
        }
        for url in ["pop://widget", "pop://widget?tool=shell", "pop://widget?tool=translate",
                    "pop://widget?tool=clipboard&tool=screenshotOCR", "pop://widget/run?tool=clipboard"] {
            XCTAssertNil(link(url), url)
        }
        XCTAssertEqual(link("pop://widget?tool=screenshotOCR&text=secret&file=/tmp/private"), .widget(.screenshotOCR),
                       "不把额外字段当作工具输入")
    }

    func testCopiedLinkRoundTrips() {
        XCTAssertEqual(PopLink.runURL("translate").absoluteString, "pop://run?plugin=translate")
        let text = "a b&c=d+e #1 你好/?"
        let url = PopLink.runURL("user-3f9a1c2b", text: text)
        XCTAssertFalse(url.absoluteString.contains(" "))
        XCTAssertEqual(PopLink(url: url), .run(pluginID: "user-3f9a1c2b", text: text, files: []))
        // 所有内置功能的链接都认得回来
        for id in BuiltinPluginID.all {
            XCTAssertEqual(PopLink(url: PopLink.runURL(id)), .run(pluginID: id, text: nil, files: []), id)
        }
    }
    @MainActor
    func testLinkRunCancellationAndSelectedContent() {
        let selected = ContentClassifier.classify(.text("当前选中的内容"))
        for kind in [PluginManifest.Action.Kind.shell, .shortcut, .ai] {
            var manifest = PluginManifest(id: "user-confirm", name: "确认测试")
            manifest.action.type = kind
            let plugin = ManifestPlugin(manifest: manifest)
            var prompts = 0
            let approved = PopCoordinator.authorizeLinkRun(plugin, content: selected) { name, input in
                prompts += 1
                XCTAssertEqual(name, "确认测试")
                XCTAssertEqual(input, "当前选中的内容")
                return false
            }
            XCTAssertFalse(approved)
            XCTAssertEqual(prompts, 1)
            XCTAssertTrue(PopCoordinator.authorizeLinkRun(plugin, content: selected) { _, _ in true })
        }
    }

    @MainActor
    func testLinkRunConfirmationIncludesFilesAndBuiltinAI() {
        var manifest = PluginManifest(id: "user-confirm", name: "确认测试")
        manifest.action.type = .shell
        let files = ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/a.txt")]))
        XCTAssertFalse(PopCoordinator.authorizeLinkRun(ManifestPlugin(manifest: manifest), content: files) { _, input in
            XCTAssertEqual(input, "/tmp/a.txt")
            return false
        })
        for plugin in AIPlugin.all {
            XCTAssertFalse(PopCoordinator.authorizeLinkRun(plugin, content: ContentClassifier.classify(.text("文字"))) { _, _ in false })
        }
        for kind in [PluginManifest.Action.Kind.url, .javascript] {
            manifest.action.type = kind
            XCTAssertTrue(PopCoordinator.authorizeLinkRun(ManifestPlugin(manifest: manifest), content: .empty) { _, _ in
                XCTFail("本地普通功能不应弹出脚本确认")
                return false
            })
        }
    }

}
