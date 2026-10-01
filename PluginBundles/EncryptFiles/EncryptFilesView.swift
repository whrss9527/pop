import AppKit
import SwiftUI
@testable import Pop

/// 加密打包卡片：上面写着放进去的东西和大小，填名字、两遍密码、选加密方式，存在原来的位置；
/// 做好以后可以把原文件移到废纸篓（默认不勾）。
@MainActor
final class EncryptFilesModel: ObservableObject {
    enum Phase: Equatable {
        case editing
        case working
        case done(URL, size: Int64)
        case failed(String)
    }

    let items: [URL]
    /// 映像存在哪个文件夹
    let folder: URL
    @Published var name: String
    @Published var password = ""
    @Published var confirm = ""
    @Published var strength: EncryptedImage.Strength = .aes256
    /// 做好以后把原文件移到废纸篓
    @Published var trashOriginals = false
    @Published private(set) var phase: Phase = .editing
    @Published private(set) var size: Int64?
    private let create: ([URL], String, String, EncryptedImage.Strength, URL) async throws -> URL
    private let recycle: ([URL]) async -> [URL]

    init(items: [URL], size: Int64? = nil,
         create: @escaping ([URL], String, String, EncryptedImage.Strength, URL) async throws -> URL = { items, name, password, strength, folder in
             try await EncryptedImage.create(items, name: name, password: password, strength: strength, in: folder)
         },
         recycle: @escaping ([URL]) async -> [URL]) {
        self.items = items
        folder = items.first?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
        name = EncryptedImage.defaultName(for: items)
        self.size = size
        self.create = create
        self.recycle = recycle
    }

    /// 在后台算放进去的东西多大
    func measure() {
        guard size == nil else { return }
        let items = items
        Task {
            size = await runInBackground { EncryptedImage.size(of: items) }
        }
    }

    var hint: (message: String, blocking: Bool)? {
        EncryptedImage.passwordHint(password, confirm: confirm)
    }

    var canCreate: Bool {
        phase != .working && !(hint?.blocking ?? false)
    }

    /// 「3 项，一共 1.2 GB」
    var contents: String {
        let count = items.count == 1 ? items[0].lastPathComponent : String(localized: "\(String(items.count)) 项")
        guard let size else { return count }
        return String(localized: "\(count)，一共 \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
    }

    func start() {
        guard canCreate else { return }
        phase = .working
        let items = items
        let name = name
        let password = password
        let strength = strength
        let folder = folder
        let trash = trashOriginals
        Task {
            do {
                let image = try await create(items, name, password, strength, folder)
                if trash {
                    _ = await recycle(items)
                }
                let bytes = Int64((try? image.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                // 密码不留在内存里
                self.password = ""
                self.confirm = ""
                phase = .done(image, size: bytes)
            } catch let failure as EncryptedImage.Failure {
                phase = .failed(failure.message)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func retry() {
        phase = .editing
    }
}

struct EncryptFilesView: View {
    @ObservedObject var model: EncryptFilesModel
    var onReveal: (URL) -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "加密打包"), subtitle: model.contents, width: 400, onClose: onClose) {
            switch model.phase {
            case .editing, .working:
                form
            case .done(let image, let size):
                Text(String(localized: "做好了「\(image.lastPathComponent)」（\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))）"))
                    .font(.callout)
                Text("在任何一台 Mac 上双击它、输入密码就能打开。密码忘了就打不开了，记好它")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button("在访达中显示") { onReveal(image) }
                    Button("完成", action: onClose)
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button("重试") { model.retry() }
                    Button("完成", action: onClose)
                }
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var form: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                label("名字")
                HStack(spacing: 4) {
                    TextField("", text: $model.name)
                        .textFieldStyle(.roundedBorder)
                    Text(verbatim: ".dmg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GridRow {
                label("密码")
                SecureField("", text: $model.password)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                label("再输一遍")
                SecureField("", text: $model.confirm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.start() }
            }
            GridRow {
                label("加密强度")
                Picker("加密强度", selection: $model.strength) {
                    ForEach(EncryptedImage.Strength.allCases) { strength in
                        Text(strength.title).tag(strength)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .disabled(model.phase == .working)
        if let hint = model.hint, !model.password.isEmpty {
            Text(hint.message)
                .font(.caption)
                .foregroundStyle(hint.blocking ? Color.red : Color.orange)
        }
        Toggle("做好后把原文件移到废纸篓", isOn: $model.trashOriginals)
            .toggleStyle(.checkbox)
            .font(.caption)
            .disabled(model.phase == .working)
        HStack(spacing: 8) {
            Text(String(localized: "存在「\(model.folder.lastPathComponent)」里"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if model.phase == .working {
                ProgressView()
                    .controlSize(.small)
            }
            Button("加密打包") { model.start() }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canCreate)
        }
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }
}
