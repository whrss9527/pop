import AppKit
import SwiftUI

/// 录屏前倒数：在要录的区域中间显示 3、2、1，每秒换一个数，留出时间切到要录的窗口；倒数时按 Esc 取消。
/// 数字在开始录之前就收起来了，不会录进去。
@MainActor
enum RecordingCountdown {
    static let seconds = 3

    /// 倒数完返回 true，按了 Esc 返回 false
    static func run(in region: CGRect) async -> Bool {
        let model = CountdownModel(value: seconds)
        let panel = makePanel(model: model, region: region)
        panel.orderFrontRegardless()
        // Pop 不在前台时也要接住 Esc（有辅助功能权限就收得到）
        let onKey: @Sendable (NSEvent) -> Void = { event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated {
                    model.cancelled = true
                }
            }
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: onKey)
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            onKey(event)
            return event.keyCode == 53 ? nil : event
        }
        defer {
            for monitor in [global, local].compactMap({ $0 }) {
                NSEvent.removeMonitor(monitor)
            }
            panel.orderOut(nil)
        }
        for value in stride(from: seconds, through: 1, by: -1) {
            withAnimation(Motion.content) {
                model.value = value
            }
            // 每秒分成十小段等，按了 Esc 马上收起
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(100))
                if model.cancelled { return false }
            }
        }
        return true
    }

    /// 演示用：停在 value 上，返回收起的方法
    static func showForDemo(value: Int, in region: CGRect) -> () -> Void {
        let model = CountdownModel(value: value)
        let panel = makePanel(model: model, region: region)
        panel.orderFrontRegardless()
        return { panel.orderOut(nil) }
    }

    private static func makePanel(model: CountdownModel, region: CGRect) -> NSPanel {
        let size = CGSize(width: 150, height: 150)
        let frame = CGRect(x: (region.midX - size.width / 2).rounded(), y: (region.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CountdownView(model: model))
        panel.setFrame(frame, display: false)
        return panel
    }
}

@MainActor
private final class CountdownModel: ObservableObject {
    @Published var value: Int
    var cancelled = false

    init(value: Int) {
        self.value = value
    }
}

private struct CountdownView: View {
    @ObservedObject var model: CountdownModel

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.62))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            Text("\(model.value)")
                .font(.system(size: 72, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .id(model.value)
                .transition(.asymmetric(insertion: .scale(scale: 1.4).combined(with: .opacity), removal: .opacity))
        }
        .frame(width: 128, height: 128)
        .frame(width: 150, height: 150)
    }
}
