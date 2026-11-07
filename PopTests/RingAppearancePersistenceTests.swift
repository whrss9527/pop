import XCTest
@testable import Pop

final class RingAppearanceCodingTests: XCTestCase {
    private func decode(_ json: String) throws -> RingAppearance {
        try JSONDecoder().decode(RingAppearance.self, from: Data(json.utf8))
    }

    func testDefaultAndAllShapesRoundTrip() throws {
        XCTAssertEqual(RingAppearance.default.shape, .roundedRectangle)
        XCTAssertEqual(RingAppearance.default.scale, 1)
        XCTAssertEqual(Set(RingButtonShape.allCases.map(\.id)).count, 3)
        for shape in RingButtonShape.allCases {
            let appearance = RingAppearance(shape: shape, scale: 1.25)
            XCTAssertEqual(try JSONDecoder().decode(RingAppearance.self, from: JSONEncoder().encode(appearance)), appearance)
        }
    }

    func testUnknownShapeKeepsValidScale() throws {
        let value = try decode(#"{"shape":"future-shape","scale":1.3}"#)
        XCTAssertEqual(value, RingAppearance(scale: 1.3))
        XCTAssertEqual(try JSONDecoder().decode(RingButtonShape.self, from: Data(#""future-shape""#.utf8)), .roundedRectangle)
    }

    func testMalformedFieldsFallBackIndependently() throws {
        XCTAssertEqual(try decode(#"{"shape":"circle","scale":"large"}"#), RingAppearance(shape: .circle))
        XCTAssertEqual(try decode(#"{"shape":["circle"],"scale":1.4}"#), RingAppearance(scale: 1.4))
        for json in ["{}", "null", "[]", "17", #"{"shape":null,"scale":null}"#] {
            XCTAssertEqual(try decode(json), .default, json)
        }
    }

    func testFiniteScaleClampsAtPersistenceBoundary() throws {
        XCTAssertEqual(try decode(#"{"scale":-1}"#).scale, 0.8)
        XCTAssertEqual(try decode(#"{"scale":99}"#).scale, 1.6)
        for scale in [0.8, 1, 1.6] {
            XCTAssertEqual(RingAppearance(scale: scale).normalizedScale, scale)
        }
    }

    func testNonFiniteMutationCanStillBeSavedAsDefaultScale() throws {
        for scale in [Double.nan, .infinity, -.infinity] {
            var appearance = RingAppearance(shape: .square)
            appearance.scale = scale
            XCTAssertEqual(appearance.normalized, RingAppearance(shape: .square))
            XCTAssertEqual(try JSONDecoder().decode(RingAppearance.self, from: JSONEncoder().encode(appearance)),
                           RingAppearance(shape: .square))
        }
    }

    func testNonConformingFloatDecoderAlsoNormalizes() throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        for text in ["inf", "-inf", "nan"] {
            let data = Data("{\"shape\":\"circle\",\"scale\":\"\(text)\"}".utf8)
            XCTAssertEqual(try decoder.decode(RingAppearance.self, from: data), RingAppearance(shape: .circle))
        }
    }
}

final class RingLayoutAppearancePersistenceTests: XCTestCase {
    private func decode(_ json: String) throws -> RingLayout {
        try JSONDecoder().decode(RingLayout.self, from: Data(json.utf8))
    }

    func testLegacySlotOnlyLayoutGetsDefaultAppearanceAndNoAliases() throws {
        let layout = try decode(#"{"slots":["search",null,"translate",null]}"#)
        XCTAssertEqual(layout.slots, [BuiltinPluginID.search, nil, BuiltinPluginID.translate, nil])
        XCTAssertEqual(layout.appearance, .default)
        XCTAssertTrue(layout.customNames.isEmpty)
    }

    func testMalformedNewFieldsDoNotEraseSlotOrder() throws {
        for extra in [#""appearance":false,"customNames":[]"#, #""appearance":{"shape":7,"scale":{}},"customNames":42"#] {
            let layout = try decode("{\"slots\":[\"search\",null,\"translate\",null],\(extra)}")
            XCTAssertEqual(layout.slots, [BuiltinPluginID.search, nil, BuiltinPluginID.translate, nil])
            XCTAssertEqual(layout.appearance, .default)
            XCTAssertTrue(layout.customNames.isEmpty)
        }
    }

    func testMixedAliasDictionaryRetainsValidEntriesAndUnknownFunctionIDs() throws {
        let layout = try decode(#"{"slots":["search",null],"customNames":{"search":"  找一下\n","future.plugin":"Keep me","bad-number":12,"bad-object":{},"bad-array":[],"blank":"\n\t","null":null}}"#)
        XCTAssertEqual(layout.customNames, ["search": "找一下", "future.plugin": "Keep me"])
        XCTAssertEqual(layout.customDisplayName(for: "future.plugin"), "Keep me")
    }

    func testAliasSanitizationKeepsWholeGraphemesAndFunctionID() {
        let family = "👨‍👩‍👧‍👦"
        var layout = RingLayout(slots: ["external.plugin"])
        layout.setCustomName("  \n" + String(repeating: family, count: 45) + "\t ", for: "external.plugin")
        XCTAssertEqual(layout.customDisplayName(for: "external.plugin"), String(repeating: family, count: 40))
        XCTAssertEqual(layout.customDisplayName(for: "external.plugin")?.count, 40)
        XCTAssertEqual(layout.slots, ["external.plugin"])
        layout.setCustomName(String(repeating: "e\u{301}", count: 41), for: "external.plugin")
        XCTAssertEqual(layout.customDisplayName(for: "external.plugin"), String(repeating: "e\u{301}", count: 40))
    }

    func testControlCharactersAreRemovedWithoutLosingJoinedEmoji() {
        var layout = RingLayout(slots: ["search"])
        layout.setCustomName("\0  Work\nSearch\u{7F}\t👩‍💻  ", for: "search")
        XCTAssertEqual(layout.customDisplayName(for: "search"), "Work Search 👩‍💻")
        layout.setCustomName(" \0\n\t\u{200D} ", for: "search")
        XCTAssertNil(layout.customDisplayName(for: "search"))
        layout.setCustomName("Name", for: "search")
        layout.setCustomName(nil, for: "search")
        XCTAssertNil(layout.customNames["search"])
    }

    func testAliasFollowsFunctionAcrossSwapSlotRemovalAndCountChange() {
        var layout = RingLayout(slots: ["search", "translate", nil, nil], customNames: ["search": "Find", "translate": "Read"])
        layout.place("search", at: 1)
        XCTAssertEqual(layout.slots, ["translate", "search", nil, nil])
        XCTAssertEqual(layout.customDisplayName(for: "search"), "Find")
        layout.place(nil, at: 1)
        layout.remove("translate")
        layout.setSlotCount(1)
        XCTAssertEqual(layout.customNames, ["search": "Find", "translate": "Read"])
        layout.place("search", at: 0)
        XCTAssertEqual(layout.customDisplayName(for: "search"), "Find")
    }

    func testResetAppearanceDoesNotResetLayoutOrAliases() {
        var layout = RingLayout(slots: ["search", nil, "translate", nil], appearance: RingAppearance(shape: .square, scale: 1.5),
                                customNames: ["search": "Find"])
        let slots = layout.slots
        layout.resetAppearance()
        XCTAssertEqual(layout.appearance, .default)
        XCTAssertEqual(layout.slots, slots)
        XCTAssertEqual(layout.customDisplayName(for: "search"), "Find")
    }

    func testEncodingNormalizesDirectlyMutatedFields() throws {
        var layout = RingLayout(slots: ["search", nil])
        layout.appearance.scale = .infinity
        layout.customNames = ["search": "  Find  ", "future": String(repeating: "好", count: 45), "blank": "\n"]
        let saved = try JSONDecoder().decode(RingLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(saved.appearance, .default)
        XCTAssertEqual(saved.customNames, ["search": "Find", "future": String(repeating: "好", count: 40)])
    }

    func testPerAppOverridesAndUninstallRetainIndependentAliases() throws {
        var settings = AppSettings()
        settings.ring = RingLayout(slots: ["translate", nil], appearance: RingAppearance(shape: .circle, scale: 1.3),
                                   customNames: ["translate": "Global"])
        let override = RingLayout(slots: ["translate", "search"], appearance: RingAppearance(shape: .square, scale: 0.9),
                                  customNames: ["translate": "Editor"])
        settings.appRings = [AppRing(bundleID: "fixture.editor", layout: override)]
        XCTAssertEqual(settings.ring(for: "fixture.editor"), override)
        XCTAssertEqual(settings.ring(for: "other.app").customDisplayName(for: "translate"), "Global")
        settings.setInstalled("translate", false)
        XCTAssertNil(settings.ring.index(of: "translate"))
        XCTAssertNil(settings.ring(for: "fixture.editor").index(of: "translate"))
        XCTAssertEqual(settings.ring.customDisplayName(for: "translate"), "Global")
        XCTAssertEqual(settings.ring(for: "fixture.editor").customDisplayName(for: "translate"), "Editor")
        settings.setInstalled("translate", true)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.ring, settings.ring)
        XCTAssertEqual(decoded.appRings, settings.appRings)
    }

    func testCustomizedLegacySlotsAreNotReplacedByDefaultMigration() throws {
        let slots = try JSONSerialization.jsonObject(with: JSONEncoder().encode(RingLayout.legacyDefault.slots))
        let object: [String: Any] = ["ring": ["slots": slots, "appearance": ["shape": "circle", "scale": 1.2],
                                            "customNames": ["translate": "Read"]]]
        let settings = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(settings.ring.slots, RingLayout.legacyDefault.slots)
        XCTAssertEqual(settings.ring.appearance, RingAppearance(shape: .circle, scale: 1.2))
        XCTAssertEqual(settings.ring.customDisplayName(for: "translate"), "Read")
    }

    func testBackupRoundTripPreservesDefaultAndPerAppCustomization() throws {
        var settings = AppSettings()
        settings.modifiedAt = Date(timeIntervalSince1970: 1_800_000_000)
        settings.searchEngine = .duckDuckGo
        settings.trigger.keepsRingOpen = true
        settings.ring = RingLayout(slots: ["search", nil, "translate", nil], appearance: RingAppearance(shape: .circle, scale: 1.6),
                                   customNames: ["search": "Find", "future.plugin": "Retained"])
        settings.appRings = [AppRing(bundleID: "fixture.editor", layout: RingLayout(slots: ["translate", nil],
                                    appearance: RingAppearance(shape: .square, scale: 0.8), customNames: ["translate": "Read"]))]
        let backup = SettingsBackup(settings: settings, plugins: [], appVersion: "fixture", exportedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let restored = try SettingsBackup.decode(backup.encoded())
        XCTAssertEqual(restored.settings, settings)
        XCTAssertEqual(restored.settings.ring, settings.ring)
        XCTAssertEqual(restored.settings.appRings, settings.appRings)
        XCTAssertEqual(restored.appVersion, "fixture")
    }
}
