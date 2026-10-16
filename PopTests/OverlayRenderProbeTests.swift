import XCTest
@testable import Pop

final class OverlayRenderProbeTests: XCTestCase {
    func testFullPrefixAlsoRequiresDedicatedDemoAndKnownVariant() {
        var env = ["POP_RENDER_PROBE_WORKLOAD": "full-prefix"]
        XCTAssertNil(OverlayRenderProbe.workload(in: env))
        env["POP_DEMO"] = "1"
        XCTAssertNil(OverlayRenderProbe.workload(in: env))
        env["POP_RENDER_PROBE"] = "1"
        XCTAssertNil(OverlayRenderProbe.workload(in: env))
        env["POP_RENDER_PROBE_VARIANT"] = "baseline"
        XCTAssertEqual(OverlayRenderProbe.workload(in: env), .fullPrefix)
        env["POP_RENDER_PROBE_WORKLOAD"] = "typo"
        XCTAssertNil(OverlayRenderProbe.workload(in: env))
        env.removeValue(forKey: "POP_RENDER_PROBE_WORKLOAD")
        XCTAssertEqual(OverlayRenderProbe.workload(in: env), .isolated)
    }

    func testExperimentsRequireBothDedicatedAndDemoOptIn() {
        for variant in ["baseline", "no-ghost", "legacy-glass", "native-emoji"] {
            XCTAssertNil(OverlayRenderProbe.selected(in: ["POP_RENDER_PROBE_VARIANT": variant]))
            XCTAssertNil(OverlayRenderProbe.selected(in: ["POP_DEMO": "1", "POP_RENDER_PROBE_VARIANT": variant]))
            XCTAssertNil(OverlayRenderProbe.selected(in: ["POP_RENDER_PROBE": "1", "POP_RENDER_PROBE_VARIANT": variant]))
            XCTAssertEqual(OverlayRenderProbe.selected(in: ["POP_DEMO": "1", "POP_RENDER_PROBE": "1", "POP_RENDER_PROBE_VARIANT": variant])?.rawValue, variant)
        }
        XCTAssertNil(OverlayRenderProbe.selected(in: ["POP_DEMO": "1", "POP_RENDER_PROBE": "1", "POP_RENDER_PROBE_VARIANT": "typo"]))
    }
}
