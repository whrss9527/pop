import AppKit
@testable import Pop

/// 插件包「加到提醒事项」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopReminderEntry)
final class ReminderEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ReminderPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：从一句话里认出时间和事情
        host.addDemoScene(PluginHost.DemoScene(name: "reminder", after: "history-search", order: 1, delay: 1.4, hold: 0, show: { demo in
            let draft = ReminderDraft(text: "明天下午3点和设计组过一遍新版本的截图")
            demo.overlay.showCard(ReminderCardView(draft: draft, onAdd: { _ in }, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct ReminderPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.reminder, name: String(localized: "加到提醒事项"), symbol: "checklist",
                          summary: String(localized: "从选中的文字里认出时间（明天下午 3 点、周五、10 月 8 日、半小时后……），加到「提醒事项」或者「日历」"),
                          accepts: [.text], maxLength: 500, check: .custom(CustomContentCheck("dateMention") { NaturalDate.parse($0) != nil }))

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        return .present(PluginPresentation { session in
            // 先认出时间和事情，可以再改
            let draft = ReminderDraft(text: text)
            session.showCard(ReminderCardView(draft: draft,
                                              onAdd: { [weak draft] target in
                                                  guard let draft else { return }
                                                  Self.add(draft, to: target, session: session)
                                              },
                                              onClose: { session.end() }))
        })
    }

    /// 加到提醒事项或日历：加好了提示一句，没加上就在卡片上说原因
    @MainActor static func add(_ draft: ReminderDraft, to target: ReminderDraft.Target, session: PluginSession) {
        draft.isSaving = true
        draft.errorMessage = nil
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let (date, hasTime, notes) = (draft.date, draft.hasTime, draft.notes)
        Task { @MainActor in
            do {
                switch target {
                case .reminder:
                    try await ReminderService.addReminder(title: title, date: date, hasTime: hasTime, notes: notes)
                case .calendar:
                    try await ReminderService.addEvent(title: title, date: date, hasTime: hasTime, notes: notes)
                }
                session.finish(toast: target == .reminder ? String(localized: "已加到提醒事项") : String(localized: "已加到日历"))
            } catch {
                draft.isSaving = false
                draft.errorMessage = (error as? ReminderService.Failure)?.message ?? error.localizedDescription
            }
        }
    }
}
