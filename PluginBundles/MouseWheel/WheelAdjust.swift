import CoreGraphics
import Foundation
@testable import Pop

/// 鼠标滚轮怎么改：上下反不反、左右反不反、几倍速
struct WheelOptions: Equatable {
    var reverseVertical = false
    var reverseHorizontal = false
    /// 1 是系统的速度，2、3 是两倍、三倍
    var speed = 1

    /// 有要改的才拦滚动事件
    var isActive: Bool {
        reverseVertical || reverseHorizontal || speed != 1
    }
}

/// 改滚动事件：只改一格一格的鼠标滚轮；触控板、妙控鼠标的滚动是连续的，照旧
enum WheelAdjust {
    static func isWheel(_ event: CGEvent) -> Bool {
        event.type == .scrollWheel && event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
    }

    /// 按设置改一个滚动事件，返回改没改
    @discardableResult
    static func apply(_ options: WheelOptions, to event: CGEvent) -> Bool {
        guard options.isActive, isWheel(event) else { return false }
        let speed = max(1, options.speed)
        let vertical = (options.reverseVertical ? -1 : 1) * speed
        let horizontal = (options.reverseHorizontal ? -1 : 1) * speed
        // 行数、像素、定点数三种写法都改（不同的 App 读不同的那个）；先全读出来再写，免得写一个时另外两个跟着变
        let lines = (event.getIntegerValueField(.scrollWheelEventDeltaAxis1), event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        let points = (event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        let fixed = (event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: lines.0 * Int64(vertical))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: lines.1 * Int64(horizontal))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed.0 * Double(vertical))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed.1 * Double(horizontal))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: points.0 * Int64(vertical))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: points.1 * Int64(horizontal))
        return true
    }

    /// 系统设置里开没开「自然滚动」（没设过时是开着的）
    static func naturalScrolling(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    }
}
