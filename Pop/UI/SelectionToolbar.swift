import AppKit
import SwiftUI

/// 选中文字后弹出的工具条：一排功能（图标下面写着名字），点一下就用选中的文字执行；最后的「…」打开完整的圆盘。
/// 窗口不激活 Pop、也不抢键盘焦点，原来的 App 和选区都不受影响。点了别处、按了键、滚动或者过一会儿没用就收起。
@MainActor
final class SelectionToolbarController {
    var onRun: (String) -> Void = { _ in }
    var onMore: () -> Void = {}

    private var panel: SelectionToolbarPanel?
    private var hideTimer: Timer?
    /// 工具条在屏幕上的位置（AppKit 坐标），结果卡片从这里弹出来
    private(set) var frame: CGRect?

    var isVisible: Bool { panel != nil }

    /// 多久没用就自己收起来（秒）
    static let lifetime: TimeInterval = 8

    func show(items: [PluginInfo], selection: CGRect?, pointer: CGPoint) {
        hide()
        let view = SelectionToolbarView(items: items,
                                        onRun: { [weak self] id in
                                            self?.hide()
                                            self?.onRun(id)
                                        },
                                        onMore: { [weak self] in
                                            self?.hide()
                                            self?.onMore()
                                        })
        let hosting = FirstMouseHostingView(rootView: view)
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let frame = SelectionToolbarLogic.frame(size: size, selection: selection, pointer: pointer,
                                                screen: screen?.visibleFrame ?? CGRect(origin: .zero, size: size))
        let panel = SelectionToolbarPanel(frame: frame)
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.seconds(0.12)
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        self.frame = frame
        let timer = Timer(timeInterval: Self.lifetime, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hide()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// 无边框、透明、不激活 App、不抢键盘焦点的小窗口
final class SelectionToolbarPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 窗口不是当前窗口时，第一下点击也直接交给按钮
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct SelectionToolbarView: View {
    let items: [PluginInfo]
    var onRun: (String) -> Void
    var onMore: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                SelectionToolbarButton(symbol: item.symbol, title: item.name) {
                    onRun(item.id)
                }
            }
            Divider()
                .frame(height: 26)
                .padding(.horizontal, 2)
            SelectionToolbarButton(symbol: "ellipsis.circle", title: "更多") {
                onMore()
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .glassSurface(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // 给阴影留的边距
        .padding(8)
    }
}

private struct SelectionToolbarButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(height: 17)
                Text(title)
                    .font(.system(size: 9.5))
                    .lineLimit(1)
            }
            .frame(width: 50, height: 38)
            .foregroundStyle(hovering ? Color.accentColor : Color.primary)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}
