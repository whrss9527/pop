import SwiftUI
@testable import Pop

/// 文件编码卡片：每个文件认出来的编码、换行和第一行字（读错了可以换一种编码读），选好转成什么，转完可以撤销。
@MainActor
final class FileEncodingModel: ObservableObject {
    nonisolated static let targetKey = "pop.fileEncoding.target"
    nonisolated static let linesKey = "pop.fileEncoding.lines"

    struct Row: Identifiable {
        let url: URL
        let original: Data
        /// 按什么编码读；认不出来时为 nil
        private(set) var source: TextEncodingTools.Encoding?
        /// 按 source 读出来的文字
        private(set) var text: String?
        private(set) var lineEnding: TextEncodingTools.LineEnding?
        /// 太大、读不了这类没法转的原因
        private(set) var problem: String?

        var id: URL { url }

        init(url: URL, original: Data, source: TextEncodingTools.Encoding?, problem: String? = nil) {
            self.url = url
            self.original = original
            self.problem = problem
            if let source, problem == nil {
                read(as: source)
            } else if problem == nil {
                self.problem = String(localized: "认不出是什么编码")
            }
        }

        /// 换一种编码读
        mutating func read(as encoding: TextEncodingTools.Encoding) {
            source = encoding
            text = TextEncodingTools.decode(original, as: encoding)
            lineEnding = text.map(TextEncodingTools.lineEnding(of:))
            problem = text == nil ? String(localized: "按 \(encoding.title) 读不出来") : nil
        }
    }

    enum Phase: Equatable {
        case choosing
        case working
        /// 转了几个、本来就是的几个、出错的（文件名和原因）
        case done(converted: [URL], unchanged: Int, failed: [String])
        case failed(String)
    }

    @Published private(set) var rows: [Row]
    @Published var target: TextEncodingTools.Encoding {
        didSet {
            UserDefaults.standard.set(target.rawValue, forKey: Self.targetKey)
            refresh()
        }
    }
    @Published var lines: TextEncodingTools.LineTarget {
        didSet {
            UserDefaults.standard.set(lines.rawValue, forKey: Self.linesKey)
            refresh()
        }
    }
    @Published private(set) var phase = Phase.choosing
    /// 要转的（转出来和原来不一样的）；换选项时重新算一次，不在每次刷新界面时算
    @Published private(set) var pending: [URL] = []
    /// 正在算要转哪些：每个文件都要整个重新编码一遍比一比，几十 MB 的文件要好一会儿，放在后台算；算好以前不能转
    @Published private(set) var isRefreshing = false
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(rows: [Row], target: TextEncodingTools.Encoding? = nil, lines: TextEncodingTools.LineTarget? = nil) {
        self.rows = rows
        self.target = target ?? UserDefaults.standard.string(forKey: Self.targetKey).flatMap(TextEncodingTools.Encoding.init(rawValue:)) ?? .utf8
        self.lines = lines ?? UserDefaults.standard.string(forKey: Self.linesKey).flatMap(TextEncodingTools.LineTarget.init(rawValue:)) ?? .keep
        refresh()
    }

    /// 转出来的内容；读不了或者存不下时为 nil
    nonisolated static func converted(_ row: Row, to target: TextEncodingTools.Encoding, lines: TextEncodingTools.LineTarget) -> Data? {
        guard row.problem == nil, let text = row.text else { return nil }
        return TextEncodingTools.encode(TextEncodingTools.normalize(text, to: lines), as: target)
    }

    private func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration
        let rows = rows
        let target = target
        let lines = lines
        isRefreshing = true
        refreshTask = Task {
            let changed = await runInBackground {
                rows.filter { row in
                    Self.converted(row, to: target, lines: lines).map { $0 != row.original } ?? false
                }.map(\.url)
            }
            // 算的时候又换了选项：用后来那一次的
            guard generation == refreshGeneration else { return }
            pending = changed
            isRefreshing = false
        }
    }

    /// 等这次算完（测试用）
    func refreshed() async {
        await refreshTask?.value
    }

    /// 读文件、认编码（在后台调用）
    nonisolated static func inspect(_ url: URL) -> Row {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= TextEncodingTools.maxBytes else {
            return Row(url: url, original: Data(), source: nil, problem: String(localized: "文件太大，没有转"))
        }
        guard let data = try? Data(contentsOf: url) else {
            return Row(url: url, original: Data(), source: nil, problem: String(localized: "读不了这个文件"))
        }
        return Row(url: url, original: data, source: TextEncodingTools.detect(data))
    }

    func setSource(_ encoding: TextEncodingTools.Encoding, for row: Row) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[index].read(as: encoding)
        refresh()
    }

    var summary: String {
        guard !isRefreshing else { return String(localized: "正在看哪些文件要转…") }
        let count = pending.count
        guard count > 0 else { return String(localized: "选中的文件已经是这种编码和换行了") }
        let note = target == .utf8BOM ? String(localized: "带 BOM 的 UTF-8 用 Excel 打开 CSV 不会乱码；") : ""
        return note + String(localized: "会把 \(count) 个文件转成 \(target.title)，原来的内容记着，转完可以撤销")
    }

    func convert() {
        guard phase == .choosing else { return }
        let rows = self.rows
        let target = self.target
        let lines = self.lines
        phase = .working
        Task {
            let result: (converted: [URL], unchanged: Int, failed: [String]) = await runInBackground {
                var converted: [URL] = []
                var unchanged = 0
                var failed: [String] = []
                for row in rows {
                    if let problem = row.problem {
                        failed.append(String(localized: "\(row.url.lastPathComponent)（\(problem)）"))
                        continue
                    }
                    guard let data = Self.converted(row, to: target, lines: lines) else {
                        let problem = String(localized: "有的字 \(target.title) 存不下")
                        failed.append(String(localized: "\(row.url.lastPathComponent)（\(problem)）"))
                        continue
                    }
                    if data == row.original {
                        unchanged += 1
                        continue
                    }
                    do {
                        // 不用 .atomic：在原来的文件上改，权限（比如脚本能运行）和扩展属性都留着
                        try data.write(to: row.url)
                        converted.append(row.url)
                    } catch {
                        failed.append(String(localized: "\(row.url.lastPathComponent)（\(error.localizedDescription)）"))
                    }
                }
                return (converted, unchanged, failed)
            }
            phase = .done(converted: result.converted, unchanged: result.unchanged, failed: result.failed)
        }
    }

    /// 把转过的文件写回原来的内容
    func undo() {
        guard case .done(let converted, _, _) = phase else { return }
        let originals = rows.filter { converted.contains($0.url) }.map { ($0.url, $0.original) }
        phase = .working
        Task {
            let failed: [String] = await runInBackground {
                originals.compactMap { url, data in
                    do {
                        try data.write(to: url)
                        return nil
                    } catch {
                        return String(localized: "\(url.lastPathComponent)（\(error.localizedDescription)）")
                    }
                }
            }
            phase = failed.isEmpty ? .choosing : .failed(String(localized: "有的文件没能改回去：\(failed.joined(separator: String(localized: "、")))"))
        }
    }
}

struct FileEncodingView: View {
    @ObservedObject var model: FileEncodingModel
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "文件编码"), subtitle: subtitle, width: 440, onClose: onClose) {
            switch model.phase {
            case .choosing, .working:
                chooser
            case .done(let converted, let unchanged, let failed):
                Text(String(localized: "转好了 \(converted.count) 个文件"))
                    .font(.callout)
                if unchanged > 0 {
                    Text(String(localized: "有 \(unchanged) 个本来就是，没有动"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !failed.isEmpty {
                    Text(String(localized: "没转的：\(failed.joined(separator: String(localized: "、")))"))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Spacer()
                    if !converted.isEmpty {
                        Button("撤销") { model.undo() }
                    }
                    Button("完成", action: onClose)
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("完成", action: onClose)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .controlSize(.small)
    }

    private var subtitle: String {
        model.rows.count == 1 ? model.rows[0].url.lastPathComponent : String(localized: "\(model.rows.count) 个文件")
    }

    @ViewBuilder
    private var chooser: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(model.rows) { row in
                    rowView(row)
                }
            }
        }
        .frame(height: min(CGFloat(model.rows.count) * 46, 230))
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("转成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("转成", selection: $model.target) {
                    ForEach(TextEncodingTools.Encoding.targets) { encoding in
                        Text(encoding.title).tag(encoding)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            GridRow {
                Text("换行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("换行", selection: $model.lines) {
                    ForEach(TextEncodingTools.LineTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        Text(model.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            if model.phase == .working {
                ProgressView()
                    .controlSize(.small)
            }
            Button("转换") { model.convert() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.pending.isEmpty || model.phase == .working || model.isRefreshing)
        }
    }

    private func rowView(_ row: FileEncodingModel.Row) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.problem ?? row.text.map { TextEncodingTools.firstLine($0) } ?? "")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(row.problem == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            // 读错了（第一行是乱码）时换一种编码读
            Menu {
                ForEach(TextEncodingTools.Encoding.readable) { encoding in
                    Button(encoding.title) { model.setSource(encoding, for: row) }
                }
            } label: {
                Text([row.source?.title, row.lineEnding?.title].compactMap { $0 }.joined(separator: " · "))
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "第一行是乱码时，换一种编码读"))
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
}
