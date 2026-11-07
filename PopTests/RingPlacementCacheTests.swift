import XCTest
@testable import Pop

final class RingPlacementCacheTests: XCTestCase {
    private let safeFrame = CGRect(x: 0, y: 0, width: 1000, height: 650)

    private func key(ids: [String?] = ["first", "second", "third", "fourth"], count: Int = 4,
                     frame: CGRect? = nil, exclusions: [CGRect] = [], scale: CGFloat = 2) -> RingPlacementCache.Key {
        .init(configuredSlotIDs: ids, slotCount: count, safeFrame: frame ?? safeFrame,
              excludedFrames: exclusions, displayScale: scale)
    }

    func testNearbyInvocationReusesOnlyMostRecentOrder() {
        let placement = RingPlacement(slotCount: 4, anchor: CGPoint(x: 500, y: 325), safeFrame: safeFrame)
        var cache = RingPlacementCache()
        XCTAssertNil(cache.preferredDisplayOrder(for: key(), anchor: placement.anchor))
        cache.record(placement, for: key())
        XCTAssertEqual(cache.preferredDisplayOrder(for: key(), anchor: CGPoint(x: 500.5, y: 325)), placement.displayOrder)
    }

    func testNeighborhoodUsesActualButtonDimensions() {
        let placement = RingPlacement(slotCount: 4, anchor: CGPoint(x: 500, y: 325), safeFrame: safeFrame)
        let reach = max(placement.buttonSize.width, placement.buttonSize.height)
        var cache = RingPlacementCache()
        cache.record(placement, for: key())
        XCTAssertEqual(cache.preferredDisplayOrder(for: key(), anchor: CGPoint(x: 500 + reach, y: 325)), placement.displayOrder)
        XCTAssertNil(cache.preferredDisplayOrder(for: key(), anchor: CGPoint(x: 500 + reach + 0.5, y: 325)))
        XCTAssertNil(cache.preferredDisplayOrder(for: key(), anchor: CGPoint(x: 500 + reach, y: 325 + reach)))
    }

    func testRecordingAdvancesReferenceAnchorForContinuousPreview() {
        let first = RingPlacement(slotCount: 4, anchor: CGPoint(x: 400, y: 325), safeFrame: safeFrame)
        let reach = max(first.buttonSize.width, first.buttonSize.height)
        let secondAnchor = CGPoint(x: 400 + reach * 0.75, y: 325)
        let second = RingPlacement(slotCount: 4, anchor: secondAnchor, safeFrame: safeFrame)
        var cache = RingPlacementCache()
        cache.record(first, for: key())
        XCTAssertNotNil(cache.preferredDisplayOrder(for: key(), anchor: secondAnchor))
        cache.record(second, for: key())
        XCTAssertNotNil(cache.preferredDisplayOrder(for: key(), anchor: CGPoint(x: 400 + reach * 1.5, y: 325)))
    }

    func testConfigurationScreenExclusionAndScaleChangesDoNotReuse() {
        let placement = RingPlacement(slotCount: 4, anchor: CGPoint(x: 500, y: 325), safeFrame: safeFrame)
        var cache = RingPlacementCache()
        cache.record(placement, for: key())
        let changed = [
            key(ids: ["second", "first", "third", "fourth"]),
            key(ids: ["first", "second", "third", nil]),
            key(count: 8),
            key(frame: safeFrame.offsetBy(dx: -1000, dy: 0)),
            key(exclusions: [CGRect(x: 420, y: 618, width: 160, height: 32)]),
            key(scale: 1)
        ]
        for candidate in changed {
            XCTAssertNil(cache.preferredDisplayOrder(for: candidate, anchor: placement.anchor))
        }
    }

    func testClearAndReplacementKeepOnlyOneEntry() {
        let placement = RingPlacement(slotCount: 4, anchor: CGPoint(x: 500, y: 325), safeFrame: safeFrame)
        let original = key()
        let replacement = key(ids: [nil, "second", "third", "fourth"])
        var cache = RingPlacementCache()
        cache.record(placement, for: original)
        cache.record(placement, for: replacement)
        XCTAssertNil(cache.preferredDisplayOrder(for: original, anchor: placement.anchor))
        XCTAssertNotNil(cache.preferredDisplayOrder(for: replacement, anchor: placement.anchor))
        cache.clear()
        XCTAssertNil(cache.preferredDisplayOrder(for: replacement, anchor: placement.anchor))
    }

    func testAdjacentCornerInvocationsKeepCutWhileCapacityFits() {
        let ids: [String?] = (0..<8).map { "slot-\($0)" }
        let configuration = key(ids: ids, count: 8)
        let first = RingPlacement(slotCount: 8, anchor: CGPoint(x: 0.5, y: 0), safeFrame: safeFrame, displayScale: 2)
        var cache = RingPlacementCache()
        cache.record(first, for: configuration)
        let nextAnchor = CGPoint(x: 0, y: 0.5)
        let next = RingPlacement(slotCount: 8, anchor: nextAnchor, safeFrame: safeFrame, displayScale: 2,
                                 preferredDisplayOrder: cache.preferredDisplayOrder(for: configuration, anchor: nextAnchor))
        XCTAssertEqual(next.displayOrder, first.displayOrder)
        for slotID in first.displayOrder {
            let old = first.labelFrame(first.displayOrder.firstIndex(of: slotID)!, hoverSafe: false)
            let new = next.labelFrame(next.displayOrder.firstIndex(of: slotID)!, hoverSafe: false)
            XCTAssertLessThan(hypot(new.midX - old.midX, new.midY - old.midY), 4)
        }
    }
}
