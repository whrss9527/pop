import XCTest
@testable import Pop

final class ChangelogTests: XCTestCase {
    func testBetaBuildShowsAccumulatedChangesAndIntermediateStableVersions() {
        let text = "# 更新记录\n\n## 未发布\n- new\n## 0.68.1\n- fixed"
        let releases = Changelog.forBuild(text, current: "0.69.0-beta.10")
        XCTAssertEqual(releases.map(\.version), ["0.69.0-beta.10", "0.68.1"])
        XCTAssertEqual(Changelog.releases(releases, after: "0.68.0", upTo: "0.69.0-beta.10").count, 2)
        XCTAssertEqual(Changelog.forBuild(text, current: "0.69.0").map(\.version), ["0.69.0", "0.68.1"])
    }

    private let sample = """
    # 更新记录

    ## 0.30.0（2026-09-30）

    ### 新增

    - **录屏**：拖出一块区域录成 MP4。
    - **视频拼缩略图**：从视频里均匀取 16 帧。

    ## 说明

    这一节不是版本，跳过。

    ## 0.29.1（2026-09-29）

    ### 修复

    - 修好了一个问题。

    ## 0.29.0 (2026-09-28)

    ### 新增

    - **网页存档**：整页存成 PDF。
    - **录屏**：重复的名字只算一次。

    ### 修复

    - **不算**：修复里的加粗不是新增。
    """

    func testConsecutiveSameDayUpdatesKeepTheOriginalBaseline() {
        let name = "changelog-daily-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("0.29.0", forKey: Changelog.lastVersionKey)
        _ = Changelog.whatsNew(current: "0.29.1", releases: Changelog.parse(sample), defaults: defaults)
        XCTAssertTrue(UpdateNotificationGate.claim(defaults: defaults))
        _ = Changelog.whatsNew(current: "0.30.0", releases: Changelog.parse(sample), defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: Changelog.updatedFromKey), "0.29.0")
        XCTAssertEqual(Changelog.recent(current: "0.30.0", releases: Changelog.parse(sample), defaults: defaults).map(\.version), ["0.30.0", "0.29.1"])
    }

    func testParsesEachRelease() {
        let releases = Changelog.parse(sample)
        XCTAssertEqual(releases.map(\.version), ["0.30.0", "0.29.1", "0.29.0"])
        XCTAssertEqual(releases.map(\.date), ["2026-09-30", "2026-09-29", "2026-09-28"])
        XCTAssertTrue(releases[0].notes.hasPrefix("### 新增"), releases[0].notes)
        XCTAssertFalse(releases[0].notes.contains("这一节不是版本"))
        XCTAssertEqual(releases[1].notes, "### 修复\n\n- 修好了一个问题。")
        XCTAssertNil(Changelog.heading("## 说明"))
        XCTAssertEqual(Changelog.heading("## 1.0.0")?.version, "1.0.0")
        XCTAssertNil(Changelog.heading("## 1.0.0")?.date)
    }

    func testHighlightsAndSummary() {
        let releases = Changelog.parse(sample)
        XCTAssertEqual(Changelog.releases(releases, after: "0.29.0", upTo: "0.30.0").map(\.version), ["0.30.0", "0.29.1"])
        XCTAssertEqual(Changelog.releases(releases, after: "0.28.0", upTo: "0.29.1").map(\.version), ["0.29.1", "0.29.0"])
        XCTAssertEqual(Changelog.highlights(releases), ["录屏", "视频拼缩略图", "网页存档"])
        XCTAssertEqual(Changelog.summary(Array(releases.prefix(1))), "新增：录屏、视频拼缩略图。点这里看更新内容。")
        XCTAssertEqual(Changelog.summary([releases[1]]), "修了一些问题，用起来更顺手。点这里看更新内容。")
        let many = Changelog.parse("""
        ## 2.0.0（2026-10-01）

        ### 新增

        - **一**：a
        - **二**：b
        - **三**：c
        - **四**：d
        - **五**：e
        """)
        XCTAssertEqual(Changelog.summary(many), "新增：一、二、三、四 等 5 项。点这里看更新内容。")
        // 更新记录只有中文：别的界面语言不列名字，点开看网页上的说明
        XCTAssertEqual(Changelog.summary(releases, chinese: false), "点这里看这一版的更新说明。")
        XCTAssertEqual(Changelog.releasePage("0.31.0").absoluteString, "https://github.com/whrss9527/pop/releases/tag/v0.31.0")
    }

    func testTellsWhatIsNewOnlyAfterAnUpdate() throws {
        let suite = "pop-changelog-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let releases = Changelog.parse(sample)
        // 第一次装：不说，记下版本
        XCTAssertNil(Changelog.whatsNew(current: "0.29.0", releases: releases, defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: Changelog.lastVersionKey), "0.29.0")
        // 同一版再启动：不说
        XCTAssertNil(Changelog.whatsNew(current: "0.29.0", releases: releases, defaults: defaults))
        XCTAssertEqual(Changelog.recent(current: "0.29.0", releases: releases, defaults: defaults).map(\.version), ["0.29.0"])
        // 更新了两版：说这两版新增的，「更新」页列出这两版
        XCTAssertEqual(Changelog.whatsNew(current: "0.30.0", releases: releases, defaults: defaults),
                       "新增：录屏、视频拼缩略图。点这里看更新内容。")
        XCTAssertEqual(Changelog.recent(current: "0.30.0", releases: releases, defaults: defaults).map(\.version), ["0.30.0", "0.29.1"])
        // 装回旧版：不说
        XCTAssertNil(Changelog.whatsNew(current: "0.29.1", releases: releases, defaults: defaults))
    }

    /// App 里带着的更新记录最上面一版就是现在的版本（发版时两处要一起改）
    func testBundledChangelogMatchesTheAppVersion() throws {
        let bundled = Changelog.bundled
        XCTAssertGreaterThan(bundled.count, 10)
        XCTAssertEqual(bundled.first?.version, UpdateChecker.currentVersion)
        // 早期的几版没写日期
        let resource = try XCTUnwrap(Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"))
        let text = try String(contentsOf: resource, encoding: .utf8)
        if text.contains("## 未发布") || text.contains("## Unreleased") || UpdateChecker.currentVersion.contains("-") {
            XCTAssertNil(bundled.first?.date)
        } else {
            XCTAssertNotNil(bundled.first?.date)
        }
        for release in bundled {
            XCTAssertFalse(release.notes.isEmpty, release.version)
        }
    }
}
