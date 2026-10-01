import AppKit
@testable import Pop

/// 插件包「链接解析」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopLinkInspectEntry)
final class LinkInspectEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [LinkInspectPlugin()]
    }
}

struct LinkInspectPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.linkInspect, name: String(localized: "链接解析"), symbol: "link",
                          summary: String(localized: "拆开链接的协议、主机、路径和每个参数（解码后），去掉 utm_source 这类跟踪参数"), accepts: [.url])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let url = content.url, url.scheme?.lowercased() != "mailto" else { return .failure(String(localized: "没有识别到链接")) }
        let clean = LinkInspector.cleaned(url)?.absoluteString
        var buttons: [CardButton] = []
        if let clean {
            buttons.append(CardButton(title: String(localized: "复制干净的链接"), action: .copy(clean)))
        }
        var detail = clean == nil ? String(localized: "这个链接里没有跟踪参数") : String(localized: "上面是去掉跟踪参数后的链接，可以直接替换原文")
        if LinkExpander.isShortLink(url) {
            // 只有点了才访问短链接服务
            buttons.insert(CardButton(title: String(localized: "展开短链接"), action: .expandLink(url)), at: 0)
            detail += String(localized: "；这是短链接，点「展开短链接」会访问一次它的服务器，看最后跳到哪里")
        }
        return .card(ResultCard(title: String(localized: "链接解析"), body: clean ?? "", detail: detail,
                                monospaced: true, replaceText: clean, rows: LinkInspector.rows(for: url), rowLineLimit: 2,
                                buttons: buttons))
    }
}
