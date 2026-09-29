import AppKit
import SwiftUI

@MainActor
final class RingViewModel: ObservableObject {
    struct Slot: Identifiable, Equatable {
        let id: Int
        let info: PluginInfo?
        var enabled: Bool
    }

    let geometry: RingGeometry
    @Published private(set) var slots: [Slot]
    @Published private(set) var hovered: Int? = nil
    /// 高亮所在的角度（度，SwiftUI 坐标系）。跨过 0° 时继续累加，滑到下一格时总是走近的那一边
    @Published private(set) var highlightAngle: Double = -90
    /// 高亮从无到有时换一个新的：新的高亮直接出现在目标格上，不会从上次离开的位置滑过来
    @Published private(set) var highlightID = 0
    /// 选中执行的那一格：圆盘收起前它会「按」一下
    @Published private(set) var committed: Int? = nil
    @Published private(set) var centerText: String
    @Published private(set) var isLoading: Bool

    init(layout: RingLayout, catalog: [PluginInfo], installed: Set<String>, content: ClassifiedContent?) {
        let count = max(layout.slotCount, 1)
        geometry = RingGeometry(slotCount: count, outerRadius: RingGeometry.outerRadius(forSlotCount: count))
        slots = layout.slots.enumerated().map { index, pluginID in
            let info = pluginID.flatMap { id in installed.contains(id) ? catalog.first(where: { $0.id == id }) : nil }
            return Slot(id: index, info: info, enabled: false)
        }
        centerText = "读取中…"
        isLoading = true
        if let content {
            apply(content)
        }
    }

    func update(content: ClassifiedContent) {
        withAnimation(Motion.content) {
            apply(content)
        }
    }

    private func apply(_ content: ClassifiedContent) {
        slots = slots.map { slot in
            var slot = slot
            slot.enabled = slot.info?.canHandle(content) ?? false
            return slot
        }
        centerText = content.summary
        isLoading = false
    }

    /// offset 是指针相对圆心（或按下点）的偏移，y 轴向上；nil 表示不指向任何格子。
    func updateHover(offset: CGVector?) {
        setHovered(offset.flatMap { geometry.slot(at: $0) })
    }

    func setHovered(_ index: Int?) {
        guard index != hovered, committed == nil else { return }
        withAnimation(Motion.hover) {
            if let index {
                if hovered == nil {
                    highlightID += 1
                }
                highlightAngle = RingGeometry.continuousAngle(geometry.slotCenterDegrees(index), near: highlightAngle)
            }
            hovered = index
        }
        // 触控板上划过每一格轻轻震一下
        if let index, slots.indices.contains(index), slots[index].enabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    /// 选中了这一格，马上就要执行
    func commit(_ index: Int) {
        guard slots.indices.contains(index) else { return }
        if hovered != index {
            setHovered(index)
        }
        withAnimation(Motion.commit) {
            committed = index
        }
    }

    /// 可以执行的格子（有插件、能处理当前内容、内容已读取完）
    func selectablePlugin(at index: Int?) -> PluginInfo? {
        guard !isLoading, let index, slots.indices.contains(index), slots[index].enabled else { return nil }
        return slots[index].info
    }

    /// 放了插件的格子（不管能不能处理当前内容）；空格子返回 nil
    func pluginSlot(_ index: Int?) -> Int? {
        guard let index, slots.indices.contains(index), slots[index].info != nil else { return nil }
        return index
    }
}

/// 圆盘：玻璃圆盘从指针处弹开，格子从圆心依次飞出；指向哪一格，高亮就沿着圆环滑过去。
/// 收起时（选中或取消）圆盘微微放大、格子往外飘着淡出，选中的那一格再按一下。动画的方向始终是从里往外。
struct RingMenuView: View {
    @ObservedObject var model: RingViewModel
    @ObservedObject var presentation: OverlayPresentation
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool {
        systemReduceMotion && !Motion.ignoresReduceMotion
    }

    var body: some View {
        let geometry = model.geometry
        let size = geometry.diameter
        let phase = presentation.phase
        ZStack {
            Color.clear
                .frame(width: size, height: size)
                .glassSurface(Circle())
                .scaleEffect(discScale(phase))
                .opacity(phase == .shown ? 1 : 0)
                .animation(phase == .shown ? Motion.ringOpen : Motion.exit, value: phase)

            highlight
                .opacity(phase == .shown ? 1 : 0)
                .animation(phase == .shown ? Motion.ringOpen : Motion.exit, value: phase)

            ForEach(model.slots) { slot in
                slotView(slot, phase: phase)
            }

            hub(phase: phase)
        }
        .frame(width: size, height: size)
        .padding(OverlayController.ringPadding)
    }

    @ViewBuilder
    private var highlight: some View {
        if let hovered = model.hovered, model.slots.indices.contains(hovered) {
            RingHighlight(angle: model.highlightAngle, geometry: model.geometry,
                          enabled: model.slots[hovered].enabled, committed: model.committed != nil)
                .id(model.highlightID)
                .transition(.opacity)
        }
    }

    private func slotView(_ slot: RingViewModel.Slot, phase: OverlayPresentation.Phase) -> some View {
        let offset = model.geometry.slotCenterOffset(slot.id)
        let reach = slotReach(phase)
        return RingSlotLabel(slot: slot, isHovered: model.hovered == slot.id, committed: model.committed,
                             isLoading: model.isLoading)
            .scaleEffect(reduceMotion || phase != .entering ? 1 : 0.55)
            .opacity(phase == .shown ? 1 : 0)
            .offset(x: offset.dx * reach, y: -offset.dy * reach)
            .animation(phase == .shown ? Motion.ringOpen.delay(reduceMotion ? 0 : Double(slot.id) * Motion.slotStagger)
                                       : Motion.exit,
                       value: phase)
    }

    private func hub(phase: OverlayPresentation.Phase) -> some View {
        let diameter = model.geometry.innerRadius * 2 - 4
        return ZStack {
            Circle()
                .fill(Color.primary.opacity(0.06))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            if model.hovered != nil {
                // 圆心边上的小点指着当前的格子，跟着高亮一起转
                PolarDot(angle: model.highlightAngle, distance: diameter / 2 - 6, radius: 2.5)
                    .fill(Color.accentColor)
                    .id(model.highlightID)
                    .transition(.opacity)
            }
            ZStack {
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity)
                } else {
                    Text(model.centerText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: diameter - 10)
                        .transition(.opacity)
                }
            }
            .animation(Motion.content, value: model.isLoading)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(reduceMotion || phase != .entering ? 1 : 0.5)
        .opacity(phase == .shown ? 1 : 0)
        .animation(phase == .shown ? Motion.ringOpen.delay(Motion.seconds(0.04)) : Motion.exit, value: phase)
    }

    /// 圆盘的缩放：从小弹开，收起时微微放大着淡出
    private func discScale(_ phase: OverlayPresentation.Phase) -> CGFloat {
        guard !reduceMotion else { return 1 }
        switch phase {
        case .entering: return 0.3
        case .shown: return 1
        case .leaving: return 1.05
        }
    }

    /// 格子离圆心的远近（1 表示在自己的位置上）：展开前都挤在圆心，收起时再往外飘一点
    private func slotReach(_ phase: OverlayPresentation.Phase) -> CGFloat {
        guard !reduceMotion else { return 1 }
        switch phase {
        case .entering: return 0.12
        case .shown: return 1
        case .leaving: return 1.1
        }
    }
}

/// 指向的格子下面衬一块圆形高亮，外圈一段弧线；两者都沿着圆环滑到下一格。
private struct RingHighlight: View {
    let angle: Double
    let geometry: RingGeometry
    let enabled: Bool
    let committed: Bool

    var body: some View {
        let radius = geometry.highlightRadius
        let arcSpan = min(360.0 / Double(max(geometry.slotCount, 1)) * 0.62, 42)
        ZStack {
            PolarDot(angle: angle, distance: geometry.labelRadius, radius: radius)
                .fill(Color.accentColor.opacity(committed ? 0.34 : 0.2))
            PolarDot(angle: angle, distance: geometry.labelRadius, radius: radius)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            RingArc(angle: angle, radius: geometry.outerRadius - 5, span: arcSpan)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .shadow(color: Color.accentColor.opacity(0.7), radius: 5)
        }
        .opacity(enabled ? 1 : 0.35)
        .frame(width: geometry.diameter, height: geometry.diameter)
        .allowsHitTesting(false)
    }
}

/// 离中心 distance、角度 angle（度，SwiftUI 坐标系）处的一个圆。角度可以动画，圆会沿着圆周移动。
struct PolarDot: Shape {
    var angle: Double
    var distance: CGFloat
    var radius: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radians = CGFloat(angle) * .pi / 180
        let center = CGPoint(x: rect.midX + cos(radians) * distance, y: rect.midY + sin(radians) * distance)
        return Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// 以 angle 为中心、张角 span 的一段圆弧（度，SwiftUI 坐标系）。
struct RingArc: Shape {
    var angle: Double
    var radius: CGFloat
    var span: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // y 轴向下时，clockwise: false 在屏幕上是顺时针方向
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: .degrees(angle - span / 2), endAngle: .degrees(angle + span / 2), clockwise: false)
        return path
    }
}

private struct RingSlotLabel: View {
    let slot: RingViewModel.Slot
    let isHovered: Bool
    let committed: Int?
    let isLoading: Bool

    var body: some View {
        let isCommitted = committed == slot.id
        let active = (isHovered && slot.enabled) || isCommitted
        let dimmed = committed != nil && !isCommitted
        VStack(spacing: 3) {
            if let info = slot.info {
                Image(systemName: info.symbol)
                    .font(.system(size: 19, weight: .medium))
                    .symbolEffect(.bounce, value: isCommitted)
                    .frame(height: 22)
                Text(info.name)
                    .font(.system(size: 10.5, weight: active ? .semibold : .regular))
                    .lineLimit(1)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: 66)
        .foregroundStyle(active ? Color.accentColor : Color.primary)
        .opacity(isLoading ? 0.45 : (slot.enabled ? 1 : 0.3))
        .opacity(dimmed ? 0.35 : 1)
        .scaleEffect(isCommitted ? 1.2 : (active ? 1.12 : 1))
        .animation(Motion.hover, value: active)
        .animation(Motion.commit, value: isCommitted)
        .animation(Motion.content, value: slot.enabled)
        .animation(Motion.content, value: isLoading)
    }
}
