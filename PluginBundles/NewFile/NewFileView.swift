import AppKit
import SwiftUI
@testable import Pop

/// 新建文件卡片：选内容（空白、选中的文字、剪贴板）、种类和名字；种类和名字里的扩展名互相跟着变。
@MainActor
final class NewFileModel: ObservableObject {
    nonisolated static let kindKey = "pop.newFile.kind"

    enum Source: String, Identifiable {
        case blank
        case selection
        case clipboardText
        case clipboardImage

        var id: String { rawValue }

        var title: String {
            switch self {
            case .blank: return String(localized: "空白")
            case .selection: return String(localized: "选中的文字")
            case .clipboardText: return String(localized: "剪贴板里的文字")
            case .clipboardImage: return String(localized: "剪贴板里的图片")
            }
        }
    }

    let folder: URL
    let selection: String?
    let clipboardText: String?
    /// 剪贴板里的图片（PNG）
    let clipboardImage: Data?
    @Published var source: Source {
        didSet {
            guard source != oldValue else { return }
            // 图片存成 PNG；换回文字时用选着的种类
            name = (base as NSString).appendingPathExtension(source == .clipboardImage ? "png" : kind.ext) ?? name
        }
    }
    @Published var kind: NewFileMaker.Kind {
        didSet {
            guard kind != oldValue, source != .clipboardImage else { return }
            name = (base as NSString).appendingPathExtension(kind.ext) ?? name
        }
    }
    /// 名字（带扩展名）；写上认识的扩展名时种类跟着变
    @Published var name: String {
        didSet {
            if source != .clipboardImage, let typed = NewFileMaker.Kind.of(extension: (name as NSString).pathExtension), typed != kind {
                kind = typed
            }
        }
    }
    @Published private(set) var error: String?

    init(folder: URL, selection: String?, clipboardText: String?, clipboardImage: Data?, kind: NewFileMaker.Kind? = nil) {
        self.folder = folder
        let selection = selection.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        self.selection = selection
        self.clipboardText = clipboardText.flatMap { $0.isEmpty ? nil : $0 }
        self.clipboardImage = clipboardImage
        let kind = kind ?? UserDefaults.standard.string(forKey: Self.kindKey).flatMap(NewFileMaker.Kind.init(rawValue:)) ?? .text
        self.kind = kind
        source = selection != nil ? .selection : .blank
        name = NewFileMaker.untitled + "." + kind.ext
    }

    /// 能选的内容：空白，还有有的那几种
    var sources: [Source] {
        [Source.blank] + [selection.map { _ in Source.selection }, clipboardText.map { _ in Source.clipboardText },
                    clipboardImage.map { _ in Source.clipboardImage }].compactMap { $0 }
    }

    /// 不带扩展名的名字
    var base: String {
        let trimmed = (name as NSString).deletingPathExtension
        return trimmed.isEmpty ? NewFileMaker.untitled : trimmed
    }

    var content: NewFileMaker.Content {
        switch source {
        case .blank: return .blank
        case .selection: return .text(selection ?? "")
        case .clipboardText: return .text(clipboardText ?? "")
        case .clipboardImage: return clipboardImage.map { .image($0) } ?? .blank
        }
    }

    /// 要存进去的文字（卡片上预览前几行）
    var previewText: String? {
        if case .text(let text) = content { return text }
        return nil
    }

    var fileName: String {
        NewFileMaker.fileName(name, ext: source == .clipboardImage ? "png" : kind.ext)
    }

    /// 新建好的文件；出错时为 nil，错误写在 error 里
    func create() -> URL? {
        let fileName = self.fileName
        let ext = (fileName as NSString).pathExtension
        let kind = source == .clipboardImage ? nil : NewFileMaker.Kind.of(extension: ext)
        let data = NewFileMaker.data(kind: kind, content: content, title: (fileName as NSString).deletingPathExtension)
        do {
            let url = try NewFileMaker.create(in: folder, name: fileName, data: data, executable: kind == .shell)
            if source != .clipboardImage {
                UserDefaults.standard.set(self.kind.rawValue, forKey: Self.kindKey)
            }
            error = nil
            return url
        } catch let failure as NewFileMaker.Failure {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
        return nil
    }
}

struct NewFileView: View {
    @ObservedObject var model: NewFileModel
    var onCreate: (_ open: Bool) -> Void
    var onClose: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        CardContainer(title: String(localized: "新建文件"), subtitle: model.folder.lastPathComponent, width: 400, onClose: onClose) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(String(localized: "存到「\(model.folder.lastPathComponent)」"))
                Spacer(minLength: 0)
            }
            .font(.caption)
            .help(model.folder.path(percentEncoded: false))
            if model.sources.count > 1 {
                Picker("内容", selection: $model.source) {
                    ForEach(model.sources) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if model.source != .clipboardImage {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(NewFileMaker.Kind.allCases) { kind in
                        chip(kind)
                    }
                }
            }
            if let text = model.previewText {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
            TextField("文件名", text: $model.name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onCreate(true) }
            if let error = model.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("新建") { onCreate(false) }
                Button("新建并打开") { onCreate(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
    }

    /// 种类：选中的填上强调色
    private func chip(_ kind: NewFileMaker.Kind) -> some View {
        let selected = model.kind == kind
        return Button {
            model.kind = kind
        } label: {
            VStack(spacing: 1) {
                Text(kind.title)
                    .lineLimit(1)
                Text(".\(kind.ext)")
                    .font(.caption2)
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor : Color.primary.opacity(0.06)))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
