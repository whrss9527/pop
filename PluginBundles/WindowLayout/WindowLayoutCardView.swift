import AppKit
import Carbon.HIToolbox
import SwiftUI
@testable import Pop

/// 窗口布局卡片：选一个位置，把唤起时前台 App 的窗口放过去
struct WindowLayoutCardView: View {
    var hasMultipleDisplays: Bool
    var onChoose: (WindowLayout) -> Void
    var onClose: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        CardContainer(title: String(localized: "窗口布局"), subtitle: String(localized: "方向键放到半屏，回车最大化"), width: 404, onClose: onClose) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(WindowLayout.allCases) { layout in
                    LayoutTile(layout: layout, enabled: layout != .nextDisplay || hasMultipleDisplays) {
                        onChoose(layout)
                    }
                }
            }
        }
    }

    /// 键盘选择：← → ↑ ↓ 放到对应的半屏，回车最大化，C 居中，1–3 放到三分之一
    static func layout(for event: NSEvent) -> WindowLayout? {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return nil }
        switch Int(event.keyCode) {
        case kVK_LeftArrow: return .leftHalf
        case kVK_RightArrow: return .rightHalf
        case kVK_UpArrow: return .topHalf
        case kVK_DownArrow: return .bottomHalf
        case kVK_Return, kVK_ANSI_KeypadEnter: return .maximize
        case kVK_ANSI_C: return .center
        case kVK_ANSI_1: return .leftThird
        case kVK_ANSI_2: return .centerThird
        case kVK_ANSI_3: return .rightThird
        default: return nil
        }
    }
}

private struct LayoutTile: View {
    let layout: WindowLayout
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: layout.symbol)
                    .font(.system(size: 17))
                    .frame(height: 22)
                Text(layout.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(hovering && enabled ? 0.14 : 0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(layout.title)
        .onHover { hovering = $0 }
        .animation(Motion.content, value: hovering)
    }
}
