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
        let math = settings.rules.first { $0.condition == .math }
        XCTAssertEqual(math?.enabled, false)
        XCTAssertEqual(math?.pluginID, BuiltinPluginID.calculate)
        XCTAssertEqual(settings.rules.count, RuleCondition.allCases.count)
        XCTAssertEqual(settings.rules.map(\.condition), DirectRule.defaults.map(\.condition))
    }

    /// 0.1 版保存的规则：新条件按默认顺序插进去（单个词要排在外文前面才有意义），已有规则保持原样。
    func testLegacyRulesGainNewConditionsInOrder() throws {
        let settings = try decode(#"""
        {"rules": [
            {"condition": "foreignText", "pluginID": "translate", "enabled": false},
            {"condition": "chineseText", "pluginID": "translate", "enabled": true},
            {"condition": "url", "pluginID": "openURL", "enabled": false},
            {"condition": "email", "pluginID": "openURL", "enabled": false},
            {"condition": "math", "pluginID": "calculate", "enabled": true},
            {"condition": "timestamp", "pluginID": "timestamp", "enabled": false},
            {"condition": "json", "pluginID": "formatJSON", "enabled": false},
            {"condition": "files", "pluginID": "copyPath", "enabled": false},
            {"condition": "image", "enabled": false},
            {"condition": "anyText", "pluginID": "translate", "enabled": false}
        ]}
        """#)
        XCTAssertEqual(settings.rules.map(\.condition), DirectRule.defaults.map(\.condition))
        XCTAssertEqual(settings.rules.first { $0.condition == .foreignText }?.enabled, false)
        XCTAssertEqual(settings.rules.first { $0.condition == .chineseText }?.enabled, true)
        let image = settings.rules.first { $0.condition == .image }
        XCTAssertNil(image?.pluginID)
        XCTAssertEqual(image?.enabled, false)
    }

    /// 0.1 版的设置里没有新功能：读取时自动装上，但用户自己卸载过的不会被装回来。
    func testLegacySettingsAdoptNewBuiltinPlugins() throws {
        let legacy = BuiltinPluginID.legacy.filter { $0 != BuiltinPluginID.search }
        let json = #"{"installedPlugins": ["# + legacy.map { "\"\($0)\"" }.joined(separator: ", ") + "]}"
        let settings = try decode(json)
        XCTAssertFalse(settings.isInstalled(BuiltinPluginID.search))
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.dictionary))
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.clipboardHistory))
        XCTAssertEqual(Set(settings.knownBuiltinPlugins), Set(BuiltinPluginID.all))

        var current = AppSettings()
        current.setInstalled(BuiltinPluginID.speak, false)
        let roundTripped = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current))
        XCTAssertFalse(roundTripped.isInstalled(BuiltinPluginID.speak))
    }

    /// 没改过圆盘布局的老用户换成新的默认布局；改过的保持不变。
    func testLegacyDefaultRingIsUpgraded() throws {
        let legacySlots = RingLayout.legacyDefault.slots.map { $0.map { "\"\($0)\"" } ?? "null" }.joined(separator: ", ")
        let upgraded = try decode(#"{"ring": {"slots": ["# + legacySlots + "]}}")
        XCTAssertEqual(upgraded.ring, RingLayout.default)

        let custom = try decode(#"{"ring": {"slots": ["search", null, "translate", null]}}"#)
        XCTAssertEqual(custom.ring.slots, [BuiltinPluginID.search, nil, BuiltinPluginID.translate, nil])

        // 新版本保存的设置里即使恰好是旧布局，也是用户自己选的，不再改动
        var current = AppSettings()
        current.ring = .legacyDefault
        let roundTripped = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current))
        XCTAssertEqual(roundTripped.ring, RingLayout.legacyDefault)
    }

    func testClipboardSettingsDecoding() throws {
        let settings = try decode(#"{"clipboard": {"enabled": false, "retentionDays": -3, "maxItems": 1, "hotKey": "fromTheFuture"}}"#)
        XCTAssertFalse(settings.clipboard.enabled)
        XCTAssertEqual(settings.clipboard.retentionDays, 0)
        XCTAssertEqual(settings.clipboard.maxItems, 10)
        XCTAssertEqual(settings.clipboard.hotKey, ClipboardSettings().hotKey)
        XCTAssertEqual(settings.clipboard.ignoredBundleIDs, ClipboardSettings.defaultIgnoredBundleIDs)
    }

    func testRingPlacementSwapsAndClears() {
        var ring = RingLayout.default
        ring.place(BuiltinPluginID.search, at: 0)
        XCTAssertEqual(ring.slots[0], BuiltinPluginID.search)
        XCTAssertEqual(ring.slots[1], BuiltinPluginID.translate)

        ring.place(BuiltinPluginID.settings, at: 2)
        XCTAssertEqual(ring.slots[2], BuiltinPluginID.settings)
        XCTAssertNil(ring.index(of: BuiltinPluginID.dictionary))

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
