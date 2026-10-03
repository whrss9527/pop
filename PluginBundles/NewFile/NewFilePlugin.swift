import AppKit
@testable import Pop

/// 插件包「新建文件」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopNewFileEntry)
final class NewFileEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [NewFilePlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：把选中的一段 Markdown 存成文件（只是卡片，不写文件）
        host.addDemoScene(PluginHost.DemoScene(name: "newFile", after: "pdfPages", order: 3, delay: 1.4, hold: 0, show: { demo in
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let model = NewFileModel(folder: downloads, selection: NewFilePlugin.demoSelection, clipboardText: nil, clipboardImage: nil, kind: .markdown)
            demo.overlay.showCard(NewFileView(model: model, onCreate: { _ in }, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct NewFilePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.newFile, name: String(localized: "新建文件"), symbol: "doc.badge.plus",
                          summary: String(localized: "在选中的文件夹（没选时是访达当前的文件夹）里新建文本、Markdown、网页、脚本这些文件，也可以把选中的文字、剪贴板里的文字和图片直接存成文件"),
                          accepts: [])

    static let demoSelection = "## 本周计划\n\n- 整理「下载」文件夹\n- 给新版本换图标\n- 周五前发布 0.49"

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let folder = await Self.folder(for: content.files, sourcePID: context.sourcePID)
        let pasteboard = NSPasteboard.general
        let model = NewFileModel(folder: folder, selection: content.files.isEmpty ? content.text : nil,
                                 clipboardText: pasteboard.string(forType: .string), clipboardImage: Self.clipboardPNG(pasteboard))
        return .present(PluginPresentation { session in
            session.showCard(NewFileView(model: model, onCreate: { open in
                guard let url = model.create() else { return }
                if open {
                    NSWorkspace.shared.open(url)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                session.finish(toast: String(localized: "新建了「\(url.lastPathComponent)」"))
            }, onClose: { session.end() }))
        })
    }

    /// 存到哪：选中了文件夹就是它，选中了文件就是文件所在的文件夹；什么都没选时是访达最前面的窗口正在看的文件夹，
    /// 不在访达里（或者访达没开窗口）时是桌面
    @MainActor static func folder(for files: [URL], sourcePID: pid_t?) async -> URL {
        if let selected = files.first(where: { FolderTree.isFolder($0.path(percentEncoded: false)) }) {
            return selected
        }
        if let file = files.first {
            return file.deletingLastPathComponent()
        }
        if let pid = sourcePID, NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder",
           let front = await NewFileMaker.frontFinderFolder() {
            return front
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// 剪贴板里的图片存成 PNG；拷贝的是文件时不算（访达会顺带放上文件的图标）
    static func clipboardPNG(_ pasteboard: NSPasteboard) -> Data? {
        guard pasteboard.types?.contains(.fileURL) != true else { return nil }
        if let png = pasteboard.data(forType: .png) {
            return png
        }
        guard let tiff = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
