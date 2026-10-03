import EventKit
import Foundation
@testable import Pop

/// 把一件事加到「提醒事项」或「日历」。第一次用时系统会问要不要允许。
/// 读写日历数据库要等系统的日历服务（正在同步 iCloud 时会等好一会儿），都放在 queue 上做，不在主线程上等
enum ReminderService {
    struct Failure: Error, Equatable {
        let message: String
    }

    private static let queue = DispatchQueue(label: "Pop.Reminder", qos: .userInitiated)
    /// 第一次用到时才连日历服务（在后台）
    private static let store = EKEventStore()

    /// 加到默认的提醒事项列表；说了几点的在那个时间提醒
    static func addReminder(title: String, date: Date, hasTime: Bool, notes: String?) async throws {
        let granted: Bool
        do {
            granted = try await store.requestFullAccessToReminders()
        } catch {
            throw Failure(message: String(localized: "没能申请提醒事项的权限：\(error.localizedDescription)"))
        }
        guard granted else {
            throw Failure(message: String(localized: "没有提醒事项的权限：在「系统设置 → 隐私与安全性 → 提醒事项」里打开 Pop"))
        }
        try await onQueue {
            guard let list = store.defaultCalendarForNewReminders() else {
                throw Failure(message: String(localized: "没有找到提醒事项列表，先在「提醒事项」App 里建一个"))
            }
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.notes = notes
            reminder.calendar = list
            reminder.dueDateComponents = components(date, hasTime: hasTime)
            if hasTime {
                reminder.addAlarm(EKAlarm(absoluteDate: date))
            }
            do {
                try store.save(reminder, commit: true)
            } catch {
                throw Failure(message: String(localized: "没能保存：\(error.localizedDescription)"))
            }
        }
    }

    /// 加到默认日历：说了几点的是一小时的日程，没说的是全天
    static func addEvent(title: String, date: Date, hasTime: Bool, notes: String?) async throws {
        let granted: Bool
        do {
            // 只要写入权限：Pop 不需要看到日历里原有的日程
            granted = try await store.requestWriteOnlyAccessToEvents()
        } catch {
            throw Failure(message: String(localized: "没能申请日历的权限：\(error.localizedDescription)"))
        }
        guard granted else {
            throw Failure(message: String(localized: "没有日历的权限：在「系统设置 → 隐私与安全性 → 日历」里打开 Pop"))
        }
        try await onQueue {
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw Failure(message: String(localized: "没有找到可以添加日程的日历"))
            }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.notes = notes
            event.calendar = calendar
            event.isAllDay = !hasTime
            event.startDate = date
            event.endDate = hasTime ? date.addingTimeInterval(3600) : date
            do {
                try store.save(event, span: .thisEvent, commit: true)
            } catch {
                throw Failure(message: String(localized: "没能保存：\(error.localizedDescription)"))
            }
        }
    }

    /// 在 queue 上做完 work 再回来
    private static func onQueue(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 提醒事项的到期时间：没说几点的只有日期
    static func components(_ date: Date, hasTime: Bool, calendar: Calendar = .current) -> DateComponents {
        var components = calendar.dateComponents(hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day],
                                                 from: date)
        components.calendar = calendar
        components.timeZone = hasTime ? calendar.timeZone : nil
        return components
    }
}
