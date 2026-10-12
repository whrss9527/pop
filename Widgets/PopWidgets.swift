import AppIntents
import SwiftUI
import WidgetKit

extension WidgetAction: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "工具")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .clipboard: "剪贴板历史", .screenshotOCR: "截图识字", .screenshotTranslate: "截图翻译", .pluginLibrary: "插件库"
    ]
}

struct ToolConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "常用工具"
    @Parameter(title: "第一个工具", default: .clipboard) var first: WidgetAction
    @Parameter(title: "第二个工具", default: .screenshotOCR) var second: WidgetAction
    @Parameter(title: "第三个工具", default: .screenshotTranslate) var third: WidgetAction
    @Parameter(title: "第四个工具", default: .pluginLibrary) var fourth: WidgetAction
}

struct ToolsEntry: TimelineEntry {
    let date: Date
    let tools: [WidgetAction]
}

struct ToolsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ToolsEntry { ToolsEntry(date: Date(), tools: WidgetAction.allCases) }
    func snapshot(for configuration: ToolConfiguration, in context: Context) async -> ToolsEntry {
        ToolsEntry(date: Date(), tools: [configuration.first, configuration.second, configuration.third, configuration.fourth])
    }
    func timeline(for configuration: ToolConfiguration, in context: Context) async -> Timeline<ToolsEntry> {
        Timeline(entries: [await snapshot(for: configuration, in: context)], policy: .never)
    }
}

struct ToolsView: View {
    let entry: ToolsEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pop", systemImage: "circle.circle").font(.headline)
            if family == .systemSmall, let tool = entry.tools.first {
                Spacer()
                Image(systemName: tool.symbol).font(.largeTitle)
                Text(verbatim: tool.title).font(.headline)
                Spacer()
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(entry.tools.enumerated()), id: \.offset) { _, tool in
                        Link(destination: tool.url) {
                            Label(tool.title, systemImage: tool.symbol).font(.caption).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(entry.tools.first?.url)
    }
}

@main
struct PopWidgets: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PopTools", intent: ToolConfiguration.self, provider: ToolsProvider()) { ToolsView(entry: $0) }
            .configurationDisplayName("常用工具")
            .description("打开剪贴板、截图工具或插件库。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
