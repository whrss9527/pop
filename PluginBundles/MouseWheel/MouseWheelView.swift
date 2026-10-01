import SwiftUI
@testable import Pop

/// 「鼠标滚轮」卡片：上下反过来、左右反过来、滚动速度，现在的情况和说明
struct MouseWheelView: View {
    @ObservedObject var model: MouseWheel
    var onOpenPrivacy: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "鼠标滚轮"), width: 360, onClose: onClose) {
            Toggle(isOn: Binding(get: { model.options.reverseVertical }, set: { model.setReverse($0) })) {
                Text("滚轮方向反过来")
            }
            .toggleStyle(.switch)
            Text(verbatim: model.directionHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("左右滚动也反过来", isOn: Binding(get: { model.options.reverseHorizontal }, set: { model.setReverseHorizontal($0) }))
                .toggleStyle(.checkbox)
            Picker("滚动速度", selection: Binding(get: { model.options.speed }, set: { model.setSpeed($0) })) {
                ForEach(MouseWheel.speeds, id: \.self) { speed in
                    Text(MouseWheel.speedTitle(speed)).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: model.needsPermission ? "exclamationmark.triangle" : "computermouse")
                    .foregroundStyle(model.needsPermission ? Color.orange : (model.isRunning ? Color.accentColor : .secondary))
                    .frame(width: 16)
                Text(verbatim: model.statusText)
                    .font(.callout)
                    .foregroundStyle(model.options.isActive ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("只改一格一格的滚轮鼠标；触控板、妙控鼠标照旧。设置会记住，Pop 启动时接着生效。")
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
}
