import AppKit
import SwiftUI
@testable import Pop

/// 整理文件夹卡片：换整理方式时预览跟着变；整理在后台做，整理完可以撤销。
@MainActor
final class TidyFolderModel: ObservableObject {
    nonisolated static let modeKey = "pop.tidyFolder.mode"

    nonisolated static var savedMode: FolderTidy.Mode {
        UserDefaults.standard.string(forKey: modeKey).flatMap(FolderTidy.Mode.init(rawValue:)) ?? .kind
    }

    enum Phase: Equatable {
        case preview
        case working
        case done(FolderTidy.Done)
        case failed(String)
    }

    let folder: URL
    @Published private(set) var items: [FolderTidy.Item]
    @Published var mode: FolderTidy.Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }
    @Published private(set) var phase = Phase.preview

    init(folder: URL, items: [FolderTidy.Item], mode: FolderTidy.Mode = TidyFolderModel.savedMode) {
        self.folder = folder
        self.items = items
        self.mode = mode
    }

    var plan: FolderTidy.Plan {
        FolderTidy.plan(items, in: folder, mode: mode)
    }

    var summary: String {
        let plan = self.plan
        guard !plan.moves.isEmpty else { return String(localized: "没有要整理的文件") }
        return String(localized: "会把 \(plan.moves.count) 个文件放进 \(plan.groups.count) 个子文件夹；子文件夹、隐藏文件和没下载完的文件不动")
    }

    func apply() {
        let plan = self.plan
        guard !plan.moves.isEmpty, phase == .preview else { return }
        phase = .working
        Task {
            let result: Result<FolderTidy.Done, FolderTidy.Failure> = await runInBackground {
                do {
                    return .success(try FolderTidy.apply(plan))
                } catch let failure as FolderTidy.Failure {
                    return .failure(failure)
                } catch {
                    return .failure(FolderTidy.Failure(message: error.localizedDescription))
                }
            }
            switch result {
            case .success(let done): phase = .done(done)
            case .failure(let failure): phase = .failed(failure.message)
            }
        }
    }

    func undo() {
        guard case .done(let done) = phase else { return }
        phase = .working
        let folder = self.folder
        Task {
            let result: Result<[FolderTidy.Item], FolderTidy.Failure> = await runInBackground {
                do {
                    try FolderTidy.undo(done)
                    return .success(try FolderTidy.items(in: folder))
                } catch let failure as FolderTidy.Failure {
                    return .failure(failure)
                } catch {
                    return .failure(FolderTidy.Failure(message: error.localizedDescription))
                }
            }
            switch result {
            case .success(let items):
                self.items = items
                phase = .preview
            case .failure(let failure):
                phase = .failed(failure.message)
            }
        }
    }
}

struct TidyFolderView: View {
    @ObservedObject var model: TidyFolderModel
    var onReveal: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "整理文件夹"), subtitle: model.folder.lastPathComponent, width: 400, onClose: onClose) {
            switch model.phase {
            case .preview, .working:
                preview
            case .done(let done):
                Text(String(localized: "整理好了 \(done.moves.count) 个文件，放进了 \(Set(done.moves.map { $0.to.deletingLastPathComponent() }).count) 个子文件夹"))
                    .font(.callout)
                HStack(spacing: 8) {
                    Spacer()
                    Button("撤销") { model.undo() }
                    Button("在访达中显示", action: onReveal)
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

    @ViewBuilder
    private var preview: some View {
        let plan = model.plan
        Picker("整理方式", selection: $model.mode) {
            ForEach(FolderTidy.Mode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(model.phase == .working)
        if plan.groups.isEmpty {
            Text("没有要整理的文件")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(plan.groups) { group in
                        HStack(spacing: 8) {
                            Image(systemName: group.symbol)
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            Text(group.name)
                            Spacer()
                            Text(String(localized: "\(group.count) 个"))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                    }
                }
            }
            .frame(height: min(CGFloat(plan.groups.count) * 30, 240))
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
            Button("整理") { model.apply() }
                .keyboardShortcut(.defaultAction)
                .disabled(plan.moves.isEmpty || model.phase == .working)
        }
    }
}
