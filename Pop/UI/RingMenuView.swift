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
            update(content: content)
        }
    }

    func update(content: ClassifiedContent) {
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
        let index = offset.flatMap { geometry.slot(at: $0) }
        if index != hovered {
            hovered = index
        }
    }

    func setHovered(_ index: Int?) {
        hovered = index
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

struct RingMenuView: View {
    @ObservedObject var model: RingViewModel

    var body: some View {
        let geometry = model.geometry
        let size = geometry.diameter
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 12, y: 4)

            if let hovered = model.hovered, model.slots.indices.contains(hovered) {
                let degrees = geometry.sectorDegrees(hovered)
                SectorShape(startDegrees: degrees.start, endDegrees: degrees.end,
                            innerRadius: geometry.innerRadius + 2, outerRadius: geometry.outerRadius - 4)
                    .fill(Color.accentColor.opacity(model.slots[hovered].enabled ? 0.32 : 0.1))
            }

            ForEach(model.slots) { slot in
                let offset = geometry.slotCenterOffset(slot.id)
                RingSlotLabel(slot: slot, isHovered: model.hovered == slot.id, isLoading: model.isLoading)
                    .position(x: size / 2 + offset.dx, y: size / 2 - offset.dy)
            }

            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                .frame(width: geometry.innerRadius * 2 - 4, height: geometry.innerRadius * 2 - 4)

            centerLabel(width: geometry.innerRadius * 2 - 14)
        }
        .frame(width: size, height: size)
        .padding(OverlayController.ringPadding)
    }

    @ViewBuilder
    private func centerLabel(width: CGFloat) -> some View {
        if model.isLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            Text(model.centerText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: width)
        }
    }
}

private struct RingSlotLabel: View {
    let slot: RingViewModel.Slot
    let isHovered: Bool
    let isLoading: Bool

    var body: some View {
        let active = isHovered && slot.enabled
        VStack(spacing: 3) {
            if let info = slot.info {
                Image(systemName: info.symbol)
                    .font(.system(size: 19, weight: .medium))
                    .frame(height: 22)
                Text(info.name)
                    .font(.system(size: 10.5))
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
        .scaleEffect(active ? 1.12 : 1)
        .animation(.easeOut(duration: 0.12), value: active)
    }
}

/// 圆环上的一个扇区。角度用 SwiftUI 坐标系（y 轴向下，从 x 正方向顺时针）。
struct SectorShape: Shape {
    var startDegrees: Double
    var endDegrees: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        // y 轴向下时，clockwise: false 在屏幕上是顺时针方向
        path.addArc(center: center, radius: outerRadius,
                    startAngle: .degrees(startDegrees), endAngle: .degrees(endDegrees), clockwise: false)
        path.addArc(center: center, radius: innerRadius,
                    startAngle: .degrees(endDegrees), endAngle: .degrees(startDegrees), clockwise: true)
        path.closeSubpath()
        return path
    }
}
