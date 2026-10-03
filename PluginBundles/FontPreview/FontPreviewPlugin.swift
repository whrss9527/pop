import AppKit
import SwiftUI
@testable import Pop

/// 插件包「字体预览」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopFontPreviewEntry)
final class FontPreviewEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [FontPreviewPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：一句诗用这台 Mac 上的中文字体显示
        host.addDemoScene(PluginHost.DemoScene(name: "fontPreview", after: "pdfPages", order: 9, delay: 1.4, hold: 0, show: { demo in
            // 和插件一样在后台列字体
            let families = await runInBackground { FontCatalog.installed() }
            let model = FontPreviewModel(text: "落霞与孤鹜齐飞，秋水共长天一色", families: families)
            model.size = 22
            demo.overlay.showCard(FontPreviewView(model: model, onCopy: { _ in }, onCopyImage: { _ in }, onReveal: { _ in }, onClose: {}),
                                  anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct FontPreviewPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.fontPreview, name: String(localized: "字体预览"), symbol: "textformat",
                          summary: String(localized: "用这台 Mac 上的每一种字体显示选中的文字（没选中时用示例），按中文、西文、等宽、收藏筛选，只看能完整显示的；复制字体名、CSS，或者复制成图片；选中字体文件时先预览再安装"),
                          accepts: [], optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files.filter(FontCatalog.isFontFile)
        let text = content.text
        let families = await runInBackground { FontCatalog.installed() }
        let faces: [FontPreviewModel.Face] = await runInBackground {
            files.flatMap(FontCatalog.faces(in:)).map { FontPreviewModel.Face(postScriptName: $0.postScriptName, displayName: $0.displayName, font: $0.font) }
        }
        if !files.isEmpty && faces.isEmpty {
            return .failure(String(localized: "读不了这个字体文件"))
        }
        return .present(PluginPresentation { session in
            let model = FontPreviewModel(text: files.isEmpty ? text : nil, families: families, files: files, faces: faces)
            session.showCard(FontPreviewView(model: model,
                                             onCopy: { session.perform(.copy($0)) },
                                             onCopyImage: { session.perform(.copyImage($0)) },
                                             onReveal: { url in
                                                 NSWorkspace.shared.activateFileViewerSelecting([url])
                                                 session.end()
                                             },
                                             onClose: { session.end() }))
        })
    }
}
