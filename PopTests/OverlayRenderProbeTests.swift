import XCTest
@testable import Pop

final class OverlayRenderProbeTests: XCTestCase {
    func testExperimentsRequireBothDedicatedAndDemoOptIn() {
        for variant in ["baseline", "no-ghost", "legacy-glass"] {
            XCTAssertNil(OverlayRenderProbe.selected(in: ["POP_RENDER_PROBE_VARIANT": variant]))
            XCTAssertNil(OverlayRenderProbe.selected(in: ["POP_DEMO": "1", "POP_RENDER_PROBE_VARIANT": variant]))
            XCTAssertNil(OverlayRenderProbe.selected(in: ["POP_RENDER_PROBE": "1", "POP_RENDER_PROBE_VARIANT": variant]))
            XCTAssertEqual(OverlayRenderProbe.selected(in: ["POP_DEMO": "1", "POP_RENDER_PROBE": "1", "POP_RENDER_PROBE_VARIANT": variant])?.rawValue, variant)
        }
        XCTAssertNil(OverlayRenderProbe.selected(in: ["POP_DEMO": "1", "POP_RENDER_PROBE": "1", "POP_RENDER_PROBE_VARIANT": "typo"]))
    }
}
