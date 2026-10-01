import SwiftUI
@testable import Pop

/// 批量重命名卡片的状态：改了规则马上算出新名字；改名在后台做，改完可以撤销。
@MainActor
final class RenameModel: ObservableObject {
    /// 按文件名排好的顺序
    let files: [URL]
    @Published var rule = BatchRename.Rule() {
        didSet { update() }
    }
    @Published private(set) var plan = BatchRename.Plan()
    /// 改好了的文件（撤销用）；还没改时是空的
    @Published private(set) var renamed: [BatchRename.Move] = []
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    /// 「拍摄时间」模式下每个文件的时间写法，第一次用到时在后台读
    private var dateNames: [URL: String]?

    init(files: [URL]) {
        self.files = BatchRename.ordered(files)
        update()
    }

    private func update() {
        if rule.mode == .captureDate, dateNames == nil {
            dateNames = [:]
            let files = self.files
            Task { [weak self] in
                let names = await runInBackground { BatchRename.dateNames(for: files) }
                guard let self else { return }
                self.dateNames = names
                self.update()
            }
        }
        plan = BatchRename.plan(files, rule: rule, dateNames: dateNames ?? [:])
    }

    func apply() {
        let plan = self.plan
        guard plan.canApply, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task { [weak self] in
            let result = await runInBackground { () -> Result<[BatchRename.Move], BatchRename.Failure> in
                do {
                    return .success(try BatchRename.apply(plan))
                } catch let failure as BatchRename.Failure {
                    return .failure(failure)
                } catch {
                    return .failure(BatchRename.Failure(message: error.localizedDescription))
                }
            }
            guard let self else { return }
            self.isWorking = false
            switch result {
            case .success(let moves):
                self.renamed = moves
            case .failure(let failure):
                self.errorMessage = failure.message
                self.update()
            }
        }
    }

    func undo() {
        let moves = renamed
        guard !moves.isEmpty, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task { [weak self] in
            let failure = await runInBackground { () -> String? in
                do {
                    try BatchRename.undo(moves)
                    return nil
                } catch {
                    return (error as? BatchRename.Failure)?.message ?? error.localizedDescription
                }
            }
            guard let self else { return }
            self.isWorking = false
            if let failure {
                self.errorMessage = failure
            } else {
                self.renamed = []
                self.update()
            }
        }
    }

    /// 预览下面那句话是不是在说有问题
    var summaryIsWarning: Bool {
        errorMessage != nil || plan.error != nil || plan.problems > 0
    }

    /// 预览下面的一句话
    var summary: String {
        if let error = plan.error { return error }
        if let problem = plan.items.first(where: { $0.problem != nil })?.problem {
            return plan.problems == 1 ? problem : String(localized: "\(plan.problems) 个名字不能用：\(problem)")
        }
        let count = plan.changes.count
        return count == 0 ? String(localized: "名字都没有变") : String(localized: "会改 \(count) 个文件的名字")
    }
}

struct RenameCardView: View {
    @ObservedObject var model: RenameModel
    var onReveal: ([URL]) -> Void
    var onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        CardContainer(title: String(localized: "批量重命名"), subtitle: String(localized: "\(model.files.count) 个文件"), width: 520, onClose: onClose) {
            if model.renamed.isEmpty {
                editor
            } else {
                finished
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        Picker("方式", selection: $model.rule.mode) {
            ForEach(BatchRename.Mode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        switch model.rule.mode {
        case .sequence:
            HStack(spacing: 8) {
                TextField("名字（后面接编号，可以不填）", text: $model.rule.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                Stepper("从 \(model.rule.start) 开始", value: $model.rule.start, in: 0...99_999)
                    .fixedSize()
                Picker("位数", selection: $model.rule.digits) {
                    ForEach(1...4, id: \.self) { digits in
                        Text("\(digits) 位").tag(digits)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        case .replace:
            HStack(spacing: 8) {
                TextField("查找", text: $model.rule.find)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                TextField(model.rule.useRegex ? String(localized: "替换为（$1 是第一个分组）") : String(localized: "替换为"), text: $model.rule.replacement)
                    .textFieldStyle(.roundedBorder)
                Toggle("正则", isOn: $model.rule.useRegex)
                    .toggleStyle(.checkbox)
                    .fixedSize()
            }
        case .affix:
            HStack(spacing: 8) {
                TextField("加在前面", text: $model.rule.prefix)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                TextField("加在后面（扩展名前）", text: $model.rule.suffix)
                    .textFieldStyle(.roundedBorder)
            }
        case .captureDate:
            Text("照片按拍摄时间命名，比如 2026-09-27 17.42.18；没有拍摄时间的按修改时间，同一秒的后面加编号。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .letterCase:
            Picker("大小写", selection: $model.rule.letterCase) {
                ForEach(BatchRename.LetterCase.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.plan.items.prefix(300)) { item in
                    HStack(spacing: 6) {
                        Text(item.source.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(item.newName)
                            .foregroundStyle(item.problem != nil ? Color.red : (item.changed ? Color.primary : Color.secondary))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(item.problem ?? item.newName)
                    }
                    .font(.system(size: 12))
                }
            }
            .padding(.trailing, 6)
        }
        .frame(height: min(CGFloat(model.plan.items.count) * 19 + 6, 190))

        Text(model.errorMessage ?? model.summary)
            .font(.caption)
            .foregroundStyle(model.summaryIsWarning ? Color.red : Color.secondary)
            .lineLimit(2)

        HStack(spacing: 8) {
            Spacer()
            Button(model.isWorking ? String(localized: "正在改名…") : String(localized: "重命名")) { model.apply() }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.plan.canApply || model.isWorking)
        }
        .controlSize(.small)
        .task {
            focused = true
        }
    }

    @ViewBuilder
    private var finished: some View {
        Label("已重命名 \(model.renamed.count) 个文件", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        if let error = model.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
        HStack(spacing: 8) {
            Button("在访达中显示") { onReveal(model.renamed.map(\.to)) }
            Button(model.isWorking ? String(localized: "正在撤销…") : String(localized: "撤销")) { model.undo() }
                .disabled(model.isWorking)
        }
        .controlSize(.small)
    }
}
