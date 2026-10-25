import AppKit
@testable import Pop

extension Bundle {
    /// 独立发布的插件包，界面文字使用包内翻译。
    static let bytePreview = Bundle(for: BytePreviewEntry.self)
}

@objc(PopBytePreviewEntry)
final class BytePreviewEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] { [BytePreviewPlugin()] }
}

struct BytePreviewPlugin: PopPlugin {
    static let id = "bytePreview"

    let info = PluginInfo(id: Self.id, name: String(localized: "文件字节预览", bundle: .bytePreview),
                          symbol: "doc.text.magnifyingglass",
                          summary: String(localized: "只读预览一个普通文件开头最多 4096 字节，显示偏移、十六进制和 ASCII；不修改或执行文件", bundle: .bytePreview),
                          accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files
        let result: Result<BytePreview.Snapshot, BytePreview.Failure> = await runInBackground {
            do { return .success(try BytePreview.read(files)) }
            catch let failure as BytePreview.Failure { return .failure(failure) }
            catch { return .failure(.cannotRead) }
        }
        switch result {
        case .failure(let failure):
            let message: String
            switch failure {
            case .requiresSingleFile:
                message = String(localized: "请只选中一个普通文件", bundle: .bytePreview)
            case .notLocalFile:
                message = String(localized: "只能预览本机文件", bundle: .bytePreview)
            case .notRegularFile:
                message = String(localized: "不支持文件夹、符号链接或特殊文件", bundle: .bytePreview)
            case .cannotRead:
                message = String(localized: "无法读取这个文件，请检查文件是否存在及读取权限", bundle: .bytePreview)
            }
            return .failure(message)
        case .success(let preview):
            let detail = preview.truncated
                ? String(localized: "仅显示前 4096 字节，后续内容未读取", bundle: .bytePreview)
                : String(localized: "已显示 \(preview.data.count) 字节", bundle: .bytePreview)
            return .card(ResultCard(title: preview.name,
                                    body: preview.data.isEmpty ? String(localized: "文件为空，没有可预览的字节", bundle: .bytePreview) : preview.text,
                                    detail: detail, monospaced: true,
                                    copyText: preview.data.isEmpty ? nil : preview.text))
        }
    }
}
