import AppKit
import SwiftUI
@testable import Pop

/// 屏幕上方的提醒：该休息了、正在休息（倒计时）、休息好了
struct BreakReminderBanner: View {
    @ObservedObject var model: BreakReminder

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 380, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(18)
            .controlSize(.small)
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .reminder, .hidden:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("该休息一下了")
                            .font(.headline)
                        Text(verbatim: model.reminderDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("跳过", action: model.skip)
                    Button("5 分钟后提醒", action: model.snooze)
                    Button(String(localized: "休息 \(BreakReminder.lengthTitle(model.breakSeconds))"), action: model.takeBreak)
                        .keyboardShortcut(.defaultAction)
                }
            }
        case .onBreak:
            HStack(spacing: 12) {
                BreakProgressRing(progress: model.breakProgress)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "休息中，还剩 \(model.breakRemainingText)"))
                        .font(.headline)
                        .monospacedDigit()
                    Text(verbatim: model.tip)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("结束休息", action: model.endBreak)
            }
        case .finished:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                    .frame(width: 28)
                Text("休息好了，接着忙吧")
                    .font(.headline)
            }
        }
    }
}

/// 休息倒计时的进度圈
private struct BreakProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// 休息时盖住屏幕：主屏幕上写着倒计时、休息时做什么，「结束休息」或者 Esc 提前结束
struct BreakOverlayView: View {
    @ObservedObject var model: BreakReminder
    let showsCountdown: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
            if showsCountdown {
                VStack(spacing: 16) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 52, weight: .light))
                    Text("休息一下")
                        .font(.system(size: 28, weight: .semibold))
                    Text(verbatim: model.breakRemainingText)
                        .font(.system(size: 64, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text(verbatim: model.tip)
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.75))
                    Button {
                        model.endBreak()
                    } label: {
                        Text("结束休息")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .padding(.top, 6)
                    Text("按 Esc 也能提前结束")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
    }
}

/// 「休息提醒」卡片：开关、多久提醒一次、休息多久、休息时盖不盖住屏幕
struct BreakReminderView: View {
    @ObservedObject var model: BreakReminder
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "休息提醒"), width: 360, onClose: onClose) {
            Toggle(isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) })) {
                Text("连续用电脑一段时间后提醒我休息")
            }
            .toggleStyle(.switch)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: model.schedule.isDue || model.schedule.isOnBreak ? "figure.walk" : "clock")
                    .foregroundStyle(model.isEnabled ? Color.accentColor : .secondary)
                    .frame(width: 16)
                Text(verbatim: model.statusText)
                    .font(.callout)
                    .foregroundStyle(model.isEnabled ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("每隔", selection: Binding(get: { model.intervalMinutes }, set: { model.setInterval(minutes: $0) })) {
                ForEach(BreakReminder.intervalChoices, id: \.self) { minutes in
                    Text(BreakReminder.durationText(TimeInterval(minutes) * 60)).tag(minutes)
                }
            }
            Picker("休息", selection: Binding(get: { model.breakSeconds }, set: { model.setBreakLength(seconds: $0) })) {
                ForEach(BreakReminder.lengthChoices, id: \.self) { seconds in
                    Text(BreakReminder.lengthTitle(seconds)).tag(seconds)
                }
            }
            Toggle("休息时盖住屏幕", isOn: $model.fullScreen)
                .toggleStyle(.checkbox)
            Text("离开电脑 3 分钟以上（休息时长更长时按休息时长）就算休息过了，合上盖子睡着的时间也算，回来重新计时；有 App 在放视频、开视频会议（不让屏幕变暗）时不提醒，这段时间也不算休息。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if model.schedule.isOnBreak {
                    Button("结束休息", action: model.endBreak)
                } else {
                    Button("现在休息", action: model.takeBreak)
                }
                Spacer()
                Button("完成", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
        .onAppear { model.tick() }
    }
}
