import SwiftUI

/// 证件照卡片：选底色和尺寸，预览跟着变；确认后另存一份放在原图旁边
struct IDPhotoView: View {
    @ObservedObject var model: IDPhotoModel
    var onSave: () -> Void
    var onClose: () -> Void

    private var hint: String {
        guard model.cutout != nil else { return "抠图在本机进行，不上传照片" }
        return model.message ?? "一寸 295×413、二寸 413×579 像素（300 dpi）；另存一份放在原图旁边，原图不动"
    }

    var body: some View {
        CardContainer(title: "证件照", subtitle: model.file.lastPathComponent, width: 400, onClose: onClose) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
                if let preview = model.preview {
                    Image(decorative: preview, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                } else if model.cutout == nil, let message = model.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    VStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在抠图…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 240)
            Picker("底色", selection: $model.background) {
                ForEach(IDPhoto.Background.allCases) { background in
                    Text(background.title).tag(background)
                }
            }
            .pickerStyle(.segmented)
            Picker("尺寸", selection: $model.size) {
                ForEach(IDPhoto.Size.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("存到原图旁边", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
            .controlSize(.small)
        }
    }
}
