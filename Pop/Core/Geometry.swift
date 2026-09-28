import CoreGraphics
import Foundation

/// 圆盘菜单的几何计算。0 号格在正上方，按顺时针编号。
struct RingGeometry: Equatable {
    var slotCount: Int
    /// 中心死区半径：指针在这个范围内不选中任何格子
    var innerRadius: CGFloat = 38
    var outerRadius: CGFloat = 124

    /// 格子多于 8 个时加大半径，避免相邻格子的文字挤在一起。
    static func outerRadius(forSlotCount count: Int) -> CGFloat {
        124 + CGFloat(max(count - 8, 0)) * 12
    }

    var diameter: CGFloat { outerRadius * 2 }
    var labelRadius: CGFloat { (innerRadius + outerRadius) / 2 }
    var slotStep: CGFloat { 2 * .pi / CGFloat(max(slotCount, 1)) }

    /// 第 index 格中心相对圆心的偏移（数学坐标系，y 轴向上）。
    func slotCenterOffset(_ index: Int, radius: CGFloat? = nil) -> CGVector {
        let r = radius ?? labelRadius
        let angle = CGFloat.pi / 2 - CGFloat(index) * slotStep
        return CGVector(dx: cos(angle) * r, dy: sin(angle) * r)
    }

    /// 指针相对圆心的偏移（y 轴向上）指向哪一格；落在中心死区内时返回 nil。
    /// 只看方向不看距离，所以按住右键往某个方向一划就能选中（marking menu）。
    func slot(at offset: CGVector) -> Int? {
        guard slotCount > 0 else { return nil }
        let distance = (offset.dx * offset.dx + offset.dy * offset.dy).squareRoot()
        guard distance >= innerRadius else { return nil }
        var theta = CGFloat.pi / 2 - atan2(offset.dy, offset.dx)
        theta = theta.truncatingRemainder(dividingBy: 2 * .pi)
        if theta < 0 { theta += 2 * .pi }
        return Int((theta + slotStep / 2) / slotStep) % slotCount
    }

    /// 第 index 格扇区在 SwiftUI 坐标系（y 轴向下，角度从 x 正方向顺时针）里的起止角度（度）。
    func sectorDegrees(_ index: Int) -> (start: Double, end: Double) {
        let step = 360.0 / Double(max(slotCount, 1))
        let center = -90.0 + Double(index) * step
        return (center - step / 2, center + step / 2)
    }
}

enum ScreenGeometry {
    /// Quartz 全局坐标（主屏左上角为原点，y 向下）转成 AppKit 屏幕坐标（主屏左下角为原点，y 向上）。
    static func appKitPoint(fromQuartz point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// 把矩形平移到 bounds 内；矩形比 bounds 还大时居中。
    static func clamp(_ rect: CGRect, within bounds: CGRect) -> CGRect {
        var result = rect
        if result.width >= bounds.width {
            result.origin.x = bounds.midX - result.width / 2
        } else {
            result.origin.x = min(max(result.origin.x, bounds.minX), bounds.maxX - result.width)
        }
        if result.height >= bounds.height {
            result.origin.y = bounds.midY - result.height / 2
        } else {
            result.origin.y = min(max(result.origin.y, bounds.minY), bounds.maxY - result.height)
        }
        return result
    }

    /// 以 center 为圆心的圆盘窗口位置，靠近屏幕边缘时整体往里挪。
    static func ringFrame(center: CGPoint, diameter: CGFloat, within bounds: CGRect) -> CGRect {
        let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        return clamp(rect, within: bounds)
    }

    /// 结果卡片默认放在指针右下方；右边放不下放左边，下面放不下放上面（AppKit 坐标，y 向上）。
    static func cardFrame(anchor: CGPoint, size: CGSize, within bounds: CGRect, gap: CGFloat = 14) -> CGRect {
        var x = anchor.x + gap
        if x + size.width > bounds.maxX {
            x = anchor.x - gap - size.width
        }
        var y = anchor.y - gap - size.height
        if y < bounds.minY {
            y = anchor.y + gap
        }
        return clamp(CGRect(x: x, y: y, width: size.width, height: size.height), within: bounds)
    }
}
