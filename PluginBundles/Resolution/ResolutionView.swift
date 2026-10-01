import AppKit
import SwiftUI
@testable import Pop

/// 分辨率卡片：上面选显示器，下面是这台能用的大小（看起来像多大）、刷新率，设成主显示器。
/// 外接显示器换了以后要在 15 秒内点「保留」，不然换回原来的：换成显示器不支持的模式、屏幕黑了时什么都不用做。
@MainActor
final class ResolutionModel: ObservableObject {
    /// 读写显示器的地方：这台 Mac，或者测试、演示时的假显示器
    struct Backend {
        var displays: @MainActor () -> [DisplayModes.Display]
        var apply: @MainActor (_ mode: DisplayModes.Mode, _ display: CGDirectDisplayID) -> Bool
        var makeMain: @MainActor (_ display: CGDirectDisplayID, _ displays: [DisplayModes.Display]) -> Bool

        static var system: Backend {
            Backend(displays: { DisplayModes.all() },
                    apply: { DisplayModes.apply($0, to: $1) },
                    makeMain: { DisplayModes.makeMain($0, among: $1) })
        }
    }

    /// 换了模式、等着确认的那台显示器，和到时候换回去的模式
    struct Pending: Equatable {
        let display: CGDirectDisplayID
        let previous: DisplayModes.Mode
        var remaining: Int
    }

    /// 外接显示器换了模式以后等几秒
    static let confirmSeconds = 15

    @Published private(set) var displays: [DisplayModes.Display] = []
    @Published var selectedID: CGDirectDisplayID?
    @Published private(set) var pending: Pending?
    /// 换不成时的说明
    @Published private(set) var message: String?

    private let backend: Backend
    private let usesTimers: Bool
    private var countdown: Timer?
    private var screensObserver: NSObjectProtocol?

    /// usesTimers 为 false 时不自己倒计时（测试里一秒一秒地调 tick）
    init(backend: Backend = .system, selecting display: CGDirectDisplayID? = nil, usesTimers: Bool = true) {
        self.backend = backend
        self.usesTimers = usesTimers
        displays = backend.displays()
        selectedID = displays.first { $0.id == display }?.id ?? displays.first?.id
    }

    var selected: DisplayModes.Display? {
        displays.first { $0.id == selectedID } ?? displays.first
    }

    var choices: [DisplayModes.Choice] {
        guard let selected else { return [] }
        return DisplayModes.choices(selected.modes, current: selected.current)
    }

    var rates: [DisplayModes.Mode] {
        guard let selected else { return [] }
        return DisplayModes.rates(selected.modes, current: selected.current)
    }

    /// 「保留这个分辨率吗？12 秒后换回原来的」
    var pendingText: String? {
        guard let pending else { return nil }
        return String(localized: "保留这个分辨率吗？\(pending.remaining) 秒后换回原来的")
    }

    func refresh() {
        displays = backend.displays()
        if let selectedID, !displays.contains(where: { $0.id == selectedID }) {
            self.selectedID = displays.first?.id
        }
        // 等着确认的显示器拔掉了：不用换回去了
        if let pending, !displays.contains(where: { $0.id == pending.display }) {
            stopCountdown()
        }
    }

    /// 换成这个模式：列表里的一种大小，或者一种刷新率
    func choose(_ mode: DisplayModes.Mode) {
        guard let display = selected, let current = display.current, !mode.same(as: current) else { return }
        // 另一台还在等确认：能点到这里说明看得见，那台就留着
        if let pending, pending.display != display.id {
            keep()
        }
        // 已经在等确认时又换了一次：到时候换回最早的那个
        let previous = pending?.previous ?? current
        guard backend.apply(mode, display.id) else {
            message = String(localized: "换不成 \(DisplayModes.sizeText(mode))（\(DisplayModes.rateText(mode.refreshRate))）")
            refresh()
            return
        }
        message = nil
        refresh()
        if display.isBuiltIn || mode.same(as: previous) {
            // 内建显示器换哪个都显示得出来；换回了原来的也不用再确认
            stopCountdown()
        } else {
            startCountdown(display: display.id, previous: previous)
        }
    }

    /// 留着现在的模式
    func keep() {
        stopCountdown()
    }

    /// 换回原来的模式
    func revert() {
        guard let pending else { return }
        stopCountdown()
        message = backend.apply(pending.previous, pending.display) ? nil : String(localized: "没能换回原来的分辨率")
        refresh()
    }

    /// 倒计时走一秒，到了就换回去
    func tick() {
        guard var pending else { return }
        pending.remaining -= 1
        if pending.remaining <= 0 {
            revert()
        } else {
            self.pending = pending
        }
    }

    /// 设成主显示器
    func makeMain() {
        guard let display = selected, !display.isMain else { return }
        message = backend.makeMain(display.id, displays) ? nil : String(localized: "没能把「\(display.name)」设成主显示器")
        refresh()
    }

    /// 卡片开着时跟着显示器的变化（插拔、在系统设置里改了）重新读
    func startObserving() {
        guard screensObserver == nil else { return }
        screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                                                 queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    /// 卡片关掉了（Esc、点到别处、关闭按钮）：还在等确认的话换回去，屏幕黑了时按 Esc 也能回到原来的样子
    func closed() {
        if let screensObserver {
            NotificationCenter.default.removeObserver(screensObserver)
        }
        screensObserver = nil
        revert()
    }

    private func startCountdown(display: CGDirectDisplayID, previous: DisplayModes.Mode) {
        countdown?.invalidate()
        countdown = nil
        pending = Pending(display: display, previous: previous, remaining: Self.confirmSeconds)
        guard usesTimers else { return }
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func stopCountdown() {
        countdown?.invalidate()
        countdown = nil
        pending = nil
    }
}

struct ResolutionView: View {
    @ObservedObject var model: ResolutionModel
    var onOpenSettings: () -> Void
    /// 「完成」：留着现在的模式，关掉卡片
    var onDone: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "分辨率"), width: 360, onClose: onClose) {
            if model.displays.count > 1 {
                Picker("显示器", selection: Binding(get: { model.selected?.id ?? 0 }, set: { model.selectedID = $0 })) {
                    ForEach(model.displays) { display in
                        Text(verbatim: display.name).tag(display.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if let display = model.selected {
                VStack(alignment: .leading, spacing: 2) {
                    Text("看起来像")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.choices) { choice in
                                ChoiceRow(choice: choice, isCurrent: choice.mode.size == display.current?.size) {
                                    model.choose(choice.mode)
                                }
                            }
                        }
                    }
                    .frame(height: min(CGFloat(model.choices.count) * ChoiceRow.height, ChoiceRow.height * 9.5))
                }
                if model.rates.count > 1, let current = display.current {
                    Picker("刷新率", selection: Binding(get: { current }, set: { model.choose($0) })) {
                        ForEach(model.rates, id: \.self) { mode in
                            Text(verbatim: DisplayModes.rateText(mode.refreshRate)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                if model.displays.count > 1 {
                    if display.isMain {
                        Label("主显示器：菜单栏和程序坞在这台上", systemImage: "menubar.rectangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("设为主显示器", action: model.makeMain)
                            .help("把菜单栏和程序坞挪到这台显示器上")
                    }
                }
            }
            if let text = model.pendingText {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .foregroundStyle(.orange)
                    Text(text)
                        .font(.callout)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("换回去", action: model.revert)
                    Button("保留", action: model.keep)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }
            if let message = model.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button("显示器设置", action: onOpenSettings)
                Spacer()
                if model.pending == nil {
                    Button("完成", action: onDone)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .controlSize(.small)
        .onAppear { model.startObserving() }
        .onDisappear { model.closed() }
    }
}

/// 一种大小：「1512 × 982」，系统默认的写着「默认」，会发虚的写着「低分辨率」；现在用的打勾
private struct ChoiceRow: View {
    /// 每行一样高，列表按行数定高度，九行以上才滚动
    static let height: CGFloat = 24

    let choice: DisplayModes.Choice
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(verbatim: DisplayModes.sizeText(choice.mode))
                    .font(.callout)
                    .monospacedDigit()
                if choice.isDefault {
                    Text("默认")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if choice.isBlurry {
                    Text("低分辨率")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("这个大小没有 HiDPI 模式，文字会发虚")
                }
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: Self.height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
