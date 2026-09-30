import SwiftUI

/// PDF 密码卡片：给 PDF 加上打开密码，或者输入密码另存一份没有密码的。原文件不动。
@MainActor
final class PDFPasswordModel: ObservableObject {
    enum Mode {
        /// 加密码
        case add
        /// 去掉密码
        case remove
    }

    let pdf: URL
    let mode: Mode
    @Published var password = ""
    @Published var confirmation = ""
    /// 存的时候出的问题（比如密码不对），改了密码就不显示
    @Published var error: String?

    init(pdf: URL, mode: Mode) {
        self.pdf = pdf
        self.mode = mode
    }

    var canSubmit: Bool {
        switch mode {
        case .add: return !password.isEmpty && password == confirmation
        case .remove: return !password.isEmpty
        }
    }

    var hint: String {
        if let error {
            return error
        }
        switch mode {
        case .add:
            if !confirmation.isEmpty && password != confirmation {
                return String(localized: "两次输入的密码不一样")
            }
            return String(localized: "另存一份打开时要输入密码的 PDF，原文件不动。密码忘了就打不开了，记得记下来")
        case .remove:
            return String(localized: "输入打开这份 PDF 的密码，另存一份不用密码就能打开的，原文件不动")
        }
    }

    var isWarning: Bool {
        error != nil || (mode == .add && !confirmation.isEmpty && password != confirmation)
    }
}

struct PDFPasswordView: View {
    @ObservedObject var model: PDFPasswordModel
    var onSubmit: (String) -> Void
    var onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        CardContainer(title: model.mode == .add ? String(localized: "给 PDF 加密码") : String(localized: "去掉 PDF 的密码"), subtitle: model.pdf.lastPathComponent,
                      width: 380, onClose: onClose) {
            SecureField("密码", text: $model.password)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)
            if model.mode == .add {
                SecureField("再输一次", text: $model.confirmation)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
            }
            Text(model.hint)
                .font(.caption)
                .foregroundStyle(model.isWarning ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button(model.mode == .add ? String(localized: "存一份加密的") : String(localized: "存一份没有密码的"), action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSubmit)
            }
            .controlSize(.small)
        }
        .onChange(of: model.password) {
            model.error = nil
        }
        .task {
            focused = true
        }
    }

    private func submit() {
        if model.canSubmit {
            onSubmit(model.password)
        }
    }
}
