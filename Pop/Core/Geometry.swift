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
        let center = slotCenterDegrees(index)
        return (center - step / 2, center + step / 2)
    }

    /// 第 index 格中心的角度（度，SwiftUI 坐标系）：0 号格在正上方，也就是 -90°。
    func slotCenterDegrees(_ index: Int) -> Double {
        -90.0 + Double(index) * 360.0 / Double(max(slotCount, 1))
    }

    /// 指向某一格时，衬在它下面的那块圆形高亮的半径：不碰到相邻的格子，也不超出圆环。
    var highlightRadius: CGFloat {
        let chord = 2 * labelRadius * sin(slotStep / 2)
        return max(min(chord * 0.47, (outerRadius - innerRadius) / 2 - 4), 12)
    }

    /// 角度 angle 换成离 reference 最近的等价角度（加减 360 的整数倍），高亮滑动时总走近的那一边。
    static func continuousAngle(_ angle: Double, near reference: Double) -> Double {
        angle + 360 * ((reference - angle) / 360).rounded()
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

    // MARK: - 贴图

    /// 按比例缩小到 maxSize 以内；本来就放得下时不变。
    static func fitted(_ size: CGSize, within maxSize: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return size }
        let ratio = min(1, maxSize.width / size.width, maxSize.height / size.height)
        return CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
    }

    /// 以 point 为中心的贴图位置，超出屏幕时往里挪。
    static func pinFrame(size: CGSize, centeredAt point: CGPoint, within bounds: CGRect) -> CGRect {
        clamp(CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
              within: bounds)
    }

    /// 刚框选完的截图：框选通常是从左上拖到右下，松开时指针在右下角，贴图就盖在原来的位置上。
    static func pinFrame(size: CGSize, bottomRightAt point: CGPoint, within bounds: CGRect) -> CGRect {
        clamp(CGRect(x: point.x - size.width, y: point.y, width: size.width, height: size.height), within: bounds)
    }

    /// 缩放贴图：换成 size 大小，point（屏幕坐标）在贴图上的相对位置保持不变，这样以指针为中心放大缩小。
    static func resized(_ frame: CGRect, to size: CGSize, keeping point: CGPoint) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return CGRect(origin: frame.origin, size: size) }
        let relativeX = min(max((point.x - frame.minX) / frame.width, 0), 1)
        let relativeY = min(max((point.y - frame.minY) / frame.height, 0), 1)
        return CGRect(x: (point.x - size.width * relativeX).rounded(), y: (point.y - size.height * relativeY).rounded(),
                      width: size.width, height: size.height)
    }
}
