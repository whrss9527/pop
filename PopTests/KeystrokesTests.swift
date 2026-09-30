import CoreGraphics
import XCTest
@testable import Pop

final class KeystrokesTests: XCTestCase {
    func testWritesShortcutsInMenuOrder() {
        XCTAssertEqual(Keystrokes.text(keyCode: 8, flags: .maskCommand, character: "c"), "⌘C")
        XCTAssertEqual(Keystrokes.text(keyCode: 21, flags: [.maskCommand, .maskShift], character: "4"), "⇧⌘4")
        XCTAssertEqual(Keystrokes.text(keyCode: 3, flags: [.maskCommand, .maskControl, .maskAlternate], character: "f"), "⌃⌥⌘F")
        XCTAssertEqual(Keystrokes.text(keyCode: 8, flags: .maskControl, character: "c"), "⌃C")
        // 法语键盘上美式 A 的位置是 Q
        XCTAssertEqual(Keystrokes.text(keyCode: 0, flags: .maskCommand, character: "q"), "⌘Q")
        // 读不到键盘布局时按美式键盘
        XCTAssertEqual(Keystrokes.text(keyCode: 6, flags: .maskCommand, character: nil), "⌘Z")
        XCTAssertEqual(Keystrokes.text(keyCode: 6, flags: .maskCommand, character: ""), "⌘Z")
    }

    func testHidesOrdinaryTyping() {
        XCTAssertNil(Keystrokes.text(keyCode: 0, flags: [], character: "a"))
        XCTAssertNil(Keystrokes.text(keyCode: 0, flags: .maskShift, character: "a"))
        XCTAssertNil(Keystrokes.text(keyCode: 21, flags: .maskShift, character: "4"))
        // ⌥ 能打出特殊字符，也是在打字
        XCTAssertNil(Keystrokes.text(keyCode: 14, flags: .maskAlternate, character: "e"))
        XCTAssertNil(Keystrokes.text(keyCode: 49, flags: [], character: " "))
        XCTAssertNil(Keystrokes.text(keyCode: 49, flags: .maskShift, character: " "))
    }

    func testShowsSpecialKeys() {
        XCTAssertEqual(Keystrokes.text(keyCode: 36, flags: [], character: "\r"), "↩")
        XCTAssertEqual(Keystrokes.text(keyCode: 53, flags: [], character: "\u{1B}"), "⎋")
        XCTAssertEqual(Keystrokes.text(keyCode: 48, flags: .maskShift, character: "\t"), "⇧⇥")
        XCTAssertEqual(Keystrokes.text(keyCode: 51, flags: .maskAlternate, character: nil), "⌥⌫")
        XCTAssertEqual(Keystrokes.text(keyCode: 49, flags: .maskCommand, character: " "), "⌘␣")
        XCTAssertEqual(Keystrokes.text(keyCode: 122, flags: .maskSecondaryFn, character: nil), "F1")
        // 方向键自带「数字小键盘」和 fn 的标记，不算修饰键
        XCTAssertEqual(Keystrokes.text(keyCode: 126, flags: [.maskNumericPad, .maskSecondaryFn], character: nil), "↑")
        XCTAssertEqual(Keystrokes.text(keyCode: 123, flags: [.maskAlternate, .maskShift, .maskNumericPad], character: nil), "⌥⇧←")
    }

    func testCountsTheSameShortcutPressedAgain() {
        var display = Keystrokes.next(after: nil, text: "⌘Z", at: 10)
        XCTAssertEqual(display.label, "⌘Z")
        display = Keystrokes.next(after: display, text: "⌘Z", at: 10.8)
        display = Keystrokes.next(after: display, text: "⌘Z", at: 12.2)
        XCTAssertEqual(display.label, "⌘Z ×3")
        // 隔得久了重新数
        display = Keystrokes.next(after: display, text: "⌘Z", at: 14)
        XCTAssertEqual(display.label, "⌘Z")
        // 换了组合也重新数
        display = Keystrokes.next(after: display, text: "⇧⌘Z", at: 14.2)
        XCTAssertEqual(display, Keystrokes.Display(text: "⇧⌘Z", count: 1, time: 14.2))
    }

    @MainActor
    func testPluginNeedsNoContent() {
        let info = ShowKeystrokesPlugin().info
        XCTAssertTrue(info.canHandle(.empty))
        XCTAssertFalse(info.hidesOverlay)
    }
}
