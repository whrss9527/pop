import AppKit
import Charts
import SwiftUI
@testable import Pop

/// 「生成图表」卡片的状态：画成什么样子、标题、显不显示数值、要不要从大到小排
@MainActor
final class ChartModel: ObservableObject {
    static let valuesKey = "pop.chart.showsValues"

    let original: ChartData.Dataset
    /// 能画的样子（饼图只给一组、没有负数的数据）
    let kinds: [ChartData.Kind]
    @Published var kind: ChartData.Kind
    @Published var title: String
    @Published var showsValues: Bool {
        didSet { defaults.set(showsValues, forKey: Self.valuesKey) }
    }
    @Published var sortsDescending = false
    private let defaults: UserDefaults

    init(dataset: ChartData.Dataset, defaults: UserDefaults = .standard) {
        original = dataset
        kinds = ChartData.kinds(for: dataset)
        kind = ChartData.suggestedKind(for: dataset)
        // 只有一组数、带着表头时拿表头当标题
        if dataset.series.count == 1, let name = dataset.series.first?.name, name != String(localized: "数值") {
            title = name
        } else {
            title = ""
        }
        // 没改过的话：数不多时显示数值
        showsValues = defaults.object(forKey: Self.valuesKey) as? Bool ?? (dataset.labels.count <= 12)
        self.defaults = defaults
    }

    var dataset: ChartData.Dataset {
        sortsDescending && canSort ? ChartData.sortedDescending(original) : original
    }

    /// 折线是按顺序连起来的，不排
    var canSort: Bool {
        kind != .line && original.labels.count > 2
    }

    /// 「6 项 · 2 组数」
    var summary: String {
        let count = original.labels.count
        let groups = original.series.count
        return groups > 1 ? String(localized: "\(count) 项 · \(groups) 组数") : String(localized: "\(count) 项")
    }

    /// 存成图片：白底，1920 × 1200 像素
    func png() -> Data? {
        ChartImage.png(dataset: dataset, kind: kind, showsValues: showsValues, title: title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 存到「下载」时的文件名：有标题用标题
    var fileName: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ImageFiles.timestampedName(String(localized: "图表")) : trimmed
    }
}

/// 图表本身：卡片上和存成图片都用它
struct ChartCanvas: View {
    let dataset: ChartData.Dataset
    let kind: ChartData.Kind
    let showsValues: Bool
    var title = ""
    /// 存成图片时字大一点
    var exporting = false

    static let palette: [Color] = [
        Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 1.0, green: 0.58, blue: 0.0), Color(red: 0.2, green: 0.78, blue: 0.35),
        Color(red: 0.69, green: 0.32, blue: 0.87), Color(red: 1.0, green: 0.18, blue: 0.33), Color(red: 0.19, green: 0.69, blue: 0.78),
        Color(red: 1.0, green: 0.8, blue: 0.0), Color(red: 0.35, green: 0.34, blue: 0.84), Color(red: 0.0, green: 0.78, blue: 0.75),
        Color(red: 0.64, green: 0.52, blue: 0.37), Color(red: 0.56, green: 0.56, blue: 0.58), Color(red: 1.0, green: 0.42, blue: 0.62),
    ]

    struct Point: Identifiable {
        let id: Int
        let label: String
        let series: String
        /// 第几组：折线图上相邻两组的数值一上一下写，免得叠在一起
        let group: Int
        let value: Double
    }

    /// 每一组的每一项
    var points: [Point] {
        var result: [Point] = []
        for (group, series) in dataset.series.enumerated() {
            for (index, value) in series.values.enumerated() where index < dataset.labels.count {
                result.append(Point(id: group * 100_000 + index, label: dataset.labels[index], series: series.name, group: group, value: value))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: exporting ? 16 : 8) {
            if !title.isEmpty {
                Text(verbatim: title)
                    .font(.system(size: exporting ? 24 : 13, weight: .semibold))
                    .lineLimit(2)
            }
            chart
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch kind {
        case .bar:
            barChart
        case .horizontal:
            horizontalChart
        case .line:
            lineChart
        case .pie:
            pieChart
        }
    }

    private var labelKey: String { String(localized: "名称") }
    private var valueKey: String { String(localized: "数值") }
    private var seriesKey: String { String(localized: "系列") }
    private var seriesNames: [String] { dataset.series.map(\.name) }
    private var seriesColors: [Color] { seriesNames.indices.map { Self.palette[$0 % Self.palette.count] } }
    private var legend: Visibility { dataset.series.count > 1 ? .visible : .hidden }
    private var valueFont: Font { .system(size: exporting ? 14 : 9, weight: .medium) }

    private func valueText(_ value: Double) -> String {
        ChartData.format(value, decimals: dataset.decimals, unit: dataset.unit)
    }

    /// 柱子上的数写在顶上，负数写在下面
    private func columnLabelPosition(_ point: Point) -> AnnotationPosition {
        point.value < 0 ? .bottom : .top
    }

    /// 条形图的数写在右边，负数写在左边
    private func barLabelPosition(_ point: Point) -> AnnotationPosition {
        point.value < 0 ? .leading : .trailing
    }

    private var barChart: some View {
        Chart(points) { point in
            BarMark(x: .value(labelKey, point.label), y: .value(valueKey, point.value))
                .foregroundStyle(by: .value(seriesKey, point.series))
                .position(by: .value(seriesKey, point.series))
                .annotation(position: columnLabelPosition(point), spacing: 2) {
                    if showsValues {
                        Text(verbatim: valueText(point.value))
                            .font(valueFont)
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .chartForegroundStyleScale(domain: seriesNames, range: seriesColors)
        .chartXScale(domain: dataset.labels)
        .chartLegend(legend)
    }

    private var horizontalChart: some View {
        Chart(points) { point in
            BarMark(x: .value(valueKey, point.value), y: .value(labelKey, point.label))
                .foregroundStyle(by: .value(seriesKey, point.series))
                .position(by: .value(seriesKey, point.series))
                .annotation(position: barLabelPosition(point), spacing: 3) {
                    if showsValues {
                        Text(verbatim: valueText(point.value))
                            .font(valueFont)
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .chartForegroundStyleScale(domain: seriesNames, range: seriesColors)
        .chartYScale(domain: dataset.labels)
        .chartLegend(legend)
    }

    private var lineChart: some View {
        Chart(points) { point in
            LineMark(x: .value(labelKey, point.label), y: .value(valueKey, point.value))
                .foregroundStyle(by: .value(seriesKey, point.series))
                .symbol(by: .value(seriesKey, point.series))
            if showsValues {
                PointMark(x: .value(labelKey, point.label), y: .value(valueKey, point.value))
                    .opacity(0)
                    .annotation(position: point.group % 2 == 0 ? .top : .bottom, spacing: 4) {
                        Text(verbatim: valueText(point.value))
                            .font(valueFont)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartForegroundStyleScale(domain: seriesNames, range: seriesColors)
        .chartXScale(domain: dataset.labels)
        .chartLegend(legend)
    }

    private var pieChart: some View {
        let total = dataset.series.first?.values.reduce(0, +) ?? 0
        let colors = dataset.labels.indices.map { Self.palette[$0 % Self.palette.count] }
        return Chart(points) { point in
            SectorMark(angle: .value(valueKey, point.value), innerRadius: .ratio(0.5), angularInset: 1.5)
                .cornerRadius(3)
                .foregroundStyle(by: .value(labelKey, point.label))
                .annotation(position: .overlay) {
                    // 太小的块不写，挤不下
                    if showsValues, total > 0, point.value / total >= 0.05 {
                        Text(verbatim: ChartData.percentText(point.value, total: total))
                            .font(valueFont.bold())
                            .foregroundStyle(.white)
                    }
                }
        }
        .chartForegroundStyleScale(domain: dataset.labels, range: colors)
        .chartLegend(position: .trailing, alignment: .center)
    }
}

/// 图表存成 PNG：白底、浅色外观，960 × 600 点按两倍画
enum ChartImage {
    @MainActor
    static func png(dataset: ChartData.Dataset, kind: ChartData.Kind, showsValues: Bool, title: String) -> Data? {
        let content = ChartCanvas(dataset: dataset, kind: kind, showsValues: showsValues, title: title, exporting: true)
            .padding(36)
            .frame(width: 960, height: 600)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

struct ChartView: View {
    @ObservedObject var model: ChartModel
    var onCopy: () -> Void
    var onSave: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "生成图表"), subtitle: model.summary, width: 460, onClose: onClose) {
            TextField("标题（可以不填，存成图片时写在上面）", text: $model.title)
                .textFieldStyle(.roundedBorder)
            ChartCanvas(dataset: model.dataset, kind: model.kind, showsValues: model.showsValues)
                .frame(height: 230)
            if model.kinds.count > 1 {
                Picker("样子", selection: $model.kind) {
                    ForEach(model.kinds) { kind in
                        Text(verbatim: kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack(spacing: 12) {
                Toggle("显示数值", isOn: $model.showsValues)
                    .toggleStyle(.checkbox)
                if model.canSort {
                    Toggle("从大到小", isOn: $model.sortsDescending)
                        .toggleStyle(.checkbox)
                }
                Spacer(minLength: 8)
                Button("存到「下载」", action: onSave)
                Button("复制图片", action: onCopy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
    }
}
