import Combine
import XCTest
@testable import Pop

final class SettingsCodingTests: XCTestCase {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.searchEngine = .baidu
        settings.trigger.mode = .middleClick
        settings.ring.place(BuiltinPluginID.settings, at: 3)
        settings.modifiedAt = Date(timeIntervalSinceReferenceDate: 12345.678)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }

    func testEmptyJSONDecodesToDefaults() throws {
        XCTAssertEqual(try decode("{}"), AppSettings())
    }

    /// 新版本加的枚举值、越界的数值不能让旧数据整体解码失败。
    func testUnknownValuesFallBackToDefaults() throws {
        let settings = try decode(#"{"trigger": {"mode": "fromTheFuture", "holdDuration": 5, "hotKey": "optionSpace"}, "searchEngine": "yahoo"}"#)
        XCTAssertEqual(settings.trigger.mode, TriggerSettings().mode)
        XCTAssertEqual(settings.trigger.holdDuration, TriggerSettings.holdDurationRange.upperBound)
        XCTAssertEqual(settings.trigger.hotKey, .optionSpace)
        XCTAssertEqual(settings.searchEngine, .google)
    }

    func testRulesAreNormalized() throws {
        let settings = try decode(#"{"rules": [{"condition": "math", "pluginID": "calculate", "enabled": false}, {"condition": "math", "enabled": true}]}"#)
        XCTAssertEqual(settings.rules.first?.condition, .math)
        XCTAssertEqual(settings.rules.first?.enabled, false)
        XCTAssertEqual(settings.rules.count, RuleCondition.allCases.count)
        XCTAssertEqual(Set(settings.rules.map(\.condition)), Set(RuleCondition.allCases))
    }

    func testRingPlacementSwapsAndClears() {
        var ring = RingLayout.default
        ring.place(BuiltinPluginID.search, at: 0)
        XCTAssertEqual(ring.slots[0], BuiltinPluginID.search)
        XCTAssertEqual(ring.slots[1], BuiltinPluginID.translate)

        ring.place(BuiltinPluginID.settings, at: 2)
        XCTAssertEqual(ring.slots[2], BuiltinPluginID.settings)
        XCTAssertNil(ring.index(of: BuiltinPluginID.openURL))

        ring.place(nil, at: 2)
        XCTAssertNil(ring.slots[2])
    }

    func testSlotCountPadsAndTruncates() {
        var ring = RingLayout.default
        ring.setSlotCount(4)
        XCTAssertEqual(ring.slots, Array(RingLayout.default.slots.prefix(4)))
        ring.setSlotCount(10)
        XCTAssertEqual(ring.slotCount, 10)
        XCTAssertEqual(ring.slots.suffix(6).compactMap { $0 }, [])
    }

    func testUninstallRemovesFromRing() {
        var settings = AppSettings()
        settings.setInstalled(BuiltinPluginID.translate, false)
        XCTAssertFalse(settings.isInstalled(BuiltinPluginID.translate))
        XCTAssertNil(settings.ring.index(of: BuiltinPluginID.translate))
        settings.setInstalled(BuiltinPluginID.translate, true)
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.translate))
    }

    func testSameContentIgnoresModifiedAt() {
        var a = AppSettings()
        var b = AppSettings()
        a.modifiedAt = Date()
        XCTAssertTrue(a.hasSameContent(as: b))
        b.searchEngine = .bing
        XCTAssertFalse(a.hasSameContent(as: b))
    }

    func testSearchURLEncodesQuery() {
        XCTAssertEqual(SearchEngine.google.searchURL(for: "a b&c")?.absoluteString, "https://www.google.com/search?q=a%20b%26c")
        XCTAssertEqual(SearchEngine.bing.searchURL(for: "C++")?.absoluteString, "https://www.bing.com/search?q=C%2B%2B")
        XCTAssertEqual(SearchEngine.baidu.searchURL(for: "翻译")?.absoluteString, "https://www.baidu.com/s?wd=%E7%BF%BB%E8%AF%91")
    }
}

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testUpdatePersistsAndPublishesLocalChanges() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pop.tests.\(UUID().uuidString)"))
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings.modifiedAt, .distantPast)

        var published: [AppSettings] = []
        let cancellable = store.localChanges.sink { published.append($0) }
        defer { cancellable.cancel() }

        store.update { $0.searchEngine = .bing }
        XCTAssertEqual(store.settings.searchEngine, .bing)
        XCTAssertGreaterThan(store.settings.modifiedAt, .distantPast)
        XCTAssertEqual(published.count, 1)

        // 内容没变：不记录修改、不触发同步
        let stamp = store.settings.modifiedAt
        store.update { $0.searchEngine = .bing }
        XCTAssertEqual(store.settings.modifiedAt, stamp)
        XCTAssertEqual(published.count, 1)

        XCTAssertEqual(SettingsStore(defaults: defaults).settings, store.settings)
    }

    @MainActor
    func testApplyRemoteDoesNotEcho() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pop.tests.\(UUID().uuidString)"))
        let store = SettingsStore(defaults: defaults)
        var published = 0
        let cancellable = store.localChanges.sink { _ in published += 1 }
        defer { cancellable.cancel() }

        var remote = AppSettings()
        remote.searchEngine = .duckDuckGo
        remote.modifiedAt = Date(timeIntervalSince1970: 1_800_000_000)
        store.applyRemote(remote)
        XCTAssertEqual(store.settings, remote)
        XCTAssertEqual(published, 0)
    }
}

final class SyncResolverTests: XCTestCase {
    private func settings(modifiedAt: Date, engine: SearchEngine = .google) -> AppSettings {
        var settings = AppSettings()
        settings.modifiedAt = modifiedAt
        settings.searchEngine = engine
        return settings
    }

    func testFreshInstallAdoptsCloudAndNeverOverwritesIt() {
        let fresh = AppSettings()
        XCTAssertEqual(SyncResolver.resolve(local: fresh, remote: nil), .none)
        XCTAssertEqual(SyncResolver.resolve(local: fresh, remote: settings(modifiedAt: Date(), engine: .bing)), .applyRemote)
    }

    func testLastWriterWins() {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(SyncResolver.resolve(local: settings(modifiedAt: newer), remote: nil), .pushLocal)
        XCTAssertEqual(SyncResolver.resolve(local: settings(modifiedAt: newer), remote: settings(modifiedAt: older)), .pushLocal)
        XCTAssertEqual(SyncResolver.resolve(local: settings(modifiedAt: older), remote: settings(modifiedAt: newer, engine: .bing)), .applyRemote)
        XCTAssertEqual(SyncResolver.resolve(local: settings(modifiedAt: older), remote: settings(modifiedAt: newer)), .none)
        XCTAssertEqual(SyncResolver.resolve(local: settings(modifiedAt: newer), remote: settings(modifiedAt: newer)), .none)
    }

    func testEnvelopeRoundTrip() throws {
        let envelope = SyncEnvelope(device: "MacBook", settings: settings(modifiedAt: Date(timeIntervalSince1970: 1_800_000_000)))
        let data = try JSONEncoder().encode(envelope)
        XCTAssertEqual(try JSONDecoder().decode(SyncEnvelope.self, from: data), envelope)
    }
}
