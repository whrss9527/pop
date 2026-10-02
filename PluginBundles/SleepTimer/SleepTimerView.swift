import AppKit
import SwiftUI
@testable import Pop

/// 「定时睡眠」卡片：到点以后睡眠、熄屏、锁屏还是关机，多久以后（点一下就开始）或者到几点；定好以后看还剩多久，推迟、取消
struct SleepTimerView: View {
    @ObservedObject var model: SleepTimer
    var onClose: () -> Void
    /// 「到几点」：默认一小时以后，按五分钟取整
    @State private var atTime: Date

    init(model: SleepTimer, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        // 演示、截图时按造好的时刻
        _atTime = State(initialValue: Self.roundedHourLater(from: model.environment.now(), calendar: model.environment.calendar))
    }

    var body: some View {
        CardContainer(title: String(localized: "定时睡眠", bundle: .sleepTimer), width: 380, onClose: onClose) {
            VStack(alignment: .leading, spacing: 10) {
                if let pending = model.pending {
                    activeSection(pending)
                } else {
                    setupSection
                }
                if let message = model.message {
                    Label {
                        Text(verbatim: message)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.callout)
                }
                Text("到点前一分钟在屏幕上方提示，可以推迟、取消。关机时有没存的文稿，App 会照常问，可能关不成。", bundle: .sleepTimer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        Text("完成", bundle: .sleepTimer)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .controlSize(.small)
    }

    // MARK: - 还没定

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(selection: Binding(get: { model.action }, set: { model.setAction($0) })) {
                ForEach(SleepTimerAction.allCases) { action in
                    Text(verbatim: action.title).tag(action)
                }
            } label: {
                Text("到点以后", bundle: .sleepTimer)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // 按字的长短排；英文用短的说法（Display Off、Lock），四段放得进卡片
            .fixedSize()
            VStack(alignment: .leading, spacing: 6) {
                Text("多久以后", bundle: .sleepTimer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(SleepTimer.durations, id: \.self) { minutes in
                        Button {
                            Task { await model.start(minutes: minutes) }
                        } label: {
                            Text(verbatim: SleepTimer.durationTitle(minutes))
                        }
                        .buttonStyle(.bordered)
                        .tint(minutes == model.minutes ? Color.accentColor : nil)
                    }
                }
            }
            HStack(spacing: 8) {
                Text("或者到", bundle: .sleepTimer)
                DatePicker(selection: $atTime, displayedComponents: .hourAndMinute) {
                    Text("或者到", bundle: .sleepTimer)
                }
                .labelsHidden()
                .datePickerStyle(.field)
                .fixedSize()
                Button {
                    Task { await model.start(at: atTime) }
                } label: {
                    Text("开始", bundle: .sleepTimer)
                }
                Spacer(minLength: 0)
            }
            Toggle(isOn: Binding(get: { model.fades }, set: { model.setFades($0) })) {
                Text("最后一分钟慢慢调小音量（睡眠、关机时）", bundle: .sleepTimer)
            }
            .toggleStyle(.checkbox)
            .disabled(!model.action.fadesVolume)
        }
    }

    // MARK: - 定好了

    private func activeSection(_ pending: SleepTimer.Pending) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: pending.action.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                // 倒计时每秒走一下；演示、截图时按造好的时刻
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(verbatim: SleepTimer.clock(pending.deadline.timeIntervalSince(model.environment.now())))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Text(verbatim: pending.action.at(SleepTimer.time(pending.deadline)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button(String(localized: "推迟 \(String(SleepTimer.postponeMinutes)) 分钟", bundle: .sleepTimer)) { model.postpone() }
                Button(role: .destructive) {
                    model.cancel()
                } label: {
                    Text("取消定时", bundle: .sleepTimer)
                }
            }
        }
    }

    /// 一小时以后，往后取整到五分钟（23:01:19 → 0:05）
    static func roundedHourLater(from now: Date, calendar: Calendar) -> Date {
        let later = now.addingTimeInterval(3600)
        let start = calendar.dateInterval(of: .minute, for: later)?.start ?? later
        let minute = calendar.component(.minute, from: start)
        return start.addingTimeInterval(TimeInterval((5 - minute % 5) % 5 * 60))
    }
}

// MARK: - 屏幕上方的提示

/// 最后一分钟的提示：「0:42 后睡眠」，可以推迟、取消
struct SleepTimerBanner: View {
    @ObservedObject var model: SleepTimer

    var body: some View {
        HStack(spacing: 12) {
            if let pending = model.pending {
                Image(systemName: pending.action.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        Text(verbatim: pending.action.after(SleepTimer.clock(pending.deadline.timeIntervalSince(model.environment.now()))))
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                    }
                    Text(verbatim: Self.detail(pending.action, fading: model.fades && pending.action.fadesVolume))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                Button(String(localized: "推迟 \(String(SleepTimer.postponeMinutes)) 分钟", bundle: .sleepTimer)) { model.postpone() }
                Button {
                    model.cancel()
                } label: {
                    Text("取消", bundle: .sleepTimer)
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 400)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(18)
    }

    static func detail(_ action: SleepTimerAction, fading: Bool) -> String {
        if action == .shutDown {
            return String(localized: "没存的文稿 App 会问", bundle: .sleepTimer)
        }
        return fading ? String(localized: "正在慢慢调小音量", bundle: .sleepTimer) : String(localized: "不用的话点「取消」", bundle: .sleepTimer)
    }
}

/// 提示的窗口：在普通窗口上面，不抢焦点，全屏的 App 上面也有；按钮点得到
final class SleepTimerBannerPanel: NSPanel {
    private let hosting: NSHostingView<SleepTimerBanner>

    init(rootView: SleepTimerBanner) {
        hosting = NSHostingView(rootView: rootView)
        super.init(contentRect: CGRect(origin: .zero, size: hosting.fittingSize), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = hosting
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }

    /// 放在指针所在屏幕的上方正中，菜单栏下面
    func place(on screen: NSScreen? = nil) {
        let pointer = NSEvent.mouseLocation
        guard let screen = screen ?? NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else { return }
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height, width: size.width, height: size.height), display: true)
    }
}
