import XCTest
@testable import Pop

final class SmokeTests: XCTestCase {
    func testHostLaunches() {
        XCTAssertNotNil(NSApplication.shared.delegate)
    }
}
