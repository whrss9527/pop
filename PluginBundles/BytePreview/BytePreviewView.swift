import AppKit
import SwiftUI
@testable import Pop

/// 十六列字节保持整行，正文不用宿主的自动换行或长文字裁剪。
@MainActor
struct BytePreviewView: View {
    let preview: BytePreview.Snapshot
    let text: String
    let width: CGFloat
    let viewportHeight: CGFloat
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "文件字节预览", bundle: .bytePreview), width: width, onClose: onClose) {
            Text(verbatim: preview.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(preview.name)
            Text(verbatim: preview.truncated
                 ? String(localized: "仅显示前 4096 字节，后续内容未读取", bundle: .bytePreview)
                 : String(localized: "已显示 \(preview.data.count) 字节", bundle: .bytePreview))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if preview.data.isEmpty {
                Text("文件为空，没有可预览的字节", bundle: .bytePreview)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(verbatim: text)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(8)
                }
                .frame(height: viewportHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Spacer(minLength: 0)
                Button(action: onCopy) {
                    Label {
                        Text("复制预览", bundle: .bytePreview)
                    } icon: {
                        Image(systemName: "doc.on.doc")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(text.isEmpty)
            }
        }
    }
}
