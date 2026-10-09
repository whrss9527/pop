import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 「设置 → 快捷键」：给常用的功能设置全局快捷键。
struct HotKeySettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    let catalog: [PluginInfo]

    var body: some View {
        let settings = store.settings
        let installed = catalog.filter { settings.isInstalled($0.id) }
        Form {
            Section {
                ForEach(installed) { info in
                    ShortcutSettingsRow(title: info.name, target: .plugin(info.id), symbol: info.symbol)
                }
            } header: {
                Text("给常用的功能设置全局快捷键")
            } footer: {
                Text("按下快捷键时，Pop 读取当前选中的内容，直接执行这个功能，不弹圆盘；截图翻译、屏幕取色这类不需要选中内容的功能马上执行。点右边的按钮后按下组合键（至少带 ⌘、⌥、⌃ 中的一个，F1–F20 可以单独用），按 Esc 取消，按 ⌫ 清除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// 圆盘、剪贴板和功能快捷键共用的设置行，录入失败时展示原因并保留原组合。
struct ShortcutSettingsRow: View {
    @EnvironmentObject private var store: SettingsStore
    let title: String
    let target: ShortcutTarget
    var symbol: String? = nil
    @State private var rejectedKey: KeyCombo?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                Spacer()
                ShortcutRecorder(combo: binding)
                    .accessibilityLabel(Text(title))
            }
            if let warning = store.settings.shortcutIssue(for: rejectedKey ?? store.settings.shortcut(for: target), target: target) {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var binding: Binding<KeyCombo?> {
        Binding(
            get: { store.settings.shortcut(for: target) },
            set: { key in
                if store.settings.shortcutIssue(for: key, target: target) != nil {
                    rejectedKey = key
                    return
                }
                rejectedKey = nil
                store.update { _ = $0.recordShortcut(key, for: target) }
            }
        )
    }
}

/// 录制快捷键的按钮：点一下开始录，按下组合键就记下来；Esc 取消，⌫ 清除。
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @Environment(\.isEnabled) private var isEnabled
    @State private var recordingID = UUID()
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? String(localized: "按下快捷键…") : (combo?.display ?? String(localized: "设置快捷键")))
                .monospacedDigit()
                .foregroundStyle(combo == nil && !recording ? Color.secondary : Color.primary)
                .frame(minWidth: 96)
        }
        .onDisappear(perform: stop)
        .onReceive(ShortcutRecordingState.shared.changes) { id in
            if recording, id != recordingID { stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { stop() }
        }
    }

    private func toggle() {
        if recording {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        stop()
        recording = true
        ShortcutRecordingState.shared.begin(recordingID)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                record(event)
            }
            // 录制期间的按键都不往下传
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Escape), flags.isEmpty {
            stop()
        } else if event.keyCode == UInt16(kVK_Delete), flags.isEmpty {
            combo = nil
            stop()
        } else if let recorded = KeyCombo(event: event) {
            combo = recorded
            stop()
        }
    }

    private func stop() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        ShortcutRecordingState.shared.end(recordingID)
    }
}
