import Foundation
import XCTest
@testable import Pop

@MainActor
final class OverlayDiagnosticsTests: XCTestCase {
    func testRequiresBothDemoAndExplicitDiagnosticPath() {
        XCTAssertNil(OverlayDiagnostics.requestedPath(environment: [:]))
        XCTAssertNil(OverlayDiagnostics.requestedPath(environment: ["POP_DEMO": "1"]))
        XCTAssertNil(OverlayDiagnostics.requestedPath(environment: ["POP_OVERLAY_DIAGNOSTICS_LOG": "/tmp/log"]))
        XCTAssertNil(OverlayDiagnostics.requestedPath(environment: ["POP_DEMO": "1", "POP_OVERLAY_DIAGNOSTICS_LOG": ""]))
        XCTAssertEqual(OverlayDiagnostics.requestedPath(environment: ["POP_DEMO": "1", "POP_OVERLAY_DIAGNOSTICS_LOG": "/tmp/log"]), "/tmp/log")
    }

    func testRawGeometryAndGhostLifecycleRemainOrdered() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pop-overlay-diag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("overlay.jsonl")
        let diagnostics = OverlayDiagnostics(path: file.path)
        let initial = CGRect(x: -4, y: 6, width: 404, height: 160)
        let actual = CGRect(x: -4, y: 6, width: 476, height: 440)
        diagnostics.record(.ghostCreated, window: 7, frame: initial, ghosts: 1)
        diagnostics.record(.initialFrameApplied, window: 0, frame: initial, ghosts: 1)
        diagnostics.record(.resizeApplied, window: 0, frame: actual, ghosts: 1)
        diagnostics.record(.ghostFinished, window: 7, frame: initial, ghosts: 0)
        await diagnostics.flush()
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        let entries = try lines.map { try JSONDecoder().decode(OverlayDiagnostics.Entry.self, from: Data($0.utf8)) }
        XCTAssertEqual(entries.map(\.sequence), [1, 2, 3, 4])
        XCTAssertEqual(entries.map(\.event), [.ghostCreated, .initialFrameApplied, .resizeApplied, .ghostFinished])
        XCTAssertEqual(entries.map(\.ghosts), [1, 1, 1, 0])
        XCTAssertEqual(entries.map(\.window), [7, 0, 0, 7])
        XCTAssertEqual(entries[2].width, 476)
        XCTAssertEqual(entries[2].height, 440)
        XCTAssertEqual(entries[2].x, -4)
        XCTAssertTrue(entries.allSatisfy { $0.time > 0 })
    }

    func testDisabledDiagnosticsDoNotReadWindowState() {
        let diagnostics = OverlayDiagnostics(path: nil)
        var reads = 0
        func frame() -> CGRect { reads += 1; return .zero }
        func ghosts() -> Int { reads += 1; return 0 }
        diagnostics.record(.presentBegin, window: 0, frame: frame(), ghosts: ghosts())
        XCTAssertEqual(reads, 0)
    }
}
