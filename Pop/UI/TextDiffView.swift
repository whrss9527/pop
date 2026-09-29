import SwiftUI

/// 文本对比的结果：删去的行标红、新增的行标绿，行里具体改动的词颜色更深；很多行相同的地方折叠起来。
struct TextDiffView: View {
    let result: TextDiff.Result

    var body: some View {
        let rows = result.rows()
        let content = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .line(let line):
                    DiffLineView(line: line)
                case .skipped(let count):
                    Text("⋯ \(count) 行相同 ⋯")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)

        Group {
            // 行数多时放进固定高度的滚动区域
            if rows.count > 16 {
                ScrollView {
                    content
                }
                .frame(height: 320)
            } else {
                content.fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DiffLineView: View {
    let line: TextDiff.Line

    private var tint: Color? {
        switch line.kind {
        case .same: return nil
        case .removed: return .red
        case .added: return .green
        }
    }

    private var sign: String {
        switch line.kind {
        case .same: return " "
        case .removed: return "−"
        case .added: return "+"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(sign)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 10)
            text
                .foregroundStyle(line.kind == .same ? Color.secondary : Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(tint?.opacity(0.13) ?? .clear)
    }

    private var text: Text {
        guard !line.text.isEmpty else { return Text(" ") }
        var attributed = AttributedString()
        for segment in line.segments {
            var part = AttributedString(segment.text)
            if segment.changed, let tint {
                part.backgroundColor = tint.opacity(0.35)
            }
            attributed += part
        }
        return Text(attributed)
    }
}
