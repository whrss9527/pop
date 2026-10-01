import AppKit
@testable import Pop

/// 插件包「识别表格」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopTableOCREntry)
final class TableOCREntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [TableOCRPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：识别表格卡片。macOS 26 上按行列认出格子，更早的系统按普通文字识别
        host.addDemoScene(PluginHost.DemoScene(name: "table", after: "history-search", order: 2, delay: 1.4, hold: 0, show: { demo in
            guard let table = TableOCREntry.sampleTableImage(), case .card(let card) = await TableOCRPlugin.recognize(table) else { return nil }
            demo.overlay.showCard(ResultCardView(card: card, onAction: { _ in }, onMore: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }

    /// 识别表格演示用的图片：一张三列四行、带格子线的版本表，像素按屏幕倍率
    static func sampleTableImage() -> CGImage? {
        let rows = [["版本", "日期", "新功能"],
                    ["0.11.0", "9月29日", "转成 Markdown"],
                    ["0.12.0", "9月29日", "正则测试"],
                    ["0.13.0", "9月29日", "加到提醒事项"]]
        let columnWidths: [CGFloat] = [110, 110, 180]
        let rowHeight: CGFloat = 40
        let size = CGSize(width: columnWidths.reduce(0, +) + 40, height: rowHeight * CGFloat(rows.count) + 40)
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 1)
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 换成「点、左上角为原点」的坐标
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let origin = CGPoint(x: 20, y: 20)
        let tableWidth = columnWidths.reduce(0, +)
        // 表头底色
        context.setFillColor(NSColor(srgbRed: 0.93, green: 0.94, blue: 0.97, alpha: 1).cgColor)
        context.fill(CGRect(x: origin.x, y: origin.y, width: tableWidth, height: rowHeight))
        context.setStrokeColor(NSColor(srgbRed: 0.6, green: 0.62, blue: 0.68, alpha: 1).cgColor)
        context.setLineWidth(1)
        for index in 0...rows.count {
            let y = origin.y + CGFloat(index) * rowHeight
            context.move(to: CGPoint(x: origin.x, y: y))
            context.addLine(to: CGPoint(x: origin.x + tableWidth, y: y))
        }
        var x = origin.x
        for width in [0] + columnWidths.map({ Int($0) }) {
            x += CGFloat(width)
            context.move(to: CGPoint(x: x, y: origin.y))
            context.addLine(to: CGPoint(x: x, y: origin.y + rowHeight * CGFloat(rows.count)))
        }
        context.strokePath()
        for (rowIndex, row) in rows.enumerated() {
            var cellX = origin.x
            for (columnIndex, cell) in row.enumerated() {
                let font = NSFont.systemFont(ofSize: 15, weight: rowIndex == 0 ? .semibold : .regular)
                NSAttributedString(string: cell, attributes: [.font: font, .foregroundColor: NSColor.black])
                    .draw(at: CGPoint(x: cellX + 12, y: origin.y + CGFloat(rowIndex) * rowHeight + 11))
                cellX += columnWidths[columnIndex]
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}

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
