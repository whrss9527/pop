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
                    HStack(spacing: 8) {
                        Image(systemName: info.symbol)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.name)
                            if let warning = warning(for: info.id, in: settings) {
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        ShortcutRecorder(combo: binding(for: info.id))
                    }
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

    private func binding(for pluginID: String) -> Binding<KeyCombo?> {
        Binding(
            get: { store.settings.hotKey(for: pluginID) },
            set: { key in store.update { $0.setHotKey(key, for: pluginID) } }
        )
    }

    /// 和唤起圆盘、剪贴板历史的快捷键撞了时提醒一下
    private func warning(for pluginID: String, in settings: AppSettings) -> String? {
        guard let key = settings.hotKey(for: pluginID) else { return nil }
        if settings.trigger.hotKey.keyCombo == key {
            return "和唤起圆盘的快捷键重复了"
        }
        if settings.clipboard.enabled, settings.clipboard.hotKey.keyCombo == key {
            return "和剪贴板历史的快捷键重复了"
        }
        return nil
    }
}

/// 录制快捷键的按钮：点一下开始录，按下组合键就记下来；Esc 取消，⌫ 清除。
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "按下快捷键…" : (combo?.display ?? "设置快捷键"))
                .monospacedDigit()
                .foregroundStyle(combo == nil && !recording ? Color.secondary : Color.primary)
                .frame(minWidth: 96)
        }
        .onDisappear(perform: stop)
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
    }
}
