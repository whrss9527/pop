import AppKit
@testable import Pop

/// 插件包「图片配色」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopPaletteEntry)
final class PaletteEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [PalettePlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：图片配色卡片（用标注演示的那张示例图）
        host.addDemoScene(PluginHost.DemoScene(name: "palette", after: "diff", delay: 1.4, hold: 0, show: { demo in
            guard let sample = OverlayDemo.sampleScreenshot() else { return nil }
            let card = PalettePlugin.card(ColorPalette.extract(from: sample.image))
            demo.overlay.showCard(ResultCardView(card: card, onAction: { _ in }, onMore: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct PalettePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.palette, name: String(localized: "图片配色"), symbol: "paintpalette",
                          summary: String(localized: "找出图片里的主要颜色，按面积从大到小列出色值，点一下复制"), accepts: [.image, .imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let image: CGImage?
        if case .image(let data) = content.selection {
            image = TextRecognizer.cgImage(from: data)
        } else if let url = content.files.first {
            image = await TextRecognizer.decodedImage(contentsOf: url)
        } else {
            image = nil
        }
        guard let image else { return .failure(String(localized: "无法读取图片")) }
        let swatches = await runInBackground { ColorPalette.extract(from: image) }
        guard !swatches.isEmpty else { return .failure(String(localized: "图片是全透明的，取不出颜色")) }
        return .card(Self.card(swatches))
    }

    /// 每种颜色一行，上面一排色块，点一下复制色值
    static func card(_ swatches: [ColorPalette.Swatch]) -> ResultCard {
        let rows = swatches.map { swatch in
            ResultCard.Row(label: String(localized: "占 \(max(Int((swatch.share * 100).rounded()), 1))%"), value: swatch.hex)
        }
        return ResultCard(title: String(localized: "图片配色"), detail: String(localized: "按面积从大到小；点色块复制色值"), rows: rows,
                          palette: swatches.map(\.hex))
    }
}
