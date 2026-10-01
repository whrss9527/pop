import AppKit
import XCTest
@testable import Pop

@MainActor
final class OverlayComposingTests: XCTestCase {
    func testComposingTextKeepsKeysForTheInputMethod() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        let field = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView?.addSubview(field)
        try XCTSkipUnless(window.makeFirstResponder(field), "这个环境里窗口拿不到焦点")
        XCTAssertFalse(OverlayController.isComposing(in: window))
        field.setMarkedText("xiao", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(OverlayController.isComposing(in: window))
        field.unmarkText()
        XCTAssertFalse(OverlayController.isComposing(in: window))
    }
}
