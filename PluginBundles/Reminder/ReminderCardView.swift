import SwiftUI
@testable import Pop

/// 「加到提醒事项」卡片的内容：从选中的文字里认出时间和事情，可以再改。
@MainActor
final class ReminderDraft: ObservableObject {
    enum Target {
        case reminder
        case calendar
    }

    @Published var title: String
    @Published var date: Date
    @Published var hasTime: Bool
    /// 原来选中的文字，放进备注
    let source: String
    /// 认出了时间（否则是默认的明天上午 9 点）
    let recognized: Bool
    @Published var errorMessage: String?
    @Published var isSaving = false

    init(text: String, now: Date = Date(), calendar: Calendar = .current) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        source = trimmed
        if let parsed = NaturalDate.parse(trimmed, now: now, calendar: calendar) {
            title = parsed.title.isEmpty ? trimmed : parsed.title
            date = parsed.date
            hasTime = parsed.hasTime
            recognized = true
        } else {
            title = trimmed
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            hasTime = true
            recognized = false
        }
    }

    /// 「9月30日 周三 15:00 · 明天」
    func summary(now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if Localization.isChinese {
            formatter.dateFormat = hasTime ? "M月d日 EEE HH:mm" : "M月d日 EEE"
        } else {
            formatter.setLocalizedDateFormatFromTemplate(hasTime ? "MMMdEEEHHmm" : "MMMdEEE")
        }
        var text = formatter.string(from: date)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: text += String(localized: " · 今天")
        case 1: text += String(localized: " · 明天")
        case 2: text += String(localized: " · 后天")
        case 3...: text += String(localized: " · \(days) 天后")
        default: text += String(localized: " · 已经过去了")
        }
        return text
    }

    /// 备注里放原文（和标题一样时不放）
    var notes: String? {
        source == title ? nil : source
    }
}

struct ReminderCardView: View {
    @ObservedObject var draft: ReminderDraft
    var onAdd: (ReminderDraft.Target) -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "加到提醒事项"), subtitle: draft.recognized ? nil : String(localized: "没认出时间，先按明天上午 9 点"), onClose: onClose) {
            TextField("要做的事", text: $draft.title)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                DatePicker("", selection: $draft.date,
                           displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : [.date])
                    .labelsHidden()
                Toggle("指定时间", isOn: $draft.hasTime)
                    .toggleStyle(.checkbox)
                Spacer(minLength: 0)
            }
            .controlSize(.small)
            Text(draft.summary())
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = draft.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: 8) {
                // ⌘↩ 的按钮在 macOS 26 上不会自己变成蓝色的默认按钮，写明
                Button("加到提醒事项") { onAdd(.reminder) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .help("⌘↩")
                Button("加到日历") { onAdd(.calendar) }
            }
            .controlSize(.small)
            .disabled(draft.isSaving || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
