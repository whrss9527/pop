import CoreGraphics
import XCTest
@testable import Pop

@MainActor
final class MouseWheelTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "PopMouseWheelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    /// 一格一格的鼠标滚轮事件（continuous 为 true 时像触控板、妙控鼠标那样连续）
    private func scroll(_ vertical: Int32, _ horizontal: Int32, continuous: Bool = false) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        return event
    }

    /// 上下：行数、定点数、像素；左右：行数、定点数、像素
    private func deltas(_ event: CGEvent) -> [Double] {
        [Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)), event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
         Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),
         Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)), event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
         Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))]
    }

    // MARK: - 改滚动事件

    func testReversesAndSpeedsUpWheelEvents() throws {
        XCTAssertFalse(WheelOptions().isActive)
        XCTAssertTrue(WheelOptions(reverseVertical: true).isActive)
        XCTAssertTrue(WheelOptions(reverseHorizontal: true).isActive)
        XCTAssertTrue(WheelOptions(speed: 2).isActive)

        // 上下反过来，左右不动
        let event = try scroll(3, -2)
        let before = deltas(event)
        XCTAssertEqual(before[0], 3)
        XCTAssertEqual(before[3], -2)
        XCTAssertTrue(WheelAdjust.isWheel(event))
        XCTAssertTrue(WheelAdjust.apply(WheelOptions(reverseVertical: true), to: event))
        XCTAssertEqual(deltas(event), [-before[0], -before[1], -before[2], before[3], before[4], before[5]])

        // 左右也反过来、两倍速
        let both = try scroll(1, 4)
        let original = deltas(both)
        XCTAssertTrue(WheelAdjust.apply(WheelOptions(reverseVertical: true, reverseHorizontal: true, speed: 2), to: both))
        XCTAssertEqual(deltas(both), original.map { -2 * $0 })
        XCTAssertEqual(both.getIntegerValueField(.scrollWheelEventDeltaAxis1), -2)
        XCTAssertEqual(both.getIntegerValueField(.scrollWheelEventDeltaAxis2), -8)

        // 只调速度：方向不变
        let faster = try scroll(-2, 0)
        XCTAssertTrue(WheelAdjust.apply(WheelOptions(speed: 3), to: faster))
        XCTAssertEqual(faster.getIntegerValueField(.scrollWheelEventDeltaAxis1), -6)
    }

    func testLeavesTrackpadsAndOtherEventsAlone() throws {
        // 触控板、妙控鼠标的滚动是连续的：不改
        let trackpad = try scroll(3, 1, continuous: true)
        let before = deltas(trackpad)
        XCTAssertFalse(WheelAdjust.isWheel(trackpad))
        XCTAssertFalse(WheelAdjust.apply(WheelOptions(reverseVertical: true, speed: 2), to: trackpad))
        XCTAssertEqual(deltas(trackpad), before)
        // 什么都不改的设置：不碰事件
        let wheel = try scroll(3, 1)
        XCTAssertFalse(WheelAdjust.apply(WheelOptions(), to: wheel))
        XCTAssertEqual(wheel.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3)
        // 不是滚动事件
        let key = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        XCTAssertFalse(WheelAdjust.isWheel(key))
        XCTAssertFalse(WheelAdjust.apply(WheelOptions(reverseVertical: true), to: key))
    }

    // MARK: - 设置和卡片

    func testSettingsStatusAndPermission() {
        let defaults = freshDefaults()
        var trusted = true
        let wheel = MouseWheel(defaults: defaults, isLive: false, isTrusted: { trusted })
        XCTAssertFalse(wheel.options.isActive)
        XCTAssertFalse(wheel.isRunning)
        XCTAssertEqual(wheel.statusText, "没开：鼠标滚轮按系统设置滚动")

        wheel.setReverse(true)
        XCTAssertTrue(wheel.isRunning)
        XCTAssertEqual(wheel.statusText, "正在调整鼠标滚轮：上下反过来")
        wheel.setSpeed(2)
        XCTAssertEqual(wheel.statusText, "正在调整鼠标滚轮：上下反过来，2 倍速")
        wheel.setReverseHorizontal(true)
        XCTAssertEqual(wheel.statusText, "正在调整鼠标滚轮：上下、左右都反过来，2 倍速")
        // 不在几档里的速度不要
        wheel.setSpeed(7)
        XCTAssertEqual(wheel.options.speed, 2)
        // 设置都记住
        XCTAssertEqual(MouseWheel(defaults: defaults, isLive: false, isTrusted: { true }).options,
                       WheelOptions(reverseVertical: true, reverseHorizontal: true, speed: 2))

        // 只调速度；什么都不改时不拦
        wheel.setReverse(false)
        wheel.setReverseHorizontal(false)
        XCTAssertEqual(wheel.statusText, "正在调整鼠标滚轮：2 倍速")
        wheel.setReverseHorizontal(true)
        XCTAssertEqual(wheel.statusText, "正在调整鼠标滚轮：左右反过来，2 倍速")
        wheel.setReverseHorizontal(false)
        wheel.setSpeed(1)
        XCTAssertFalse(wheel.isRunning)
        XCTAssertEqual(MouseWheel.speedTitle(1), "系统的速度")
        XCTAssertEqual(MouseWheel.speedTitle(3), "3 倍速")

        // 没有辅助功能权限：说一声，给了以后接着生效
        trusted = false
        wheel.setReverse(true)
        XCTAssertTrue(wheel.needsPermission)
        XCTAssertFalse(wheel.isRunning)
        XCTAssertEqual(wheel.statusText, "要先在「系统设置 → 隐私与安全性 → 辅助功能」里允许 Pop，才能调整鼠标滚轮")
        trusted = true
        wheel.startIfNeeded()
        XCTAssertFalse(wheel.needsPermission)
        XCTAssertTrue(wheel.isRunning)

        // 卸载时设置一起删掉了，又装上：按存着的来
        wheel.shutDown()
        XCTAssertFalse(wheel.isRunning)
        defaults.removeObject(forKey: MouseWheel.reverseKey)
        wheel.startIfNeeded()
        XCTAssertFalse(wheel.options.isActive)
        XCTAssertFalse(wheel.isRunning)
        // 存的速度不在几档里：用系统的
        defaults.set(5, forKey: MouseWheel.speedKey)
        XCTAssertEqual(MouseWheel(defaults: defaults, isLive: false, isTrusted: { true }).options.speed, 1)
    }

    func testDirectionHintFollowsNaturalScrolling() {
        let defaults = freshDefaults()
        let wheel = MouseWheel(defaults: defaults, isLive: false, isTrusted: { true })
        defaults.set(true, forKey: "com.apple.swipescrolldirection")
        XCTAssertTrue(WheelAdjust.naturalScrolling(defaults))
        XCTAssertTrue(wheel.directionHint.hasPrefix("系统开着「自然滚动」"))
        defaults.set(false, forKey: "com.apple.swipescrolldirection")
        XCTAssertFalse(WheelAdjust.naturalScrolling(defaults))
        XCTAssertTrue(wheel.directionHint.hasPrefix("系统关着「自然滚动」"))
    }

    func testPluginAndDemo() {
        XCTAssertTrue(MouseWheelPlugin().info.canHandle(.empty))
        XCTAssertEqual(Set(MouseWheel.defaultsKeys), Set(PluginCatalog.packages.first { $0.id == "mouseWheel" }?.defaultsKeys ?? []))
        let demo = MouseWheel.demo()
        XCTAssertTrue(demo.isRunning)
        XCTAssertEqual(demo.statusText, "正在调整鼠标滚轮：上下反过来，2 倍速")
    }
}
