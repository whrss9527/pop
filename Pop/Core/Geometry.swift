import CoreGraphics
import Foundation

/// 圆盘菜单的几何计算。默认 0 号格在正上方，按顺时针编号。
struct RingGeometry: Equatable {
    var slotCount: Int
    /// 中心死区半径：指针在这个范围内不选中任何格子。
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    /// 扇形的起始边界和张角：SwiftUI 坐标系，顺时针为正；不传时保持完整圆盘。
    var arcStartDegrees: Double?
    var arcSweepDegrees: Double?
    private var labelRadiusOverride: CGFloat?

    init(slotCount: Int, innerRadius: CGFloat = 38, outerRadius: CGFloat = 124,
         arcStartDegrees: Double? = nil, arcSweepDegrees: Double? = nil, labelRadius: CGFloat? = nil) {
        self.slotCount = slotCount
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.arcStartDegrees = arcStartDegrees
        self.arcSweepDegrees = arcSweepDegrees
        labelRadiusOverride = labelRadius
    }

    /// 格子多于 8 个时加大半径，避免相邻格子的文字挤在一起。
    static func outerRadius(forSlotCount count: Int) -> CGFloat {
        124 + CGFloat(max(count - 8, 0)) * 12
    }

    var diameter: CGFloat { outerRadius * 2 }
    var labelRadius: CGFloat { labelRadiusOverride ?? (innerRadius + outerRadius) / 2 }
    var sweepDegrees: Double { min(max(arcSweepDegrees ?? 360, 0), 360) }
    var isFullCircle: Bool { sweepDegrees >= 360 }
    var slotStep: CGFloat { CGFloat(sweepDegrees) * .pi / 180 / CGFloat(max(slotCount, 1)) }
    private var stepDegrees: Double { sweepDegrees / Double(max(slotCount, 1)) }
    var startDegrees: Double { arcStartDegrees ?? (-90 - stepDegrees / 2) }

    /// 第 index 格中心相对唤起点的偏移（AppKit 坐标系，y 轴向上）。
    func slotCenterOffset(_ index: Int, radius: CGFloat? = nil) -> CGVector {
        let r = radius ?? labelRadius
        let angle = CGFloat(slotCenterDegrees(index)) * .pi / 180
        return CGVector(dx: cos(angle) * r, dy: -sin(angle) * r)
    }

    /// 指针相对唤起点的偏移（y 轴向上）指向哪一格；中心死区和扇形之外都不选中。
    /// 不限制最大距离，所以按住鼠标划出圆盘以后仍然可以选中原来的方向。
    func slot(at offset: CGVector) -> Int? {
        guard slotCount > 0, sweepDegrees > 0, offset.dx.isFinite, offset.dy.isFinite else { return nil }
        let distance = hypot(offset.dx, offset.dy)
        guard distance >= innerRadius else { return nil }
        let angle = Double(atan2(-offset.dy, offset.dx)) * 180 / .pi
        let relative = Self.normalizedDegrees(angle - startDegrees)
        guard isFullCircle || relative < sweepDegrees else { return nil }
        return min(Int(relative / stepDegrees), slotCount - 1)
    }

    /// 第 index 格扇区在 SwiftUI 坐标系里的起止角度（度）。绘制和命中检测共用同一组边界。
    func sectorDegrees(_ index: Int) -> (start: Double, end: Double) {
        let start = startDegrees + Double(index) * stepDegrees
        return (start, start + stepDegrees)
    }

    /// 第 index 格中心的角度（度，SwiftUI 坐标系）。
    func slotCenterDegrees(_ index: Int) -> Double {
        startDegrees + (Double(index) + 0.5) * stepDegrees
    }

    /// 完整圆盘保留原来的高亮；边缘扇形的高亮直径至少 44 点，避免目标缩小。
    var highlightRadius: CGFloat {
        let chord = 2 * labelRadius * sin(slotStep / 2)
        if isFullCircle {
            return max(min(chord * 0.47, (outerRadius - innerRadius) / 2 - 4), 12)
        }
        return max(min(chord * 0.47, 34), 22)
    }

    /// 外圈高亮使用当前扇区的宽度，不能再按整圆平均分配。
    var highlightArcSpanDegrees: Double { min(stepDegrees * 0.62, 42) }

    /// 角度 angle 换成离 reference 最近的等价角度，高亮滑动时总走近的那一边。
    static func continuousAngle(_ angle: Double, near reference: Double) -> Double {
        angle + 360 * ((reference - angle) / 360).rounded()
    }

    fileprivate static func normalizedDegrees(_ angle: Double) -> Double {
        let result = angle.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}

/// 一次唤起的不可变布局。窗口可以裁到可用屏幕范围，唤起点和方向计算始终不变。
struct RingPlacement: Equatable {
    let geometry: RingGeometry
    let frame: CGRect
    let anchor: CGPoint
    let safeFrame: CGRect
    let visibleSlotCount: Int
    let hasOverflow: Bool

    static let padding: CGFloat = 22
    static let labelSize = CGSize(width: 66, height: 40)
    /// 预留文字悬停放大后的空间，不缩小图标、文字或点击目标。
    static let safeLabelSize = CGSize(width: 80, height: 52)
    static let maximumLabelRadius: CGFloat = 260
    /// 96 点为 80×52 标签的对角线留出余量，每个标签完整落在自己的扇区内。
    static let minimumCenterSpacing: CGFloat = 96

    init(slotCount: Int, anchor: CGPoint, safeFrame: CGRect) {
        let count = max(slotCount, 1)
        let full = RingGeometry(slotCount: count, outerRadius: RingGeometry.outerRadius(forSlotCount: count))
        let fullFrame = Self.windowFrame(anchor: anchor, radius: full.outerRadius)
        self.anchor = anchor
        self.safeFrame = safeFrame
        if safeFrame.contains(fullFrame) {
            geometry = full
            frame = fullFrame
            visibleSlotCount = count
            hasOverflow = false
            return
        }

        // 先尝试显示全部格子，再逐个减少；最后一个位置由视图模型替换成「更多」。
        for visibleCount in stride(from: count, through: 1, by: -1) {
            if let adapted = Self.adaptiveGeometry(count: visibleCount, anchor: anchor, safeFrame: safeFrame) {
                geometry = adapted
                frame = Self.windowFrame(anchor: anchor, radius: adapted.outerRadius).intersection(safeFrame)
                visibleSlotCount = visibleCount
                hasOverflow = visibleCount < count
                return
            }
        }

        // 极小的可用区域只保留一个入口。只要区域能容纳标签，就把完整标签留在区域内。
        // 小于标签本身的区域无法同时满足不缩小和不裁切，由窗口的可用区域决定最终裁切。
        let compact = Self.compactGeometry(anchor: anchor, safeFrame: safeFrame)
        geometry = compact
        let clipped = Self.windowFrame(anchor: anchor, radius: compact.outerRadius).intersection(safeFrame)
        frame = clipped.isNull ? safeFrame : clipped
        visibleSlotCount = 1
        hasOverflow = count > 1
    }

    /// 第 index 个标签的屏幕矩形，默认包含悬停放大所需空间。
    func labelFrame(_ index: Int, hoverSafe: Bool = true) -> CGRect {
        let offset = geometry.slotCenterOffset(index)
        let size = hoverSafe ? Self.safeLabelSize : Self.labelSize
        return CGRect(x: anchor.x + offset.dx - size.width / 2, y: anchor.y + offset.dy - size.height / 2,
                      width: size.width, height: size.height)
    }

    private static func windowFrame(anchor: CGPoint, radius: CGFloat) -> CGRect {
        let reach = radius + padding
        return CGRect(x: anchor.x - reach, y: anchor.y - reach, width: reach * 2, height: reach * 2)
    }

    private static func adaptiveGeometry(count: Int, anchor: CGPoint, safeFrame: CGRect) -> RingGeometry? {
        guard safeFrame.width >= safeLabelSize.width, safeFrame.height >= safeLabelSize.height else { return nil }
        // 固定步长、固定优先级让同一个位置每次唤起都得到相同的排列。
        let radii = stride(from: CGFloat(88), through: maximumLabelRadius, by: CGFloat(4)).map { $0 }
            + [maximumLabelRadius]
        let inward = RingGeometry.normalizedDegrees(Double(atan2(anchor.y - safeFrame.midY, safeFrame.midX - anchor.x)) * 180 / .pi)
        for radius in radii {
            let spacing = minimumCenterSpacing
            let step = Double(2 * asin(spacing / (2 * radius))) * 180 / .pi
            let sweep = step * Double(count)
            // 边缘布局只朝屏幕内展开，外侧的方向始终可以取消。
            guard sweep <= 180 else { continue }
            var candidate = RingGeometry(slotCount: count, outerRadius: radius + 50,
                                         arcStartDegrees: 0, arcSweepDegrees: sweep, labelRadius: radius)
            let labelBounds = safeFrame.insetBy(dx: safeLabelSize.width / 2 + 0.5,
                                               dy: max(safeLabelSize.height / 2, candidate.highlightRadius + 1) + 0.5)
            let labelArcs = allowedArcs(radius: radius, anchor: anchor, bounds: labelBounds)
            // 每个可选方向都必须在标签圆周上落进可用区域，不能只检查标签中心。
            let sectorArcs = allowedArcs(radius: radius, anchor: anchor, bounds: safeFrame)
            // 外圈描边宽 3 点，阴影半径 5 点，合计向边缘预留 7 点。
            let rimArcs = allowedArcs(radius: candidate.outerRadius - 5, anchor: anchor,
                                      bounds: safeFrame.insetBy(dx: 7.5, dy: 7.5))
            let rimHalfSpan = candidate.highlightArcSpanDegrees / 2
            let centerSpan = step * Double(count - 1)
            var best: (angle: Double, distance: Double)?
            for labels in labelArcs {
                for rim in rimArcs {
                    for turn in -1...1 {
                        let labelAndRimStart = max(labels.start, rim.start + Double(turn) * 360 + rimHalfSpan)
                        let labelAndRimEnd = min(labels.end, rim.end + Double(turn) * 360 - rimHalfSpan)
                        for sector in sectorArcs {
                            for sectorTurn in -1...1 {
                                let start = max(labelAndRimStart, sector.start + Double(sectorTurn) * 360 + step / 2)
                                let end = min(labelAndRimEnd, sector.end + Double(sectorTurn) * 360 - step / 2)
                                guard end - start >= centerSpan else { continue }
                                let low = start + centerSpan / 2
                                let high = end - centerSpan / 2
                                let desired = RingGeometry.continuousAngle(inward, near: (low + high) / 2)
                                let angle = min(max(desired, low), high)
                                let distance = abs(angle - desired)
                                if best == nil || distance < best!.distance {
                                    best = (angle, distance)
                                }
                            }
                        }
                    }
                }
            }
            if let best {
                candidate.arcStartDegrees = best.angle - sweep / 2
                return candidate
            }
        }
        return nil
    }

    private struct AngularInterval {
        var start: Double
        var end: Double
    }

    /// 求一个圆周落在矩形内的所有连续角度区间；跨过 0° 的区间保持连贯。
    /// 只在圆与矩形边界的交点处分段，无角度采样误差，也不依赖屏幕缩放比例。
    private static func allowedArcs(radius: CGFloat, anchor: CGPoint, bounds: CGRect) -> [AngularInterval] {
        guard radius > 0, !bounds.isEmpty else { return [] }
        var boundaries: [Double] = [0, 360]
        for x in [bounds.minX - anchor.x, bounds.maxX - anchor.x] where abs(x) <= radius {
            let angle = Double(acos(x / radius)) * 180 / .pi
            boundaries += [angle, 360 - angle]
        }
        for y in [bounds.minY - anchor.y, bounds.maxY - anchor.y] where abs(y) <= radius {
            let angle = Double(asin(-y / radius)) * 180 / .pi
            boundaries += [RingGeometry.normalizedDegrees(angle), RingGeometry.normalizedDegrees(180 - angle)]
        }
        boundaries.sort()
        var intervals: [AngularInterval] = []
        for index in 0..<(boundaries.count - 1) {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end - start > 0.000_000_1 else { continue }
            let angle = CGFloat((start + end) / 2) * .pi / 180
            let point = CGPoint(x: anchor.x + cos(angle) * radius, y: anchor.y - sin(angle) * radius)
            guard bounds.contains(point) else { continue }
            if let last = intervals.last, abs(last.end - start) < 0.000_000_1 {
                intervals[intervals.count - 1].end = end
            } else {
                intervals.append(AngularInterval(start: start, end: end))
            }
        }
        if intervals.count > 1, intervals.first!.start == 0, intervals.last!.end == 360 {
            let first = intervals.removeFirst()
            intervals[intervals.count - 1].end = first.end + 360
        }
        // 整个圆都放得下时，0° 不是边界，不能因预留高亮宽度而排除这个方向。
        if intervals.count == 1, intervals[0].start == 0, intervals[0].end == 360 {
            return [AngularInterval(start: -360, end: 720)]
        }
        return intervals
    }

    private static func compactGeometry(anchor: CGPoint, safeFrame: CGRect) -> RingGeometry {
        let insetX = min(safeLabelSize.width / 2, safeFrame.width / 2)
        let insetY = min(safeLabelSize.height / 2, safeFrame.height / 2)
        let bounds = safeFrame.insetBy(dx: insetX, dy: insetY)
        // 选择离唤起点最远的可用标签中心，尽可能让唯一入口落在 38 点死区之外。
        let points = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                      CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY)]
        let point = points.max {
            hypot($0.x - anchor.x, $0.y - anchor.y) < hypot($1.x - anchor.x, $1.y - anchor.y)
        } ?? CGPoint(x: safeFrame.midX, y: safeFrame.midY)
        let radius = hypot(point.x - anchor.x, point.y - anchor.y)
        let angle = Double(atan2(anchor.y - point.y, point.x - anchor.x)) * 180 / .pi
        return RingGeometry(slotCount: 1, outerRadius: radius + 50, arcStartDegrees: angle - 30,
                            arcSweepDegrees: 60, labelRadius: radius)
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
