import XCTest
@testable import Pop

final class UpdateCheckerTests: XCTestCase {
    private func release(_ tag: String, prerelease: Bool = false, draft: Bool = false, assets: [String] = ["Pop-VERSION.zip", "SHA256SUMS.txt"]) -> [String: Any] {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return [
            "tag_name": tag,
            "name": "Pop \(version)",
            "draft": draft,
            "prerelease": prerelease,
            "html_url": "https://github.com/whrss9527/pop/releases/tag/\(tag)",
            "published_at": "2026-09-28T15:38:00Z",
            "body": "### 新增\n\n- 测试",
            "assets": assets.map { name -> [String: Any] in
                let fileName = name.replacingOccurrences(of: "VERSION", with: version)
                return ["name": fileName, "size": 1234, "browser_download_url": "https://example.com/\(tag)/\(fileName)"]
            },
        ]
    }

    private func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    func testParsesListAndSingleRelease() throws {
        let list = try XCTUnwrap(UpdateChecker.parseReleases(data([release("v0.3.0"), release("v0.2.0", prerelease: true)])))
        XCTAssertEqual(list.map(\.version), ["0.3.0", "0.2.0"])
        let first = try XCTUnwrap(list.first)
        XCTAssertEqual(first.tag, "v0.3.0")
        XCTAssertEqual(first.title, "Pop 0.3.0")
        XCTAssertEqual(first.archiveName, "Pop-0.3.0.zip")
        XCTAssertEqual(first.archiveURL?.absoluteString, "https://example.com/v0.3.0/Pop-0.3.0.zip")
        XCTAssertEqual(first.checksumsURL?.absoluteString, "https://example.com/v0.3.0/SHA256SUMS.txt")
        XCTAssertEqual(first.archiveSize, 1234)
        XCTAssertNotNil(first.publishedAt)
        XCTAssertTrue(first.canInstall)
        XCTAssertFalse(first.isPrerelease)
        XCTAssertTrue(list[1].isPrerelease)

        let single = try XCTUnwrap(UpdateChecker.parseReleases(data(release("v1.0.0"))))
        XCTAssertEqual(single.map(\.version), ["1.0.0"])
        XCTAssertNil(UpdateChecker.parseReleases(Data("not json".utf8)))
    }

    func testSkipsDraftsAndReleasesWithoutChecksums() throws {
        let list = try XCTUnwrap(UpdateChecker.parseReleases(data([
            release("v0.4.0", draft: true),
            release("v0.2.0", assets: ["Pop-VERSION.zip"]),
        ])))
        XCTAssertEqual(list.map(\.version), ["0.2.0"])
        // 旧版本只有压缩包、没有校验文件：能看到，但不能在 Pop 里直接安装
        XCTAssertFalse(list[0].canInstall)
    }

    func testPrefersArchiveWithVersionInName() throws {
        let list = try XCTUnwrap(UpdateChecker.parseReleases(data([
            release("v0.3.0", assets: ["Pop-old.zip", "Pop-VERSION.zip", "SHA256SUMS.txt", "notes.txt"]),
        ])))
        XCTAssertEqual(list.first?.archiveName, "Pop-0.3.0.zip")
    }

    func testNewestRespectsPrereleaseSetting() throws {
        let list = try XCTUnwrap(UpdateChecker.parseReleases(data([
            release("v0.2.0"),
            release("v0.4.0-beta.1", prerelease: true),
            release("v0.3.0", prerelease: true),
            release("v0.1.0"),
        ])))
        XCTAssertEqual(UpdateChecker.newest(list, includePrereleases: true)?.version, "0.4.0-beta.1")
        XCTAssertEqual(UpdateChecker.newest(list, includePrereleases: false)?.version, "0.2.0")
        XCTAssertNil(UpdateChecker.newest([], includePrereleases: true))
    }

    @MainActor
    func testStableChannelDefaultAndExistingBetaPreference() {
        let name = "update-channel-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(Updater(defaults: defaults).includePrereleases)
        defaults.set(true, forKey: "pop.update.includePrereleases")
        XCTAssertTrue(Updater(defaults: defaults).includePrereleases)
    }

    func testUpdateNotificationsShareADailyLimitAcrossRestarts() {
        let name = "update-notification-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let first = ISO8601DateFormatter().date(from: "2026-10-06T15:00:00Z")!
        XCTAssertTrue(UpdateNotificationGate.claim(defaults: defaults, now: first, calendar: calendar))
        let restartedDefaults = UserDefaults(suiteName: name)!
        XCTAssertFalse(UpdateNotificationGate.claim(defaults: restartedDefaults, now: first.addingTimeInterval(60), calendar: calendar))
        XCTAssertTrue(UpdateNotificationGate.claim(defaults: restartedDefaults, now: first.addingTimeInterval(3600), calendar: calendar))
    }

    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("0.3.0", than: "0.2.9"))
        XCTAssertTrue(UpdateChecker.isNewer("0.69.0-beta.10", than: "0.69.0-beta.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.69.0-beta.2", than: "0.69.0-beta.10"))
        XCTAssertTrue(UpdateChecker.isNewer("0.69.0-rc.1", than: "0.69.0-beta.100"))
        XCTAssertFalse(UpdateChecker.isNewer("0.69.0-beta.1+build.2", than: "0.69.0-beta.1+build.1"))
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertTrue(UpdateChecker.isNewer("v1.0", than: "0.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0", than: "1.0.0-beta"))
        XCTAssertTrue(UpdateChecker.isNewer("9.9.9", than: "0.0.0-ci"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0-beta", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.2.0", than: "0.2.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.2", than: "0.2.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.1.9", than: "0.2.0"))
    }
}

final class UpdateInstallerTests: XCTestCase {
    func testChecksumsParsing() {
        let hash = String(repeating: "a", count: 64)
        let other = String(repeating: "B", count: 64)
        let parsed = Checksums.parse("\(hash)  Pop-0.3.0.zip\n\(other) *Pop 0.3.0.zip\nbad line\n1234  short.zip\n")
        XCTAssertEqual(parsed, ["Pop-0.3.0.zip": hash, "Pop 0.3.0.zip": other.lowercased()])
    }

    func testChecksumOfFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "pop-checksum-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(try Checksums.sha256(of: url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testInstallPlan() {
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let personal = URL(fileURLWithPath: "/Users/me/Applications", isDirectory: true)
        let folders = [applications, personal]
        let installed = URL(fileURLWithPath: "/Applications/Pop.app", isDirectory: true)

        // 平时：原地替换
        XCTAssertEqual(InstallLocation.plan(bundle: installed, translocated: false, original: nil, readOnly: false,
                                            folders: folders, canWrite: { _ in true }),
                       InstallPlan(target: installed, trashAfter: nil, relocating: false))

        // 在「应用程序」里但带着隔离标记被搬到临时位置运行：还是原地替换原来的位置
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Pop.app", isDirectory: true)
        XCTAssertEqual(InstallLocation.plan(bundle: translocated, translocated: true, original: installed, readOnly: true,
                                            folders: folders, canWrite: { _ in true }),
                       InstallPlan(target: installed, trashAfter: nil, relocating: false))

        // 在下载文件夹里直接打开：装进能写的「应用程序」，旧的那份移到废纸篓
        let downloaded = URL(fileURLWithPath: "/Users/me/Downloads/Pop.app", isDirectory: true)
        XCTAssertEqual(InstallLocation.plan(bundle: translocated, translocated: true, original: downloaded, readOnly: true,
                                            folders: folders, canWrite: { $0 == personal }),
                       InstallPlan(target: personal.appendingPathComponent("Pop.app", isDirectory: true),
                                   trashAfter: downloaded, relocating: true))

        // 不是 .app（比如直接跑测试宿主以外的二进制）：没法更新
        XCTAssertNil(InstallLocation.plan(bundle: URL(fileURLWithPath: "/usr/local/bin/pop"), translocated: false, original: nil,
                                          readOnly: false, folders: folders, canWrite: { _ in true }))
    }

    func testQuoting() {
        XCTAssertEqual(UpdateInstaller.shellQuote("/Applications/Pop's.app"), "'/Applications/Pop'\\''s.app'")
        XCTAssertEqual(UpdateInstaller.appleScriptString("say \"hi\" \\ bye"), "\"say \\\"hi\\\" \\\\ bye\"")
    }

    func testErrorClassification() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                             userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))])
        XCTAssertTrue(UpdateInstaller.needsAdmin(denied))
        XCTAssertFalse(UpdateInstaller.isBlockedBySystem(denied))
        let blocked = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                              userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        XCTAssertTrue(UpdateInstaller.isBlockedBySystem(blocked))
        XCTAssertFalse(UpdateInstaller.needsAdmin(blocked))
    }

    func testReleaseNotesRendering() {
        let rendered = String(ReleaseDetails.render("## 0.3.0\n\n### 新增\n\n- **一键更新**：从 GitHub 下载\n* 第二条").characters)
        XCTAssertTrue(rendered.contains("新增"))
        XCTAssertFalse(rendered.contains("###"))
        XCTAssertTrue(rendered.contains("• 一键更新：从 GitHub 下载"))
        XCTAssertTrue(rendered.contains("• 第二条"))
    }
}
