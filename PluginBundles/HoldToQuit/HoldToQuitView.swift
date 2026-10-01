import AppKit
import SwiftUI
@testable import Pop

/// 「长按 ⌘Q 退出」卡片：开关、怎样才退出、按多久，现在的情况，照旧一按就退出的 App
struct HoldToQuitView: View {
    @ObservedObject var model: HoldToQuit
    /// 唤起 Pop 时在前台的 App：可以一下加进「照旧一按就退出」
    var sourceApp: HoldToQuit.FrontApp?
    var onOpenPrivacy: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "长按 ⌘Q 退出"), width: 380, onClose: onClose) {
            Toggle(isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) })) {
                Text("误按一下 ⌘Q 不退出")
            }
            .toggleStyle(.switch)
            Picker("怎样才退出", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                Text("按住 ⌘Q").tag(QuitGuard.Mode.hold)
                Text("连按两下 ⌘Q").tag(QuitGuard.Mode.twice)
            }
            .pickerStyle(.segmented)
            Picker(model.mode == .hold ? String(localized: "按住多久") : String(localized: "两下最多隔"),
                   selection: Binding(get: { model.duration }, set: { model.setDuration($0) })) {
                ForEach(HoldToQuit.durations, id: \.self) { seconds in
                    Text(HoldToQuit.durationTitle(seconds)).tag(seconds)
                }
            }
            .pickerStyle(.segmented)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: model.needsPermission || model.tapFailed ? "exclamationmark.triangle" : "command")
                    .foregroundStyle(model.needsPermission || model.tapFailed ? Color.orange : (model.isRunning ? Color.accentColor : .secondary))
                    .frame(width: 16)
                Text(verbatim: model.statusText)
                    .font(.callout)
                    .foregroundStyle(model.isEnabled ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            exceptionList
            Text("访达的 ⌘Q 本来就不退出，不拦。Chrome 自己能设成按住 ⌘Q 才退出，装了的话一开始就在上面的列表里，交给它自己管。输入密码时系统不让别的 App 看到按键，这时 ⌘Q 照常一按就退出。设置会记住，Pop 启动时接着生效。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.needsPermission {
                    Button("打开辅助功能设置", action: onOpenPrivacy)
                }
                Spacer()
                Button("完成", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
    }

    private var exceptionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("这些 App 里照旧一按就退出")
                .font(.subheadline.weight(.medium))
            if model.exceptions.isEmpty {
                Text("还没有")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.exceptions, id: \.self) { bundleID in
                let app = model.exceptionApp(bundleID)
                HStack(spacing: 8) {
                    QuitAppIcon(icon: app.icon)
                    Text(verbatim: app.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button {
                        model.removeException(bundleID)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "拿掉"))
                    .accessibilityLabel(String(localized: "拿掉「\(app.name)」"))
                }
            }
            HStack(spacing: 8) {
                if let sourceApp, let bundleID = sourceApp.bundleID, !model.exceptions.contains(bundleID), !model.passes(sourceApp) {
                    Button(String(localized: "加上「\(sourceApp.name)」")) {
                        model.addException(bundleID)
                    }
                }
                Menu("添加 App") {
                    let apps = model.runningApps()
                    if apps.isEmpty {
                        Text("没有别的正在运行的 App")
                    }
                    ForEach(apps) { app in
                        Button(app.name) {
                            if let bundleID = app.bundleID {
                                model.addException(bundleID)
                            }
                        }
                    }
                }
                .fixedSize()
            }
        }
    }
}

/// App 的图标；没有时画一个通用的
private struct QuitAppIcon: View {
    let icon: NSImage?
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 屏幕中间的提示：「按住 ⌘Q 退出「Safari」」和进度圈，「正在退出「Safari」」。
/// 收起以后还画着上一次的样子（窗口已经藏起来了）：大小一直不变，下次显示时放得准
struct QuitPromptView: View {
    @ObservedObject var state: QuitPromptState

    var body: some View {
        content(state.prompt ?? state.lastShown ?? .placeholder)
            .padding(18)
            .fixedSize()
    }

    private func content(_ prompt: HoldToQuit.Prompt) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: prompt.progress)
                    .stroke(prompt.isQuitting ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                QuitAppIcon(icon: prompt.app.icon, size: 44)
            }
            .frame(width: 68, height: 68)
            // 高度不变：退出时第二行留着空位，窗口不用跟着换大小
            Text(verbatim: Self.title(prompt))
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
            (prompt.mode == .hold ? Text("松开就不退出") : Text("不按就不退出"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(prompt.isQuitting ? 0 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 280)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    static func title(_ prompt: HoldToQuit.Prompt) -> String {
        if prompt.isQuitting {
            return String(localized: "正在退出「\(prompt.app.name)」")
        }
        return prompt.mode == .hold
            ? String(localized: "按住 ⌘Q 退出「\(prompt.app.name)」")
            : String(localized: "再按一次 ⌘Q 退出「\(prompt.app.name)」")
    }
}

/// 放提示的窗口：在别的窗口上面，不抢焦点，点不到
final class QuitPromptPanel: NSPanel {
    private let hosting: NSHostingView<QuitPromptView>

    init(rootView: QuitPromptView) {
        hosting = NSHostingView(rootView: rootView)
        super.init(contentRect: CGRect(x: 0, y: 0, width: 316, height: 200), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = hosting
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }

    /// 放在指针所在屏幕的正中间
    func place(on screen: NSScreen? = nil) {
        let pointer = NSEvent.mouseLocation
        guard let screen = screen ?? NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else { return }
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height), display: true)
    }
}
