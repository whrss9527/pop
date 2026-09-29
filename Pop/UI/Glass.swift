import AppKit
import SwiftUI

/// 透过窗口看到后面的桌面和其他窗口（模糊）。macOS 15 上当玻璃底用。
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// 浮窗的玻璃质感。
/// macOS 26 上用系统的 Liquid Glass（需要用 Xcode 26 编译）；更早的系统用窗口后面的模糊，
/// 再加顶部一层高光和一圈亮边，看起来像一块玻璃。
struct GlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: shape)
        } else {
            blurred(content)
        }
        #else
        blurred(content)
        #endif
    }

    private func blurred(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    VisualEffectBackground()
                    LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                    if let tint {
                        tint.opacity(0.14)
                    }
                }
                .clipShape(shape)
            }
            .overlay {
                // 玻璃的亮边：左上亮、右下暗
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.08)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: 1)
            }
            .overlay {
                shape.stroke(Color.black.opacity(0.14), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.24), radius: 16, y: 6)
    }
}

extension View {
    /// 给视图加一块玻璃底，形状由 shape 决定。
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint))
    }
}

/// 列表里的行：选中的那一行衬一块高亮，换行时高亮滑过去；鼠标悬停时浅浅亮一下。
struct SelectionHighlight: ViewModifier {
    let isSelected: Bool
    let namespace: Namespace.ID
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if hovering && !isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    }
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.22))
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
            }
            .onHover { hovering = $0 }
            .animation(Motion.content, value: hovering)
    }
}

extension View {
    func selectionHighlight(_ isSelected: Bool, in namespace: Namespace.ID) -> some View {
        modifier(SelectionHighlight(isSelected: isSelected, namespace: namespace))
    }
}
