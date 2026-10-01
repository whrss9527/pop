import AppKit
import SwiftUI

/// 插件自己处理后续的展示时拿到的这次唤起：在唤起的位置弹卡片、显示提示、结束这次唤起。
/// 插件包里的功能用它弹自己的卡片（Pop 的代码不用知道插件包里有哪些卡片）。
@MainActor
struct PluginSession {
    /// 唤起的位置（AppKit 屏幕坐标），卡片和提示从这里弹出来
    let anchor: CGPoint
    /// 选中的内容是在前台 App 里选的，可以把结果写回去替换它
    let canReplace: Bool
    let isCurrentHandler: () -> Bool
    let showCardHandler: (AnyView, ((NSEvent) -> Bool)?) -> Void
    let finishHandler: (String) -> Void
    let endHandler: () -> Void
    let performHandler: (CardAction) -> Void
    let failHandler: (String) -> Void

    /// 这次唤起还在：用户没有关掉浮窗，也没有又唤起一次。耗时的事做完以后先看看它
    var isCurrent: Bool {
        isCurrentHandler()
    }

    /// 在唤起的位置弹出卡片（替换现在的卡片）；keyHandler 返回 true 表示这个按键卡片自己处理了
    func showCard<Content: View>(_ content: Content, keyHandler: ((NSEvent) -> Bool)? = nil) {
        showCardHandler(AnyView(content), keyHandler)
    }

    /// 结束这次唤起，在唤起的位置显示一句提示。耗时的事做完时这次唤起已经结束也照样提示，
    /// 但这期间用户又唤起了 Pop 的话不去打断
    func finish(toast: String) {
        finishHandler(toast)
    }

    /// 收起浮窗，结束这次唤起
    func end() {
        endHandler()
    }

    /// 结果卡片上的通用操作：复制、替换原文、打开、在访达中显示……
    func perform(_ action: CardAction) {
        performHandler(action)
    }

    /// 显示「没能完成」的卡片
    func fail(_ message: String) {
        failHandler(message)
    }
}

/// 插件自己处理后续的展示（PluginOutcome.present）：拿到这次唤起再决定弹什么卡片。按 id 比较
struct PluginPresentation: Equatable {
    let id = UUID()
    let run: @MainActor (PluginSession) -> Void

    init(_ run: @escaping @MainActor (PluginSession) -> Void) {
        self.run = run
    }

    static func == (a: PluginPresentation, b: PluginPresentation) -> Bool {
        a.id == b.id
    }
}

/// 插件自己处理的卡片按钮（CardAction.custom）。按 id 比较
struct PluginCardAction: Equatable {
    let id = UUID()
    let run: @MainActor (PluginSession) -> Void

    init(_ run: @escaping @MainActor (PluginSession) -> Void) {
        self.run = run
    }

    static func == (a: PluginCardAction, b: PluginCardAction) -> Bool {
        a.id == b.id
    }
}

/// 插件包自己的内容检查（ContentCheck.custom），决定圆盘里要不要显示这个功能。按 id 比较
struct CustomContentCheck: Hashable {
    let id: String
    let matches: @Sendable (String) -> Bool

    init(_ id: String, matches: @escaping @Sendable (String) -> Bool) {
        self.id = id
        self.matches = matches
    }

    static func == (a: CustomContentCheck, b: CustomContentCheck) -> Bool {
        a.id == b.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
