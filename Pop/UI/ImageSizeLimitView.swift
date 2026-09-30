import SwiftUI

/// 压缩到指定大小的卡片：点一档（100 KB、200 KB……）或者自己写多少 KB，每张图另存一份不超过这个大小的 JPEG。
struct ImageSizeLimitView: View {
    let files: [URL]
    var onCompress: (Int) -> Void
    var onClose: () -> Void
    @State private var custom = ""
    @FocusState private var focused: Bool

    private var subtitle: String {
        files.count == 1 ? files[0].lastPathComponent : "\(files.count) 张图片"
    }

    /// 说明，带上现在一共多大
    private var note: String {
        let bytes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
        let base = "存成 JPEG：先降低画质，还不够就缩小尺寸，另存一份，原图不动。"
        return bytes > 0 ? base + "现在一共 \(FileInfo.shortSize(Int64(bytes)))。" : base
    }

    /// 写的数字按 KB 算
    private var customLimit: Int? {
        guard let value = Int(custom.trimmingCharacters(in: .whitespaces)), value > 0, value <= 100_000 else { return nil }
        return value * 1000
    }

    var body: some View {
        CardContainer(title: "压缩到指定大小", subtitle: subtitle, width: 420, onClose: onClose) {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(ImageConverter.sizeLimits, id: \.self) { limit in
                    Button(ImageConverter.sizeLabel(limit)) {
                        onCompress(limit)
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("其他大小", text: $custom)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .focused($focused)
                    .onSubmit(submitCustom)
                Text("KB")
                    .foregroundStyle(.secondary)
                Button("压缩", action: submitCustom)
                    .keyboardShortcut(.defaultAction)
                    .disabled(customLimit == nil)
                Spacer()
            }
        }
        .controlSize(.small)
    }

    private func submitCustom() {
        if let limit = customLimit {
            onCompress(limit)
        }
    }
}
