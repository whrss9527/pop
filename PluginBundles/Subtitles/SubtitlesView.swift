import AppKit
import SwiftUI
@testable import Pop

/// 字幕工具卡片：上面是读到的格式、句数、时间范围和编码，中间是处理以后前几句的样子，
/// 下面调时间、帧率、清理和存成什么格式；选了两份字幕时可以合成双语。
/// 格式不变时直接改原文件（播放器按名字自动加载的字幕还能对上），可以撤销；换了格式或者合成双语时另存一份。
@MainActor
final class SubtitlesModel: ObservableObject {
    struct Source: Equatable {
        let url: URL
        let format: SubtitleTools.Format
        let encoding: String
        let cues: [SubtitleTools.Cue]
        /// 原来的内容，撤销时写回去
        let data: Data
    }

    enum Phase: Equatable {
        case editing
        /// 存好的文件；改了原文件时记着它，可以撤销
        case saved(files: [URL], replaced: [URL])
        case failed(String)
    }

    let sources: [Source]
    /// 正数推后，负数提前（秒）
    @Published var shift: Double = 0 { didSet { resetPhase() } }
    @Published var rate: SubtitleTools.RateChange = .none { didSet { resetPhase() } }
    @Published var stripTags: Bool { didSet { resetPhase() } }
    @Published var stripDescriptions = false { didSet { resetPhase() } }
    @Published var output: SubtitleTools.Format { didSet { resetPhase() } }
    /// 两份字幕时：合成双语
    @Published var merge: Bool { didSet { resetPhase() } }
    /// 合成双语时上面一行用哪一份
    @Published var topIndex = 0 { didSet { resetPhase() } }
    @Published private(set) var phase: Phase = .editing

    init(sources: [Source]) {
        self.sources = sources
        merge = sources.count == 2
        // ASS 的特效标签存成别的格式时没用，默认去掉
        stripTags = sources.contains { $0.format == .ass }
        let first = sources.first?.format ?? .srt
        output = SubtitleTools.Format.outputs.contains(first) ? first : .srt
    }

    /// 读字幕文件；读不了时返回 nil
    nonisolated static func load(_ url: URL) -> Source? {
        guard let data = try? Data(contentsOf: url), let decoded = SubtitleTools.decode(data),
              let format = SubtitleTools.format(of: url, text: decoded.text) else { return nil }
        let cues = SubtitleTools.parse(decoded.text, format: format)
        guard !cues.isEmpty else { return nil }
        return Source(url: url, format: format, encoding: decoded.encoding, cues: cues, data: data)
    }

    private func resetPhase() {
        if phase != .editing {
            phase = .editing
        }
    }

    /// 一份字幕处理以后的样子
    func processed(_ source: Source) -> [SubtitleTools.Cue] {
        // 纯文字和 LRC 里放不了样式标签
        let tags = stripTags || output == .txt || output == .lrc
        let cleaned = SubtitleTools.clean(source.cues, tags: tags, descriptions: stripDescriptions)
        return SubtitleTools.retime(cleaned, shift: shift, rate: rate)
    }

    var isMerging: Bool {
        merge && sources.count == 2
    }

    /// 要写的文件：每一份的路径和内容
    var outputs: [(url: URL, cues: [SubtitleTools.Cue])] {
        if isMerging {
            let top = sources[topIndex]
            let bottom = sources[1 - topIndex]
            let name = SubtitleTools.mergedName(sources[0].url, sources[1].url)
            let url = FileNames.available(in: sources[0].url.deletingLastPathComponent(), base: name, extension: output.fileExtension)
            return [(url: url, cues: SubtitleTools.merge(processed(top), processed(bottom)))]
        }
        return sources.map { source in
            (url: target(for: source), cues: processed(source))
        }
    }

    /// 格式不变时改原文件，换了格式时另存一份同名的
    private func target(for source: Source) -> URL {
        if source.format == output {
            return source.url
        }
        return FileNames.available(in: source.url.deletingLastPathComponent(), base: source.url.deletingPathExtension().lastPathComponent,
                                   extension: output.fileExtension)
    }

    /// 处理以后的前几句
    var preview: [SubtitleTools.Cue] {
        Array((outputs.first?.cues ?? []).prefix(4))
    }

    /// 「SRT · 128 句 · 0:05 – 12:40 · GBK」
    func describe(_ source: Source) -> String {
        let start = source.cues.map(\.start).min() ?? 0
        let end = source.cues.map(\.end).max() ?? 0
        return [source.format.title, String(localized: "\(String(source.cues.count)) 句"),
                "\(FileInfo.duration(start)) – \(FileInfo.duration(end))", source.encoding].joined(separator: " · ")
    }

    /// 时间调整的说明：「推后 1.5 秒」「提前 0.8 秒」「不调」
    var shiftText: String {
        let amount = Self.number(abs(shift))
        if abs(shift) < 0.0005 { return String(localized: "不调") }
        return shift > 0 ? String(localized: "推后 \(amount) 秒") : String(localized: "提前 \(amount) 秒")
    }

    /// 「1.5」「0.25」「2」
    static func number(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// 存好：格式不变的改原文件（存成 UTF-8），换了格式或者合成双语的另存一份
    func save() {
        var written: [URL] = []
        var replaced: [URL] = []
        do {
            for item in outputs {
                let text = SubtitleTools.render(item.cues, as: output)
                try Data(text.utf8).write(to: item.url, options: .atomic)
                written.append(item.url)
                if sources.contains(where: { $0.url == item.url }) {
                    replaced.append(item.url)
                }
            }
            phase = .saved(files: written, replaced: replaced)
        } catch {
            phase = .failed(String(localized: "存不了：\(error.localizedDescription)"))
        }
    }

    /// 撤销：改过的原文件写回原来的内容，另存的删掉
    func undo() {
        guard case .saved(let files, let replaced) = phase else { return }
        for url in files {
            if replaced.contains(url), let source = sources.first(where: { $0.url == url }) {
                try? source.data.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        phase = .editing
    }

    var savedMessage: String? {
        guard case .saved(let files, let replaced) = phase else { return nil }
        let names = files.map { String(localized: "「\($0.lastPathComponent)」") }.joined(separator: Localization.listSeparator)
        return replaced.isEmpty ? String(localized: "存好了\(names)") : String(localized: "改好了\(names)，存成 UTF-8")
    }
}

struct SubtitlesView: View {
    @ObservedObject var model: SubtitlesModel
    var onReveal: ([URL]) -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "字幕工具"), subtitle: subtitle, width: 460, onClose: onClose) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(model.sources, id: \.url) { source in
                    HStack(spacing: 6) {
                        Text(source.url.lastPathComponent)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(model.describe(source))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
            preview
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label("时间")
                    HStack(spacing: 6) {
                        TextField("", value: $model.shift, format: .number.precision(.fractionLength(0...3)))
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $model.shift, in: -3600...3600, step: 0.1)
                            .labelsHidden()
                        Text(model.shiftText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    label("帧率")
                    Picker("帧率", selection: $model.rate) {
                        ForEach(SubtitleTools.RateChange.allCases) { rate in
                            Text(rate.title).tag(rate)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    label("清理")
                    HStack(spacing: 12) {
                        Toggle("去掉样式标签", isOn: $model.stripTags)
                        Toggle("去掉听障说明", isOn: $model.stripDescriptions)
                    }
                    .toggleStyle(.checkbox)
                }
                if model.sources.count == 2 {
                    GridRow {
                        label("双语")
                        HStack(spacing: 8) {
                            Toggle("合成一份", isOn: $model.merge)
                                .toggleStyle(.checkbox)
                            Picker("上面一行", selection: $model.topIndex) {
                                ForEach(model.sources.indices, id: \.self) { index in
                                    Text(model.sources[index].url.lastPathComponent).tag(index)
                                }
                            }
                            .disabled(!model.merge)
                            .fixedSize()
                        }
                    }
                }
                GridRow {
                    label("存成")
                    Picker("存成", selection: $model.output) {
                        ForEach(SubtitleTools.Format.outputs) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            footer
        }
        .controlSize(.small)
    }

    private var subtitle: String {
        model.sources.count == 1 ? model.sources[0].url.lastPathComponent : String(localized: "\(String(model.sources.count)) 份字幕")
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    /// 处理以后的前几句
    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(model.preview.enumerated()), id: \.offset) { _, cue in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(SubtitleTools.timestamp(cue.start))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(cue.text)
                        .font(.callout)
                        .lineLimit(2)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    @ViewBuilder
    private var footer: some View {
        switch model.phase {
        case .editing:
            HStack(spacing: 8) {
                Text(model.isMerging ? String(localized: "另存一份双语字幕") : model.output == model.sources.first?.format
                     ? String(localized: "直接改原文件，可以撤销") : String(localized: "另存一份，原文件不动"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("存好") { model.save() }
                    .keyboardShortcut(.defaultAction)
            }
        case .saved(let files, _):
            Text(model.savedMessage ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("撤销") { model.undo() }
                Button("在访达中显示") { onReveal(files) }
                Button("完成", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            HStack {
                Spacer()
                Button("完成", action: onClose)
            }
        }
    }
}
