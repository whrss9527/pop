import SwiftUI

/// 正则测试卡片的状态：改了表达式、选项或替换内容后稍等一下再在后台重新匹配。
@MainActor
final class RegexTesterModel: ObservableObject {
    let text: String
    @Published var pattern = "" {
        didSet { schedule() }
    }
    @Published var replacement = "" {
        didSet { schedule() }
    }
    @Published var options = RegexTester.Options() {
        didSet { schedule() }
    }
    @Published private(set) var result = RegexTester.Result()
    /// 替换后的全文；没填替换内容时为 nil
    @Published private(set) var replaced: String?

    /// 预览里最多显示这么多字（匹配仍然在全文里找）
    static let previewLength = 3000

    private var task: Task<Void, Never>?

    init(text: String, pattern: String = "") {
        self.text = text
        self.pattern = pattern
        if !pattern.isEmpty {
            schedule(delay: 0)
        }
    }

    private func schedule(delay: UInt64 = 150_000_000) {
        task?.cancel()
        let pattern = self.pattern
        let text = self.text
        let options = self.options
        let replacement = self.replacement
        task = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            let output = await runInBackground { () -> (RegexTester.Result, String?) in
                let result = RegexTester.run(pattern, on: text, options: options)
                let replaced = replacement.isEmpty || result.error != nil
                    ? nil : RegexTester.replace(pattern, with: replacement, in: text, options: options)
                return (result, replaced)
            }
            guard !Task.isCancelled, let self else { return }
            self.result = output.0
            self.replaced = output.1
        }
    }

    /// 匹配到的地方加上底色，相邻的两处颜色不同
    var highlighted: AttributedString {
        let preview = String(text.prefix(Self.previewLength))
        var attributed = AttributedString(preview)
        let length = (preview as NSString).length
        for (index, match) in result.matches.enumerated() where NSMaxRange(match.range) <= length && match.range.length > 0 {
            guard let range = Range(match.range, in: attributed) else { continue }
            attributed[range].backgroundColor = index.isMultiple(of: 2) ? Color.yellow.opacity(0.45) : Color.orange.opacity(0.45)
        }
        return attributed
    }

    var allMatches: String {
        result.matches.map(\.text).joined(separator: "\n")
    }

    /// 预览区的高度：按折行后大概有几行估算，最少两行、最多七行
    static func previewHeight(for text: String, width: CGFloat = 480) -> CGFloat {
        let lineHeight: CGFloat = 16
        let lines = String(text.prefix(previewLength)).components(separatedBy: "\n").reduce(0) { count, line in
            // 等宽字体 12 号：英文字母大约 7.2 点宽，汉字大约 12 点宽
            let lineWidth = line.reduce(CGFloat(0)) { $0 + ($1.isASCII ? 7.2 : 12) }
            return count + max(Int((lineWidth / width).rounded(.up)), 1)
        }
        return min(max(CGFloat(lines) * lineHeight + 8, lineHeight * 2 + 8), lineHeight * 7 + 8)
    }
}

struct RegexTesterView: View {
    @ObservedObject var model: RegexTesterModel
    /// 原文是在可以编辑的地方选中的文字时，才能「替换原文」
    var canReplace: Bool
    var onAction: (CardAction) -> Void
    var onClose: () -> Void
    @FocusState private var patternFocused: Bool

    private var subtitle: String {
        if model.result.error != nil { return "表达式有误" }
        guard !model.pattern.isEmpty else { return "" }
        let count = model.result.matches.count
        return model.result.truncated ? "\(count)+ 处匹配" : "\(count) 处匹配"
    }

    var body: some View {
        CardContainer(title: "正则测试", subtitle: subtitle, width: 520, onClose: onClose) {
            HStack(spacing: 6) {
                TextField("正则表达式，比如 \\d+", text: $model.pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .focused($patternFocused)
                Menu("常用") {
                    ForEach(RegexTester.presets) { preset in
                        Button(preset.title) { model.pattern = preset.pattern }
                    }
                }
                .fixedSize()
            }
            HStack(spacing: 14) {
                Toggle("忽略大小写", isOn: $model.options.ignoreCase)
                Toggle("^ $ 匹配每一行", isOn: $model.options.multiline)
                Toggle(". 也匹配换行", isOn: $model.options.dotAll)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            ScrollView {
                Text(model.highlighted)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 6)
            }
            .frame(height: RegexTesterModel.previewHeight(for: model.text))

            if let error = model.result.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !model.result.matches.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(model.result.matches.prefix(50).enumerated()), id: \.offset) { index, match in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                                Text(RegexTester.describe(match))
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 96)
            }

            TextField("替换为（$1 是第一个分组，$0 是整个匹配）", text: $model.replacement)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
            if let replaced = model.replaced {
                Text(replaced)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            FlowLayout(spacing: 8) {
                Button("复制所有匹配") { onAction(.copy(model.allMatches)) }
                    .disabled(model.result.matches.isEmpty)
                Button("复制表达式") { onAction(.copy(model.pattern)) }
                    .disabled(model.pattern.isEmpty)
                if let replaced = model.replaced {
                    Button("复制替换结果") { onAction(.copy(replaced)) }
                    if canReplace {
                        Button("替换原文") { onAction(.replace(replaced)) }
                    }
                }
            }
            .controlSize(.small)
        }
        .task {
            patternFocused = true
        }
    }
}
