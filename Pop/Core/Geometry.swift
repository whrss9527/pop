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
    private var labelAnglesOverride: [Double]?
    private var sectorBoundariesOverride: [Double]?

    init(slotCount: Int, innerRadius: CGFloat = 38, outerRadius: CGFloat = 124,
         arcStartDegrees: Double? = nil, arcSweepDegrees: Double? = nil, labelRadius: CGFloat? = nil,
         labelAngles: [Double]? = nil, sectorBoundaries: [Double]? = nil) {
        self.slotCount = slotCount
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.arcStartDegrees = arcStartDegrees
        self.arcSweepDegrees = arcSweepDegrees
        labelRadiusOverride = labelRadius
        labelAnglesOverride = labelAngles?.count == slotCount ? labelAngles : nil
        sectorBoundariesOverride = sectorBoundaries?.count == slotCount + 1 ? sectorBoundaries : nil
    }

    /// 格子多于 8 个时加大半径，避免相邻格子的文字挤在一起。
    static func outerRadius(forSlotCount count: Int) -> CGFloat {
        124 + CGFloat(max(count - 8, 0)) * 12
    }

    var diameter: CGFloat { outerRadius * 2 }
    var labelRadius: CGFloat { labelRadiusOverride ?? (innerRadius + outerRadius) / 2 }
    var sweepDegrees: Double { min(max(arcSweepDegrees ?? 360, 0), 360) }
    var isFullCircle: Bool { sweepDegrees >= 360 }
    var slotStep: CGFloat {
        if let angles = labelAnglesOverride, angles.count > 1 {
            return CGFloat(angles[1] - angles[0]) * .pi / 180
        }
        return CGFloat(stepDegrees) * .pi / 180
    }
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
        // 相切按钮角落的三角函数往返可能比死区边界小几个浮点尾数。
        guard distance + 0.000_000_1 >= innerRadius else { return nil }
        let angle = Double(atan2(-offset.dy, offset.dx)) * 180 / .pi
        let relative = Self.normalizedDegrees(angle - startDegrees)
        guard isFullCircle || relative <= sweepDegrees + 0.000_000_1 else { return nil }
        if let boundaries = sectorBoundariesOverride {
            let position = startDegrees + min(relative, sweepDegrees)
            return (0..<slotCount).first { position < boundaries[$0 + 1] } ?? (slotCount - 1)
        }
        if labelAnglesOverride != nil {
            return (0..<slotCount).first { relative < sectorDegrees($0).end - startDegrees }
        }
        return min(Int(relative / stepDegrees), slotCount - 1)
    }

    /// 第 index 格扇区在 SwiftUI 坐标系里的起止角度（度）。绘制和命中检测共用同一组边界。
    func sectorDegrees(_ index: Int) -> (start: Double, end: Double) {
        if let boundaries = sectorBoundariesOverride {
            return (boundaries[index], boundaries[index + 1])
        }
        if let angles = labelAnglesOverride {
            let start = index == 0 ? startDegrees : (angles[index - 1] + angles[index]) / 2
            let end = index == slotCount - 1 ? startDegrees + sweepDegrees : (angles[index] + angles[index + 1]) / 2
            return (start, end)
        }
        let start = startDegrees + Double(index) * stepDegrees
        return (start, start + stepDegrees)
    }

    /// 第 index 格中心的角度（度，SwiftUI 坐标系）。
    func slotCenterDegrees(_ index: Int) -> Double {
        labelAnglesOverride?[index] ?? (startDegrees + (Double(index) + 0.5) * stepDegrees)
    }

    /// 图标周围的安全半径。
    var highlightRadius: CGFloat {
        let chord = 2 * labelRadius * sin(slotStep / 2)
        if isFullCircle {
            return max(min(chord * 0.47, (outerRadius - innerRadius) / 2 - 4), 12)
        }
        return max(min(chord * 0.47, 28), 22)
    }

    /// 外圈高亮使用当前扇区的宽度，不能再按整圆平均分配。
    var highlightArcSpanDegrees: Double {
        let compact = labelAnglesOverride != nil
        return min(Double(slotStep) * 180 / .pi * (compact ? 0.5 : 0.62), compact ? 32 : 42)
    }

    /// 角度 angle 换成离 reference 最近的等价角度，高亮滑动时总走近的那一边。
    static func continuousAngle(_ angle: Double, near reference: Double) -> Double {
        angle + 360 * ((reference - angle) / 360).rounded()
    }

    fileprivate static func normalizedDegrees(_ angle: Double) -> Double {
        let result = angle.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}

/// 按已发布整圆的弦长确定按钮尺寸；同次唤起靠边或溢出时不再改变字号和点击面积。
struct RingButtonMetrics: Equatable {
    let bodySize: CGSize
    let cornerRadius: CGFloat
    static let shadowMargin: CGFloat = 4
    static let gap: CGFloat = 4

    init(slotCount: Int, appearance: RingAppearance = .default) {
        let count = max(slotCount, 1)
        let original = RingGeometry(slotCount: count, outerRadius: RingGeometry.outerRadius(forSlotCount: count))
        let chord = 2 * original.labelRadius * sin(.pi / CGFloat(count))
        let originalWidth = min(60, max(36, chord - 12))
        let normalized = appearance.normalized
        let scale = CGFloat(normalized.normalizedScale)
        let width = max(36, originalWidth * scale)
        switch normalized.shape {
        case .roundedRectangle:
            bodySize = CGSize(width: width, height: max(36, min(54, originalWidth) * scale))
            cornerRadius = min(14, originalWidth * 0.28) * scale
        case .circle:
            bodySize = CGSize(width: width, height: width)
            cornerRadius = width / 2
        case .square:
            bodySize = CGSize(width: width, height: width)
            cornerRadius = 0
        }
    }
}

/// 一次唤起的不可变布局。物理角序与动作编号分开，裁剪窗口不会移动唤起点。
struct RingPlacement: Equatable {
    let geometry: RingGeometry
    let frame: CGRect
    let anchor: CGPoint
    let safeFrame: CGRect
    let excludedFrames: [CGRect]
    /// 布局求解和窗口对齐实际使用的比例，恢复旧布局时也按同一规则比较。
    let displayScale: CGFloat
    let appearance: RingAppearance
    let visibleSlotCount: Int
    let hasOverflow: Bool
    let buttonSize: CGSize
    /// 物理角序 → 可见候选动作数组索引；溢出时数组为原前缀加「更多」。
    let displayOrder: [Int]

    /// 只为窗口与动画留白，不参与能否保留整圆或多少项的判断。
    static let padding: CGFloat = 22
    private static let epsilon: CGFloat = 0.000_000_1
    private static let turn = Double.pi * 2
    private static let innerRadius: CGFloat = 38

    init(slotCount: Int, anchor: CGPoint, safeFrame: CGRect,
         excludedFrames: [CGRect] = [], displayScale: CGFloat = 1,
         preferredDisplayOrder: [Int]? = nil, appearance: RingAppearance = .default) {
        let count = max(slotCount, 1)
        let normalizedAppearance = appearance.normalized
        let metrics = RingButtonMetrics(slotCount: count, appearance: normalizedAppearance)
        let exclusions = excludedFrames.filter { Self.isFinite($0) && !$0.isEmpty }
        let scale = Self.normalizedDisplayScale(displayScale)
        self.anchor = anchor
        self.safeFrame = safeFrame
        self.excludedFrames = exclusions
        self.displayScale = scale
        self.appearance = normalizedAppearance
        buttonSize = metrics.bodySize

        let solver = Solver(anchor: anchor, bounds: safeFrame, exclusions: exclusions,
                            size: metrics.bodySize, scale: scale, originalCount: count,
                            preferredOrder: preferredDisplayOrder)
        let original = RingGeometry(slotCount: count, outerRadius: RingGeometry.outerRadius(forSlotCount: count))
        let originalAngles = (0..<count).map { original.slotCenterDegrees($0) * .pi / 180 }
        var solution: Solution?
        if Self.isFinite(safeFrame), safeFrame.width > 0, safeFrame.height > 0,
           anchor.x.isFinite, anchor.y.isFinite {
            // 真实按钮、死区与圆心都放得下时，保持已有完整圆盘；透明 padding 可以裁掉。
            if solver.hubFits(fullCircle: true) {
                solution = solver.solution(radius: original.labelRadius, angles: originalAngles, fullCircle: true,
                                           allowsPreferredOrder: false)
                if solution == nil {
                    solution = solver.regularCircle(originalRadius: original.labelRadius, angles: originalAngles)
                }
            }
            if solution == nil {
                for capacity in stride(from: count, through: 1, by: -1) {
                    if let found = solver.solve(count: capacity) {
                        solution = found
                        break
                    }
                }
            }
        }
        if let solution {
            geometry = solution.geometry
            visibleSlotCount = solution.geometry.slotCount
            hasOverflow = visibleSlotCount < count
            displayOrder = solution.order
            var content = solution.visualBounds
            if let hub = solver.hubFrame(fullCircle: solution.geometry.isFullCircle) {
                content = content.union(hub.insetBy(dx: -RingButtonMetrics.shadowMargin,
                                                   dy: -RingButtonMetrics.shadowMargin))
            }
            let padded = content.insetBy(dx: -Self.padding, dy: -Self.padding)
            frame = ScreenGeometry.pixelAlignedWindowFrame(padded, scale: scale).intersection(safeFrame)
        } else {
            // 真正小于按钮或没有可点方向的区域：保留一个原尺寸入口，窗口按物理边界裁剪。
            // 不能用缩小按钮、挪动逻辑锚点或 NaN 来伪装已经放下。
            let fallbackFrame = Self.isFinite(safeFrame) && safeFrame.width >= 0 && safeFrame.height >= 0
                ? safeFrame : .zero
            let point = CGPoint(x: fallbackFrame.midX, y: fallbackFrame.midY)
            let dx = anchor.x.isFinite ? point.x - anchor.x : 0
            let dy = anchor.y.isFinite ? point.y - anchor.y : 0
            let radius = hypot(dx, dy)
            let angle = radius > 0 ? Double(atan2(-dy, dx)) : -.pi / 2
            geometry = RingGeometry(slotCount: 1, outerRadius: max(1, radius + metrics.bodySize.width),
                                    arcStartDegrees: angle * 180 / .pi - 30, arcSweepDegrees: 60,
                                    labelRadius: radius, labelAngles: [angle * 180 / .pi])
            frame = fallbackFrame
            visibleSlotCount = 1
            hasOverflow = count > 1
            displayOrder = [0]
        }
    }

    /// 返回既有圆盘时校验同一套可用区域，不能再与扣除了菜单栏的 visibleFrame 比较。
    func matchesBoundary(safeFrame: CGRect, excludedFrames: [CGRect], displayScale: CGFloat) -> Bool {
        Self.isFinite(self.safeFrame) && !self.safeFrame.isEmpty &&
            self.safeFrame == safeFrame && self.excludedFrames == excludedFrames &&
            self.displayScale == Self.normalizedDisplayScale(displayScale)
    }

    private static func normalizedDisplayScale(_ scale: CGFloat) -> CGFloat {
        scale.isFinite && scale > 0 ? max(scale, 1) : 1
    }

    /// 标签的屏幕矩形。安全包络只包含当前实际阴影，不再包含不存在的弧带和圆头。
    func labelFrame(_ index: Int, hoverSafe: Bool = true) -> CGRect {
        let offset = geometry.slotCenterOffset(index)
        let body = CGRect(x: anchor.x + offset.dx - buttonSize.width / 2,
                          y: anchor.y + offset.dy - buttonSize.height / 2,
                          width: buttonSize.width, height: buttonSize.height)
        return hoverSafe ? body.insetBy(dx: -RingButtonMetrics.shadowMargin, dy: -RingButtonMetrics.shadowMargin) : body
    }

    /// 屏幕禁区中的实际指针点不能触发；划出菜单后仍按原唤起点的方向选择。
    func slot(at offset: CGVector) -> Int? {
        guard offset.dx.isFinite, offset.dy.isFinite else { return nil }
        let point = CGPoint(x: anchor.x + offset.dx, y: anchor.y + offset.dy)
        guard !excludedFrames.contains(where: { $0.contains(point) }) else { return nil }
        return geometry.slot(at: offset)
    }

    var hubFrame: CGRect? {
        Solver(anchor: anchor, bounds: safeFrame, exclusions: excludedFrames, size: buttonSize,
               scale: 1, originalCount: visibleSlotCount, preferredOrder: nil).hubFrame(fullCircle: geometry.isFullCircle)
    }

    /// 提示不是动作容量约束；暂不为可选提示扩大圆盘。
    var statusFrame: CGRect? { nil }

    private struct Interval {
        var start: Double
        var end: Double
    }

    private struct Solution {
        let geometry: RingGeometry
        let visualBounds: CGRect
        let order: [Int]
        let score: Double
    }

    private struct Solver {
        let anchor: CGPoint
        let bounds: CGRect
        let exclusions: [CGRect]
        let size: CGSize
        let scale: CGFloat
        let originalCount: Int
        let preferredOrder: [Int]?
        var half: CGSize { CGSize(width: size.width / 2, height: size.height / 2) }
        var collisionHalf: CGSize {
            CGSize(width: half.width + RingButtonMetrics.gap / 2,
                   height: half.height + RingButtonMetrics.gap / 2)
        }
        var centerBounds: CGRect {
            bounds.insetBy(dx: half.width + RingButtonMetrics.shadowMargin,
                           dy: half.height + RingButtonMetrics.shadowMargin)
        }

        func hubFrame(fullCircle: Bool) -> CGRect? {
            let radius = RingPlacement.innerRadius - 2
            let body = CGRect(x: anchor.x - radius, y: anchor.y - radius, width: radius * 2, height: radius * 2)
            let visual = body.insetBy(dx: -RingButtonMetrics.shadowMargin, dy: -RingButtonMetrics.shadowMargin)
            return fits(visual) ? body : nil
        }
        func hubFits(fullCircle: Bool) -> Bool { hubFrame(fullCircle: fullCircle) != nil }

        /// 正规圆盘保留默认方向。四角投影给出按钮完整落在自身扇区内的解析半径下界。
        func regularCircle(originalRadius: CGFloat, angles: [Double]) -> Solution? {
            solution(radius: regularRadius(originalRadius: originalRadius, angles: angles), angles: angles,
                     fullCircle: true, allowsPreferredOrder: false)
        }

        private func regularRadius(originalRadius: CGFloat, angles: [Double]) -> CGFloat {
            var radius = max(originalRadius, RingPlacement.innerRadius + min(half.width, half.height))
            if angles.count > 1 {
                let tangent = tan(.pi / Double(angles.count))
                for angle in angles {
                    for x in [-Double(collisionHalf.width), Double(collisionHalf.width)] {
                        for y in [-Double(collisionHalf.height), Double(collisionHalf.height)] {
                            let radial = x * cos(angle) + y * sin(angle)
                            let transverse = -x * sin(angle) + y * cos(angle)
                            radius = max(radius, CGFloat(abs(transverse) / tangent - radial))
                        }
                    }
                }
            }
            radius = ceil(radius * scale) / scale
            // 死区到矩形的距离沿固定射线单调增加；最多增到四角的径向安全界。
            let deadZoneSafe = RingPlacement.innerRadius + hypot(half.width, half.height)
            while angles.contains(where: { distanceToBody(bodyFrame(radius: radius, angle: $0))
                + RingPlacement.epsilon < RingPlacement.innerRadius }), radius < deadZoneSafe {
                radius += 1 / scale
            }
            return radius
        }

        func solve(count: Int) -> Solution? {
            let centers = centerBounds
            guard centers.width >= -RingPlacement.epsilon, centers.height >= -RingPlacement.epsilon else { return nil }
            let corners = [CGPoint(x: centers.minX, y: centers.minY), CGPoint(x: centers.maxX, y: centers.minY),
                           CGPoint(x: centers.maxX, y: centers.maxY), CGPoint(x: centers.minX, y: centers.maxY)]
            let maximum = corners.map { hypot($0.x - anchor.x, $0.y - anchor.y) }.max() ?? 0
            // 按钮包含这个内切圆，因此这是由可点面积推导的必要下界，不是样式半径。
            var minimum = RingPlacement.innerRadius + min(half.width, half.height)
            if count > 1 {
                minimum = max(minimum, min(collisionHalf.width, collisionHalf.height) / sin(.pi / CGFloat(count)))
            }
            guard maximum.isFinite, maximum + RingPlacement.epsilon >= minimum else { return nil }
            let reference = RingGeometry(slotCount: count, outerRadius: RingGeometry.outerRadius(forSlotCount: count))
            let nominal = (0..<count).map { -.pi / 2 + Double($0) * RingPlacement.turn / Double(count) }
            let preferredMinimum = max(minimum, regularRadius(originalRadius: reference.labelRadius, angles: nominal))
            // 自然方向优先于绝对最小半径，避免整圆恢复时密排布局整体旋转。
            // 这个下界与正规圆盘共用按钮四角计算；它不是容量限制。
            if preferredMinimum <= maximum + RingPlacement.epsilon {
                if let regular = search(count: count, from: preferredMinimum, through: maximum) { return regular }
                return search(count: count, from: minimum, through: min(maximum, preferredMinimum - 1 / scale))
            }
            // 首选半径范围没有解，仍补搜更小的真实像素，再允许减少动作数。
            return search(count: count, from: minimum, through: maximum)
        }

        private func search(count: Int, from minimum: CGFloat, through maximum: CGFloat) -> Solution? {
            guard minimum <= maximum + RingPlacement.epsilon else { return nil }
            let firstPixel = ceil(minimum * scale) / scale
            let lastPixel = floor(maximum * scale) / scale
            var radius = firstPixel
            while radius <= lastPixel + RingPlacement.epsilon {
                if let result = solve(count: count, radius: radius) { return result }
                radius += 1 / scale
            }
            // 小数屏幕边界或恰好只有一个中心点时，仍检查最后的真实相切位置。
            if maximum - lastPixel > RingPlacement.epsilon || firstPixel > maximum {
                return solve(count: count, radius: maximum)
            }
            return nil
        }

        private func solve(count: Int, radius: CGFloat) -> Solution? {
            let arcs = allowedArcs(radius: radius)
            guard !arcs.isEmpty else { return nil }
            let entireCircle = arcs.count == 1 && arcs[0].end - arcs[0].start >= RingPlacement.turn - 1e-9
            let full = entireCircle && hubFits(fullCircle: true)
            if count == originalCount {
                let nominal = (0..<count).map { -.pi / 2 + Double($0) * RingPlacement.turn / Double(count) }
                if full, let original = solution(radius: radius, angles: nominal, fullCircle: true,
                                                 allowsPreferredOrder: false) { return original }
            }
            var best: Solution?
            // 每个真实缺口都可作为展开切口；不选「最近边」，也不重新编号动作。
            for cut in arcs.indices {
                var domains: [Interval] = []
                for offset in 0..<arcs.count {
                    let index = (cut + offset) % arcs.count
                    let shift = index < cut ? RingPlacement.turn : 0
                    domains.append(Interval(start: arcs[index].start + shift, end: arcs[index].end + shift))
                }
                let first = domains[0]
                let pixelAngle = 1 / Double(scale * radius)
                var seed = first.start
                while seed <= first.end + 1e-9 {
                    let activeDomains = entireCircle
                        ? [Interval(start: seed, end: seed + RingPlacement.turn)] : domains
                    guard let packed = pack(count: count, radius: radius, firstAngle: seed, domains: activeDomains) else {
                        // 开放角区内最早放置已经放不完，再向后开始也不会多出空间。
                        break
                    }
                    if let candidate = solution(radius: radius, angles: packed, fullCircle: full) {
                        let adjusted = relaxing(candidate, radius: radius, arcs: arcs) ?? candidate
                        let closer = adjusted.score < candidate.score ? adjusted : candidate
                        if best == nil || closer.score < best!.score - 1e-9 { best = closer }
                    }
                    seed += pixelAngle
                }
                // 端点不一定恰好落在设备像素采样上，补上相切候选。
                if !entireCircle, let packed = pack(count: count, radius: radius, firstAngle: first.end, domains: domains),
                   let candidate = solution(radius: radius, angles: packed, fullCircle: false) {
                    let adjusted = relaxing(candidate, radius: radius, arcs: arcs) ?? candidate
                    let closer = adjusted.score < candidate.score ? adjusted : candidate
                    if best == nil || closer.score < best!.score - 1e-9 { best = closer }
                }
            }
            return best
        }

        /// 四角角域随中心角单调增加；让下个矩形完全越过前一个的末边界。
        /// 叉积给出解析解，避免每个按钮再做几十轮角度二分。
        private func pack(count: Int, radius: CGFloat, firstAngle: Double, domains: [Interval]) -> [Double]? {
            var angles: [Double] = []
            var next = firstAngle
            for _ in 0..<count {
                guard let domain = domains.first(where: { $0.end + 1e-9 >= next }) else { return nil }
                let angle = max(next, domain.start)
                guard angle <= domain.end + 1e-9 else { return nil }
                angles.append(angle)
                let end = footprint(radius: radius, angle: angle, half: collisionHalf).end
                let support = Double(collisionHalf.width) * abs(sin(end)) + Double(collisionHalf.height) * abs(cos(end))
                guard support < Double(radius) else { return nil }
                next = end + asin(support / Double(radius)) + 1e-10
            }
            return angles
        }

        func solution(radius: CGFloat, angles inputAngles: [Double], fullCircle: Bool,
                      allowsPreferredOrder: Bool = true) -> Solution? {
            var angles = inputAngles
            guard !angles.isEmpty else { return nil }
            var visuals: [CGRect] = []
            var footprints: [Interval] = []
            for angle in angles {
                let body = bodyFrame(radius: radius, angle: angle)
                let visual = body.insetBy(dx: -RingButtonMetrics.shadowMargin, dy: -RingButtonMetrics.shadowMargin)
                guard fits(visual), distanceToBody(body) + RingPlacement.epsilon >= RingPlacement.innerRadius else { return nil }
                visuals.append(visual)
                footprints.append(footprint(radius: radius, angle: angle, half: collisionHalf))
            }
            for index in 1..<footprints.count {
                guard footprints[index - 1].end <= footprints[index].start + 1e-9 else { return nil }
            }
            guard footprints.last!.end <= footprints[0].start + RingPlacement.turn + 1e-9 else { return nil }
            if !fullCircle, angles.count > 1 {
                // 同一组按钮可有多个角度切口；始终把最大的真实空隙留作取消方向。
                // 这里只循环旋转物理角序，后面的动作编号仍选择同 id 位移最小的一组。
                var largestGap = -Double.infinity
                var cut = 0
                for index in angles.indices {
                    let next = (index + 1) % angles.count
                    let gap = footprints[next].start + (next == 0 ? RingPlacement.turn : 0) - footprints[index].end
                    if gap > largestGap + 1e-9 { largestGap = gap; cut = next }
                }
                if cut != 0 {
                    angles = (angles.indices).map { position in
                        let index = (position + cut) % angles.count
                        return angles[index] + (index < cut ? RingPlacement.turn : 0)
                    }
                    footprints = angles.map { footprint(radius: radius, angle: $0, half: collisionHalf) }
                }
            }
            var boundaries = [fullCircle ? (footprints.last!.end - RingPlacement.turn + footprints[0].start) / 2
                                        : footprints[0].start]
            for index in 1..<footprints.count {
                boundaries.append((footprints[index - 1].end + footprints[index].start) / 2)
            }
            boundaries.append(fullCircle ? boundaries[0] + RingPlacement.turn : footprints.last!.end)
            var bestOrder = Array(angles.indices)
            var bestScore = Double.infinity
            let previous = allowsPreferredOrder ? validPreferredOrder(count: angles.count) : nil
            let orders = previous.map { [$0] } ?? angles.indices.map { rotation in
                angles.indices.map { ($0 + rotation) % angles.count }
            }
            for order in orders {
                let score = angles.indices.reduce(0.0) { sum, physical in
                    let desired = -.pi / 2 + Double(order[physical]) * RingPlacement.turn / Double(originalCount)
                    let delta = (angles[physical] - desired).remainder(dividingBy: RingPlacement.turn)
                    return sum + delta * delta
                }
                if score < bestScore - 1e-9 { bestScore = score; bestOrder = order }
            }
            let visualBounds = visuals.dropFirst().reduce(visuals[0]) { $0.union($1) }
            let furthest = visuals.flatMap { rect in
                [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                 CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            }.map { hypot($0.x - anchor.x, $0.y - anchor.y) }.max() ?? radius
            let degrees = 180 / Double.pi
            let geometry = RingGeometry(slotCount: angles.count, outerRadius: max(furthest, RingPlacement.innerRadius),
                                        arcStartDegrees: boundaries[0] * degrees,
                                        arcSweepDegrees: fullCircle ? 360 : (boundaries.last! - boundaries[0]) * degrees,
                                        labelRadius: radius, labelAngles: angles.map { $0 * degrees },
                                        sectorBoundaries: boundaries.map { $0 * degrees })
            return Solution(geometry: geometry, visualBounds: visualBounds, order: bestOrder, score: bestScore)
        }

        private func validPreferredOrder(count: Int) -> [Int]? {
            guard let preferredOrder, preferredOrder.count == count,
                  Set(preferredOrder) == Set(0..<count),
                  preferredOrder.indices.allSatisfy({ preferredOrder[($0 + 1) % count] == (preferredOrder[$0] + 1) % count })
            else { return nil }
            return preferredOrder
        }

        /// 首项固定后，贪心得到每项可行下界；从末项向前夹到正常方向，保留后项与闭环约束。
        /// 这只利用真实剩余空位，不改变半径、容量、动作循环顺序或调用方稳定的切口。
        private func relaxing(_ original: Solution, radius: CGFloat, arcs: [Interval]) -> Solution? {
            let count = original.geometry.slotCount
            guard count > 1 else { return nil }
            var angles = (0..<count).map { original.geometry.slotCenterDegrees($0) * .pi / 180 }
            let start = angles[0], end = start + RingPlacement.turn
            var domains: [Interval] = []
            for arc in arcs {
                let base = floor((start - arc.start) / RingPlacement.turn)
                for turn in -1...1 {
                    let shift = (base + Double(turn)) * RingPlacement.turn
                    let low = max(start, arc.start + shift), high = min(end, arc.end + shift)
                    if low <= high + 1e-9 { domains.append(Interval(start: low, end: high)) }
                }
            }
            domains.sort { $0.start < $1.start }
            guard let earliest = pack(count: count, radius: radius, firstAngle: start, domains: domains) else { return nil }
            var desired = original.order.map { -.pi / 2 + Double($0) * RingPlacement.turn / Double(originalCount) }
            for index in 1..<count {
                while desired[index] <= desired[index - 1] { desired[index] += RingPlacement.turn }
            }
            let meanDelta = zip(angles, desired).reduce(0.0) { $0 + $1.0 - $1.1 } / Double(count)
            let shift = (meanDelta / RingPlacement.turn).rounded() * RingPlacement.turn
            desired = desired.map { $0 + shift }
            func previousCenter(before boundary: Double) -> Double {
                let support = Double(collisionHalf.width) * abs(sin(boundary))
                    + Double(collisionHalf.height) * abs(cos(boundary))
                return boundary - asin(min(1, support / Double(radius))) - 1e-10
            }
            func closestAllowed(to target: Double, low: Double, high: Double) -> Double? {
                var best: Double?
                for domain in domains {
                    let a = max(low, domain.start), b = min(high, domain.end)
                    guard a <= b + 1e-9 else { continue }
                    let value = min(max(target, a), max(a, b))
                    if best == nil || abs(value - target) < abs(best! - target) { best = value }
                }
                return best
            }
            let closure = footprint(radius: radius, angle: start, half: collisionHalf).start + RingPlacement.turn
            var upper = previousCenter(before: closure)
            for index in stride(from: count - 1, through: 1, by: -1) {
                guard let angle = closestAllowed(to: desired[index], low: earliest[index], high: upper) else { return nil }
                angles[index] = angle
                upper = previousCenter(before: footprint(radius: radius, angle: angle, half: collisionHalf).start)
            }
            return solution(radius: radius, angles: angles, fullCircle: original.geometry.isFullCircle)
        }

        private func bodyFrame(radius: CGFloat, angle: Double) -> CGRect {
            CGRect(x: anchor.x + radius * CGFloat(cos(angle)) - half.width,
                   y: anchor.y - radius * CGFloat(sin(angle)) - half.height, width: size.width, height: size.height)
        }
        private func distanceToBody(_ rect: CGRect) -> CGFloat {
            hypot(max(rect.minX - anchor.x, 0, anchor.x - rect.maxX),
                  max(rect.minY - anchor.y, 0, anchor.y - rect.maxY))
        }
        private func fits(_ rect: CGRect) -> Bool {
            Self.contains(bounds, rect) && !exclusions.contains { $0.intersection(rect).width > RingPlacement.epsilon && $0.intersection(rect).height > RingPlacement.epsilon }
        }
        private static func contains(_ outer: CGRect, _ inner: CGRect) -> Bool {
            inner.minX >= outer.minX - RingPlacement.epsilon && inner.maxX <= outer.maxX + RingPlacement.epsilon
                && inner.minY >= outer.minY - RingPlacement.epsilon && inner.maxY <= outer.maxY + RingPlacement.epsilon
        }
        private func footprint(radius: CGFloat, angle: Double, half: CGSize) -> Interval {
            let x = Double(radius) * cos(angle), y = Double(radius) * sin(angle)
            let corners = [-Double(half.width), Double(half.width)].flatMap { dx in
                [-Double(half.height), Double(half.height)].map { dy in
                    let raw = atan2(y + dy, x + dx)
                    return raw + RingPlacement.turn * ((angle - raw) / RingPlacement.turn).rounded()
                }
            }
            return Interval(start: corners.min()!, end: corners.max()!)
        }

        /// 圆与真实矩形/禁区/圆角死区的交点分割角域，不使用固定角度模板。
        private func allowedArcs(radius: CGFloat) -> [Interval] {
            let centers = centerBounds
            let forbidden = exclusions.map { $0.insetBy(dx: -half.width - RingButtonMetrics.shadowMargin,
                                                       dy: -half.height - RingButtonMetrics.shadowMargin) }
            var boundaries: [Double] = [0, RingPlacement.turn]
            func normalize(_ angle: Double) -> Double {
                let value = angle.truncatingRemainder(dividingBy: RingPlacement.turn)
                return value < 0 ? value + RingPlacement.turn : value
            }
            func addX(_ x: CGFloat) {
                guard abs(x) <= radius else { return }
                let a = acos(Double(x / radius)); boundaries += [a, RingPlacement.turn - a]
            }
            func addY(_ y: CGFloat) {
                guard abs(y) <= radius else { return }
                let a = asin(Double(-y / radius)); boundaries += [normalize(a), normalize(.pi - a)]
            }
            for rect in [centers] + forbidden {
                for x in [rect.minX - anchor.x, rect.maxX - anchor.x] { addX(x) }
                for y in [rect.minY - anchor.y, rect.maxY - anchor.y] { addY(y) }
            }
            // 按钮矩形与中心死区的 Minkowski 和：四段直边和四个圆角。
            for sign: CGFloat in [-1, 1] {
                addX(sign * (half.width + RingPlacement.innerRadius))
                addY(sign * (half.height + RingPlacement.innerRadius))
            }
            let cornerDistance = hypot(half.width, half.height)
            let cosine = (radius * radius + cornerDistance * cornerDistance - RingPlacement.innerRadius * RingPlacement.innerRadius)
                / (2 * radius * cornerDistance)
            if abs(cosine) <= 1 {
                let delta = acos(Double(cosine))
                for x: CGFloat in [-half.width, half.width] {
                    for y: CGFloat in [-half.height, half.height] {
                        let direction = atan2(Double(-y), Double(x))
                        boundaries += [normalize(direction - delta), normalize(direction + delta)]
                    }
                }
            }
            boundaries.sort()
            var unique: [Double] = []
            for value in boundaries where unique.last.map({ abs(value - $0) > 1e-10 }) ?? true { unique.append(value) }
            func allowed(_ angle: Double) -> Bool {
                let body = bodyFrame(radius: radius, angle: angle)
                return fits(body.insetBy(dx: -RingButtonMetrics.shadowMargin, dy: -RingButtonMetrics.shadowMargin))
                    && distanceToBody(body) + RingPlacement.epsilon >= RingPlacement.innerRadius
            }
            var arcs: [Interval] = []
            for index in 0..<(unique.count - 1) {
                let low = unique[index], high = unique[index + 1]
                if allowed((low + high) / 2) {
                    if let last = arcs.last, abs(last.end - low) < 1e-9 { arcs[arcs.count - 1].end = high }
                    else { arcs.append(Interval(start: low, end: high)) }
                }
            }
            // 精确相切或只有一条可用中心线也是有解，不把零宽角区误判为像素不足。
            for value in unique where allowed(value) && !arcs.contains(where: { value >= $0.start - 1e-9 && value <= $0.end + 1e-9 }) {
                arcs.append(Interval(start: value, end: value))
            }
            arcs.sort { $0.start < $1.start }
            if arcs.count > 1, abs(arcs[0].start) < 1e-9, abs(arcs.last!.end - RingPlacement.turn) < 1e-9 {
                let first = arcs.removeFirst()
                arcs[arcs.count - 1].end = first.end + RingPlacement.turn
            }
            return arcs
        }
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
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

    /// 窗口按实际像素向外对齐，不裁掉内容；布局中的亚像素变化不再反复触发同一个窗口尺寸。
    static func pixelAlignedWindowFrame(_ frame: CGRect, scale: CGFloat) -> CGRect {
        let scale = max(1, scale)
        let minX = floor(frame.minX * scale) / scale
        let minY = floor(frame.minY * scale) / scale
        let maxX = ceil(frame.maxX * scale) / scale
        let maxY = ceil(frame.maxY * scale) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
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
