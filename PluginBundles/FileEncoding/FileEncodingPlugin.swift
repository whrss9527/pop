import AppKit
@testable import Pop

/// 插件包「文件编码」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopFileEncodingEntry)
final class FileEncodingEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [FileEncodingPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：两个 Windows 上存的 GBK 文件和一个 UTF-8 的（内容是示例，不碰真的文件）
        host.addDemoScene(PluginHost.DemoScene(name: "fileEncoding", after: "newFile", order: 1, delay: 1.4, hold: 0, show: { demo in
            let model = FileEncodingModel(rows: FileEncodingPlugin.demoRows(), target: .utf8BOM, lines: .keep)
            demo.overlay.showCard(FileEncodingView(model: model, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct FileEncodingPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.fileEncoding, name: String(localized: "文件编码"), symbol: "character.book.closed",
                          summary: String(localized: "认出选中的文本文件是什么编码（UTF-8、GBK、Big5……）、用的什么换行，一键转成 UTF-8（Excel 打开 CSV 要带 BOM）或者 GBK，换行统一成 LF 或 CRLF；转完可以撤销"),
                          accepts: [.files], check: .custom(CustomContentCheck("textFiles") { subject in
                              subject.split(separator: "\n").contains { TextEncodingTools.isTextFile(String($0)) }
                          }))

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files.filter { TextEncodingTools.isTextFile($0.path(percentEncoded: false)) }
        guard !files.isEmpty else { return .failure(String(localized: "没有选中文本文件")) }
        let rows = await runInBackground { files.prefix(50).map(FileEncodingModel.inspect) }
        return .present(PluginPresentation { session in
            let model = FileEncodingModel(rows: rows)
            session.showCard(FileEncodingView(model: model, onClose: { session.end() }))
        })
    }

    /// 演示用：Windows 上存的订单表和字幕（GBK、CRLF），还有一个 UTF-8 的说明
    static func demoRows() -> [FileEncodingModel.Row] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-demo", directoryHint: .isDirectory)
        let samples: [(String, String, TextEncodingTools.Encoding)] = [
            ("订单.csv", "订单号,商品,数量,金额\r\n20260930001,无线鼠标,2,198.00\r\n20260930002,机械键盘,1,459.00\r\n", .gb18030),
            ("字幕.srt", "1\r\n00:00:01,000 --> 00:00:03,500\r\n大家好，欢迎来到这一期的节目\r\n", .gb18030),
            ("说明.md", "# 使用说明\n\n把文件拖进来就能用。\n", .utf8),
        ]
        return samples.map { name, text, encoding in
            FileEncodingModel.Row(url: folder.appending(path: name), original: TextEncodingTools.encode(text, as: encoding) ?? Data(), source: encoding)
        }
    }
}
