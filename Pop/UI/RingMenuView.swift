import AppKit
import SwiftUI

@MainActor
final class RingViewModel: ObservableObject {
    struct Slot: Identifiable, Equatable {
        let id: Int
        let info: PluginInfo?
        var enabled: Bool
        var isOverflow = false
        var pendingPackage: String? = nil

        /// 更多列表也保留等待更新的功能名称、图标和不可执行状态。
        var displayName: String { info?.name ?? pendingPackage ?? String(localized: "空格子") }
        var displaySymbol: String { info?.symbol ?? (pendingPackage == nil ? "circle.dotted" : "arrow.clockwise") }
        var updateHint: String? {
            pendingPackage == nil ? nil : String(localized: "正在更新，联网后会自动重试")
        }
    }

    private let baseGeometry: RingGeometry
    /// 一次唤起只算一次；异步内容、返回圆盘都不改变位置和编号。
    private(set) var placement: RingPlacement?
    var geometry: RingGeometry { placement?.geometry ?? baseGeometry }
    var overflowID: Int { slots.count }
    var visibleSlots: [Slot] {
        guard let placement, placement.hasOverflow else { return slots }
        return Array(slots.prefix(max(placement.visibleSlotCount - 1, 0))) +
            [Slot(id: overflowID, info: nil, enabled: true, isOverflow: true)]
    }
    func isOverflow(_ index: Int?) -> Bool { placement?.hasOverflow == true && index == overflowID }
    func displayIndex(for id: Int) -> Int? { visibleSlots.firstIndex { $0.id == id } }

    func freezePlacement(anchor: CGPoint, safeFrame: CGRect) {
        guard placement == nil else { return }
        placement = RingPlacement(slotCount: slots.count, anchor: anchor, safeFrame: safeFrame)
    }

    func nextVisibleSlot(by delta: Int) -> Int {
        let ids = visibleSlots.map(\.id)
        guard !ids.isEmpty else { return 0 }
        let start = hovered.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : 0)
        return ids[((start + delta) % ids.count + ids.count) % ids.count]
    }

    @Published var overflowSelection = 0
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
    /// 读到的内容（读取完之前是 nil），用来说明某一格为什么用不了
    private(set) var content: ClassifiedContent?

    /// 圆心显示的文字
    struct Center: Hashable {
        var title: String
        /// 第二行的小字：这一格为什么用不了
        var detail: String?
        /// 指着的是一个功能（不是读到的内容）
        var isFunction = false
        var enabled = true
    }

    init(layout: RingLayout, catalog: [PluginInfo], installed: Set<String>, content: ClassifiedContent?) {
        let count = max(layout.slotCount, 1)
        baseGeometry = RingGeometry(slotCount: count, outerRadius: RingGeometry.outerRadius(forSlotCount: count))
        slots = layout.slots.enumerated().map { index, pluginID in
            let info = pluginID.flatMap { id in installed.contains(id) ? catalog.first(where: { $0.id == id }) : nil }
            let pending = pluginID.flatMap { id in
                installed.contains(id) && info == nil ? PluginCatalog.all.first(where: { $0.functions.contains(id) })?.name : nil
            }
            return Slot(id: index, info: info, enabled: false, pendingPackage: pending)
        }
        centerText = String(localized: "读取中…")
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
        self.content = content
    }

    /// 指着一格时显示这一格的功能名（用不了时下面说明原因），指着空格子时说明是空的；没指着任何一格时显示读到的内容
    var center: Center {
        if isOverflow(hovered) { return Center(title: String(localized: "更多功能"), isFunction: true) }
        guard let hovered, slots.indices.contains(hovered) else { return Center(title: centerText) }
        let slot = slots[hovered]
        if let package = slot.pendingPackage {
            return Center(title: package, detail: String(localized: "正在更新，联网后会自动重试"), isFunction: true, enabled: false)
        }
        guard let info = slot.info else {
            return Center(title: String(localized: "空格子"), detail: String(localized: "可以在设置里放上功能"), isFunction: true, enabled: false)
        }
        let hint = slot.enabled || isLoading ? nil : Self.unavailableHint(for: info, content: content)
        return Center(title: info.name, detail: hint, isFunction: true, enabled: slot.enabled)
    }

    /// 这一格用不了时的简短说明：缺的是哪种内容，或者这次的内容不合适
    static func unavailableHint(for info: PluginInfo, content: ClassifiedContent?) -> String {
        let kinds = content?.kinds ?? []
        guard !info.accepts.isEmpty, info.accepts.isDisjoint(with: kinds) else { return String(localized: "当前内容用不了") }
        let order: [(ContentKind, String)] = [
            (.text, String(localized: "要先选中文字")), (.chineseText, String(localized: "要先选中文字")),
            (.foreignText, String(localized: "要先选中外文")), (.files, String(localized: "要先选中文件")),
            (.imageFile, String(localized: "要先选中图片文件")), (.image, String(localized: "要先选中图片")),
            (.url, String(localized: "要先选中链接")), (.email, String(localized: "要先选中邮箱")),
            (.json, String(localized: "要先选中JSON")), (.math, String(localized: "要先选中算式")),
            (.number, String(localized: "要先选中数字")), (.color, String(localized: "要先选中颜色值")),
            (.timestamp, String(localized: "要先选中时间戳")), (.dateTime, String(localized: "要先选中日期")),
            (.measurement, String(localized: "要先选中带单位的数")), (.word, String(localized: "要先选中一个词")),
        ]
        return order.first(where: { info.accepts.contains($0.0) })?.1 ?? String(localized: "要先选中内容")
    }

    /// offset 是指针相对圆心（或按下点）的偏移，y 轴向上；nil 表示不指向任何格子。
    func updateHover(offset: CGVector?) {
        let index = offset.flatMap { geometry.slot(at: $0) }
        setHovered(index.flatMap { visibleSlots.indices.contains($0) ? visibleSlots[$0].id : nil })
    }

    func setHovered(_ index: Int?) {
        guard index != hovered, committed == nil else { return }
        withAnimation(Motion.ringHover) {
            if let index, let position = displayIndex(for: index) {
                if hovered == nil {
                    highlightID += 1
                }
                highlightAngle = RingGeometry.continuousAngle(geometry.slotCenterDegrees(position), near: highlightAngle)
            }
            hovered = index
        }
        // 触控板上划过每一格轻轻震一下
        if let index, slots.indices.contains(index), slots[index].enabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    /// 从结果或更多列表返回时复用原来的位置，只重置本次高亮和按下动画。
    func resetSelection() {
        committed = nil
        setHovered(nil)
    }

    /// 选中了这一格，马上就要执行
    func commit(_ index: Int) {
        guard slots.indices.contains(index) else { return }
        if hovered != index {
            setHovered(index)
        }
        withAnimation(Motion.ringCommit) {
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

/// 功能以独立气泡展示，靠边时朝屏幕内排列。
struct RingMenuView: View {
    @ObservedObject var model: RingViewModel
    @ObservedObject var presentation: OverlayPresentation
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var reduceMotion: Bool {
        reduceMotionOverride ?? (systemReduceMotion && !Motion.ignoresReduceMotion)
    }

    private var isEdge: Bool { !model.geometry.isFullCircle }

    var body: some View {
        let geometry = model.geometry
        let size = geometry.diameter
        let phase = presentation.phase
        let placement = model.placement
        let canvas = placement?.frame.size ?? CGSize(width: size + OverlayController.ringPadding * 2,
                                                     height: size + OverlayController.ringPadding * 2)
        let origin = placement.map { CGPoint(x: $0.anchor.x - $0.frame.minX, y: $0.frame.maxY - $0.anchor.y) }
            ?? CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        ZStack(alignment: .topLeading) {
            Color.clear
            ZStack {
                ForEach(model.visibleSlots) { slot in
                    slotView(slot, phase: phase)
                }
                if !isEdge || hubHasRoom {
                    hub(phase: phase)
                }
            }
            .frame(width: size, height: size)
            .position(origin)

            if let placement, let status = placement.statusFrame {
                edgeStatus(phase: phase)
                    .frame(width: status.width, height: status.height)
                    .position(x: status.midX - placement.frame.minX, y: placement.frame.maxY - status.midY)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
    }

    private func slotView(_ slot: RingViewModel.Slot, phase: OverlayPresentation.Phase) -> some View {
        let position = model.displayIndex(for: slot.id) ?? 0
        let offset = model.geometry.slotCenterOffset(position)
        let reach = slotReach(phase)
        let spacing = 2 * model.geometry.labelRadius * sin(model.geometry.slotStep / 2)
        let labelWidth = min(60, max(36, spacing - 12))
        return RingSlotLabel(slot: slot, isHovered: model.hovered == slot.id, committed: model.committed,
                             isLoading: model.isLoading, reduceMotion: reduceMotion,
                             labelWidth: labelWidth)
            .help(slotHint(slot))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(slotHint(slot)))
            .accessibilityAddTraits(.isButton)
            .scaleEffect(reduceMotion || phase != .entering ? 1 : 0.72)
            .opacity(phase == .shown ? 1 : 0)
            .offset(x: offset.dx * reach, y: -offset.dy * reach)
            .animation(phase == .shown ? Motion.ringOpen.delay(reduceMotion ? 0 : min(Double(position) * Motion.slotStagger, Motion.seconds(0.045)))
                                       : Motion.exit,
                       value: phase)
    }

    private func slotHint(_ slot: RingViewModel.Slot) -> String {
        if slot.isOverflow { return String(localized: "更多功能") }
        if let hint = slot.updateHint { return slot.displayName + "\n" + hint }
        guard let info = slot.info else { return String(localized: "空格子") }
        if model.isLoading { return info.name + "\n" + String(localized: "读取中…") }
        return slot.enabled ? info.name : info.name + "\n" + RingViewModel.unavailableHint(for: info, content: model.content)
    }

    private var hubHasRoom: Bool {
        guard let placement = model.placement else { return true }
        let radius = model.geometry.innerRadius
        return placement.safeFrame.contains(CGRect(x: placement.anchor.x - radius, y: placement.anchor.y - radius,
                                                   width: radius * 2, height: radius * 2))
    }

    private func hub(phase: OverlayPresentation.Phase) -> some View {
        let diameter = isEdge ? 24 : model.geometry.innerRadius * 2 - 4
        return ZStack {
            RingSurface(shape: Circle())
            if let hovered = model.hovered {
                // 圆心边上的小点指着当前的格子，跟着高亮一起转
                let enabled = model.isOverflow(hovered) || (model.slots.indices.contains(hovered) && model.slots[hovered].enabled)
                PolarDot(angle: model.highlightAngle, distance: diameter / 2 - 6, radius: 2.5)
                    .fill(enabled ? Color.accentColor : Color.primary.opacity(0.4))
                    .id(model.highlightID)
                    .animation(reduceMotion ? nil : Motion.ringHover, value: model.highlightAngle)
                    .transition(.opacity)
            }
            // 靠边时提示放在扇形内侧，唤起点只保留取消标记。
            if hubHasRoom && !isEdge {
                ZStack {
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(RingPalette(isDark: colorScheme == .dark).foreground)
                            .transition(.opacity)
                    } else {
                        centerLabel(model.center)
                            .frame(width: diameter - 10)
                            .transition(.opacity)
                    }
                }
                .animation(Motion.content, value: model.isLoading)
                .animation(Motion.content, value: model.center)
            }
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(reduceMotion || phase != .entering ? 1 : 0.88)
        .opacity(phase == .shown ? 1 : 0)
        .animation(phase == .shown ? Motion.ringOpen : Motion.exit, value: phase)
    }

    /// 靠边时把说明从被裁切的圆心移到弧带内侧，读取和不可用原因仍能看见。
    private func edgeStatus(phase: OverlayPresentation.Phase) -> some View {
        let palette = RingPalette(isDark: colorScheme == .dark)
        return VStack(spacing: 2) {
            if model.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("读取中…").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.foreground.opacity(RingPalette.mutedOpacity))
                }
            } else {
                centerLabel(model.center)
                if model.center.detail == nil {
                    Text("关闭（Esc）")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.foreground.opacity(RingPalette.mutedOpacity))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { RingSurface(shape: RoundedRectangle(cornerRadius: 10, style: .continuous)) }
        .opacity(phase == .shown ? 1 : 0)
        .animation(Motion.content, value: model.isLoading)
        .animation(Motion.content, value: model.center)
        .animation(phase == .shown ? Motion.ringOpen : Motion.exit, value: phase)
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }

    /// 圆心保留功能名称与不可用原因。
    private func centerLabel(_ center: RingViewModel.Center) -> some View {
        let palette = RingPalette(isDark: colorScheme == .dark)
        let tint = palette.foreground.opacity(center.enabled ? 1 : RingPalette.mutedOpacity)
        let size: CGFloat = center.isFunction ? (isEdge ? 12 : 11) : (isEdge ? 11 : 10)
        let weight: Font.Weight = center.isFunction ? .semibold : .medium
        return VStack(spacing: 2) {
            Text(center.title)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(tint)
                .lineLimit(isEdge ? 1 : 2)
            if let detail = center.detail {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(palette.foreground.opacity(RingPalette.mutedOpacity))
                    .lineLimit(isEdge ? 1 : 2)
            }
        }
        .multilineTextAlignment(.center)
    }

    /// 靠边时只做短距离展开，保持气泡处于可见区域。
    private func slotReach(_ phase: OverlayPresentation.Phase) -> CGFloat {
        guard !reduceMotion else { return 1 }
        switch phase {
        case .entering: return isEdge ? 0.94 : 0.6
        case .shown: return 1
        case .leaving: return isEdge ? 1.015 : 1.04
        }
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

struct RingPalette {
    let isDark: Bool
    static let surfaceOpacity = 0.86
    static let mutedOpacity = 0.8
    static let hoverOpacity = 0.1
    static let commitOpacity = 0.14
    static let unavailableHoverOpacity = 0.06
    var surfaceLevel: Double { isDark ? 0.13 : 0.97 }
    var foregroundLevel: Double { isDark ? 0.96 : 0.08 }
    var surface: Color { Color(white: surfaceLevel) }
    var foreground: Color { Color(white: foregroundLevel) }
}

private struct RingBackdropBlendingKey: EnvironmentKey {
    static let defaultValue: NSVisualEffectView.BlendingMode = .behindWindow
}

extension EnvironmentValues {
    var ringBackdropBlending: NSVisualEffectView.BlendingMode {
        get { self[RingBackdropBlendingKey.self] }
        set { self[RingBackdropBlendingKey.self] = newValue }
    }
}

private struct RingSurface<Surface: InsettableShape>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.ringBackdropBlending) private var blendingMode
    let shape: Surface
    var tintOpacity: Double = RingPalette.surfaceOpacity

    var body: some View {
        let palette = RingPalette(isDark: colorScheme == .dark)
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: blendingMode)
            palette.surface.opacity(tintOpacity)
        }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.16 : 0.55), palette.foreground.opacity(0.08)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }
}

private struct RingSlotLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let slot: RingViewModel.Slot
    let isHovered: Bool
    let committed: Int?
    let isLoading: Bool
    let reduceMotion: Bool
    let labelWidth: CGFloat

    var body: some View {
        let isCommitted = committed == slot.id
        let active = (isHovered && slot.enabled) || isCommitted
        let dimmed = committed != nil && !isCommitted
        let palette = RingPalette(isDark: colorScheme == .dark)
        let foregroundOpacity = (isLoading && !slot.isOverflow) || !slot.enabled || dimmed ? RingPalette.mutedOpacity : 1
        let tint = slot.enabled ? Color.accentColor : palette.foreground
        let shape = RoundedRectangle(cornerRadius: min(14, labelWidth * 0.28), style: .circular)
        VStack(spacing: 3) {
            if slot.isOverflow {
                glyph("ellipsis", active: active, isCommitted: isCommitted)
                caption(String(localized: "更多"))
            } else if let info = slot.info {
                glyph(info.symbol, active: active, isCommitted: isCommitted)
                caption(info.name)
            } else if slot.pendingPackage != nil {
                glyph("arrow.clockwise", active: false, isCommitted: false)
                caption(String(localized: "正在更新"))
            } else {
                Circle().fill(palette.foreground.opacity(foregroundOpacity))
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.horizontal, 4)
        .frame(width: labelWidth, height: min(54, labelWidth))
        .foregroundStyle(palette.foreground.opacity(foregroundOpacity))
        .background {
            RingSurface(shape: shape)
                .overlay {
                    shape.fill(tint.opacity(active ? (isCommitted ? RingPalette.commitOpacity : RingPalette.hoverOpacity)
                                                   : (isHovered ? RingPalette.unavailableHoverOpacity : 0)))
                }
                .overlay {
                    shape.strokeBorder(tint.opacity(active ? 0.55 : (isHovered ? 0.22 : 0)), lineWidth: 1)
                }
        }
        .scaleEffect(reduceMotion ? 1 : (isCommitted ? 0.92 : 1))
        .animation(Motion.ringHover, value: active)
        .animation(Motion.ringCommit, value: isCommitted)
        .animation(Motion.content, value: slot.enabled)
        .animation(Motion.content, value: isLoading)
    }

    private func caption(_ name: String) -> some View {
        Text(name)
            .font(.system(size: labelWidth < 48 ? 9 : 10, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
    }

    private func glyph(_ symbol: String, active: Bool, isCommitted: Bool) -> some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: labelWidth < 48 ? 16 : 18, weight: .regular))
            .frame(height: labelWidth < 48 ? 20 : 24)
            .scaleEffect(reduceMotion ? 1 : (active && !isCommitted ? 1.06 : 1))
    }
}

/// 空间不够时保留所有原格子及编号，读取内容只更新可用状态，不重排。
struct RingOverflowView: View {
    @ObservedObject var model: RingViewModel
    let onSelect: (Int) -> Void
    let onBack: () -> Void
    let onCancel: () -> Void
    let maxHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) { Label("返回圆盘", systemImage: "chevron.left") }
                Spacer()
                Button(action: onCancel) { Image(systemName: "xmark") }
                    .accessibilityLabel(Text("关闭"))
            }
            .buttonStyle(.plain)
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.slots) { slot in
                            Button { onSelect(slot.id) } label: {
                                HStack(spacing: 10) {
                                    Text("\(slot.id + 1)")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22)
                                    Image(systemName: slot.displaySymbol)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(slot.displayName)
                                        if let hint = slot.updateHint {
                                            Text(hint).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        } else if model.isLoading {
                                            Text("读取中…").font(.caption).foregroundStyle(.secondary)
                                        } else if let info = slot.info, !slot.enabled {
                                            Text(RingViewModel.unavailableHint(for: info, content: model.content))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                                .background(model.overflowSelection == slot.id ? Color.accentColor.opacity(0.16) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isLoading || !slot.enabled)
                            .id(slot.id)
                        }
                    }
                    .padding(6)
                }
                .frame(height: min(CGFloat(model.slots.count) * 46 + 12, max(44, maxHeight - 70)))
                .onChange(of: model.overflowSelection) { _, selected in
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
        }
        .frame(width: 292)
        .glassSurface(RoundedRectangle(cornerRadius: 16))
        .padding(10)
    }
}
