import AppKit
import SwiftUI

/// 大字显示：把一段文字铺满屏幕，字号按屏幕大小自动算；点一下或者按任意键关闭，⌘C 复制
enum LargeType {
    /// 最多显示这么多字，再多铺满屏幕也看不清
    static let maxLength = 300

    private static let centered: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }()

    /// 这么长以内连在一起的一段（单词、号码、验证码）不拆到两行；更长的（链接）可以在中间换行
    static let longestUnbroken = 20

    /// 能放进 size 的最大字号：自动换行以后不超高，英文单词、数字这类连在一起的不会被拆到两行
    static func fontSize(for text: String, fitting size: CGSize, maximum: CGFloat = 320, minimum: CGFloat = 16) -> CGFloat {
        guard size.width > 0, size.height > 0, !text.isEmpty else { return minimum }
        guard fits(text, fontSize: minimum, in: size) else { return minimum }
        if fits(text, fontSize: maximum, in: size) { return maximum }
        var low = minimum
        var high = maximum
        for _ in 0..<20 {
            let middle = (low + high) / 2
            if fits(text, fontSize: middle, in: size) {
                low = middle
            } else {
                high = middle
            }
        }
        return low.rounded(.down)
    }

    static func fits(_ text: String, fontSize: CGFloat, in size: CGSize) -> Bool {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .paragraphStyle: centered,
        ]
        for run in unbreakableRuns(text) where run.count <= longestUnbroken
            && NSAttributedString(string: run, attributes: attributes).size().width > size.width {
            return false
        }
        let bounds = NSAttributedString(string: text, attributes: attributes)
            .boundingRect(with: CGSize(width: size.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return bounds.height <= size.height
    }

    /// 连在一起、不会在中间换行的几段：按空白和中日韩文字断开（中文一个字一个字都能换行）
    static func unbreakableRuns(_ text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in text {
            if character.isWhitespace || isCJK(character) {
                if !current.isEmpty {
                    runs.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            runs.append(current)
        }
        return runs
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x2E80...0x9FFF).contains(scalar.value) || (0xAC00...0xD7AF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value) || (0xFF00...0xFFEF).contains(scalar.value)
        }
    }
}

/// 铺满指针所在屏幕的一层：深色半透明的底，中间是字
final class LargeTypeWindow: NSWindow {
    private static var current: LargeTypeWindow?

    private let text: String
    private let previousApp: NSRunningApplication?
    private var monitor: Any?

    static func show(_ text: String, near point: CGPoint) {
        current?.dismiss()
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else { return }
        let window = LargeTypeWindow(text: text, screen: screen)
        current = window
        window.alphaValue = 0
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.installMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.seconds(0.15)
            window.animator().alphaValue = 1
        }
    }

    private init(text: String, screen: NSScreen) {
        self.text = text
        previousApp = NSWorkspace.shared.frontmostApplication
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let area = CGSize(width: screen.frame.width - 160, height: screen.frame.height - 220)
        // 算字号时留一点余量：SwiftUI 排出来的行高和 AppKit 算的略有出入
        let fontSize = LargeType.fontSize(for: text, fitting: CGSize(width: area.width * 0.95, height: area.height * 0.9))
        contentView = NSHostingView(rootView: LargeTypeView(text: text, fontSize: fontSize, width: area.width))
        setFrame(screen.frame, display: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }

    /// 点一下、按任意键都关掉；⌘C 先复制
    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self else { return false }
                if event.type == .keyDown, event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
                    PasteboardWriter.copy(self.text)
                }
                self.dismiss()
                return true
            }
            return handled ? nil : event
        }
    }

    private func dismiss() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if Self.current === self {
            Self.current = nil
        }
        orderOut(nil)
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
    }
}

private struct LargeTypeView: View {
    let text: String
    let fontSize: CGFloat
    let width: CGFloat

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: width)
            VStack {
                Spacer()
                Text("点一下或按任意键关闭 · ⌘C 复制")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 36)
            }
        }
        .ignoresSafeArea()
    }
}
