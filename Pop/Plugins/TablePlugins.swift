import AppKit

/// 识别表格：选中了图片就识别图片，没选中就先框选屏幕上的一块区域。
struct TableOCRPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.tableOCR, name: String(localized: "识别表格"), symbol: "tablecells",
                          summary: String(localized: "识别截图或图片里的表格，转成 Markdown 表格、CSV 或者制表符分隔（macOS 26；更早的系统按普通文字识别）"),
                          accepts: [], hidesOverlay: true, optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        if case .image(let data) = content.selection, let image = TextRecognizer.cgImage(from: data) {
            return await Self.recognize(image)
        }
        if let url = content.files.first(where: ContentClassifier.isImageFile), let image = TextRecognizer.cgImage(contentsOf: url) {
            return await Self.recognize(image)
        }
        switch await ScreenCapture.selectRegion() {
        case .cancelled:
            return .done(toast: nil)
        case .failed(let message):
            return .failure(message)
        case .captured(let capture):
            return await Self.recognize(capture.image)
        }
    }

    /// 能按表格识别就给表格，否则（系统太旧、没找到表格）给普通的文字
    @MainActor static func recognize(_ image: CGImage) async -> PluginOutcome {
        do {
            if let tables = try await TableOCR.tables(in: image) {
                let found = tables.filter { !$0.isEmpty }
                if let first = found.first {
                    return .card(TableOCR.card(for: first, otherTables: found.count - 1))
                }
                return await text(from: image, note: String(localized: "没有找到表格，下面是识别到的文字"))
            }
        } catch {
            return .failure(String(localized: "识别表格失败：\(error.localizedDescription)"))
        }
        return await text(from: image, note: String(localized: "按表格识别需要 macOS 26，这里按普通文字识别"))
    }

    @MainActor private static func text(from image: CGImage, note: String) async -> PluginOutcome {
        switch await TextRecognizer.recognize(image) {
        case .success(let text):
            guard !text.isEmpty else { return .failure(ScreenCapture.noTextHint) }
            var card = TextRecognizer.card(title: String(localized: "识别表格"), text: text)
            card.detail = note
            return .card(card)
        case .failure(let error):
            return .failure(error.message)
        }
    }
}
