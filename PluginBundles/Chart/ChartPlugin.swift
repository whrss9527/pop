import AppKit
@testable import Pop

/// 插件包「生成图表」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopChartEntry)
final class ChartEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ChartPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：从表格里复制的半年销售额和成本，按月份画成折线
        host.addDemoScene(PluginHost.DemoScene(name: "chart", after: "pdfPages", order: 18, delay: 1.4, hold: 0, show: { demo in
            demo.overlay.showCard(ChartView(model: ChartPlugin.demoModel(), onCopy: {}, onSave: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct ChartPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.chart, name: String(localized: "生成图表"), symbol: "chart.bar.xaxis",
                          summary: String(localized: "选中表格（从表格软件复制的、CSV、Markdown 表格）、一行一个「名字 数值」或者一串数，画成柱状图、条形图、折线图或者饼图，复制成图片或者存到「下载」"),
                          accepts: [.text], check: .custom(CustomContentCheck("chart") { ChartData.parse($0) != nil }))

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let dataset = ChartData.parse(text) else {
            return .failure(String(localized: "没认出能画成图表的数据"))
        }
        let model = ChartModel(dataset: dataset)
        return .present(PluginPresentation { session in
            session.showCard(ChartView(model: model,
                                       onCopy: {
                                           guard let png = model.png() else {
                                               session.fail(String(localized: "图表没能画成图片"))
                                               return
                                           }
                                           session.perform(.copyImage(png))
                                       },
                                       onSave: {
                                           guard let png = model.png() else {
                                               session.fail(String(localized: "图表没能画成图片"))
                                               return
                                           }
                                           session.perform(.saveImage(png, name: model.fileName))
                                       },
                                       onClose: { session.end() }))
        })
    }

    /// 演示用：从表格里复制的上半年销售额和成本（万元）
    static let demoText = "月份\t销售额\t成本\n1月\t120\t82\n2月\t135\t86\n3月\t162\t95\n4月\t151\t91\n5月\t178\t102\n6月\t196\t110"

    @MainActor static func demoModel(defaults: UserDefaults = UserDefaults(suiteName: "PopChartDemo") ?? .standard) -> ChartModel {
        let model = ChartModel(dataset: ChartData.parse(demoText) ?? ChartData.Dataset(labels: [], series: [], labelTitle: nil, unit: nil, decimals: 0),
                               defaults: defaults)
        // 演示的示例内容不翻译
        model.title = "上半年销售额和成本（万元）"
        return model
    }
}
