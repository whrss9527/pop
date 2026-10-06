import Foundation

/// 有新版本和更新后首次启动共用每日额度，按用户的本地日历计算。
enum UpdateNotificationGate {
    static let key = "pop.update.lastNotificationDate"

    static func alreadySentToday(defaults: UserDefaults = .standard, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let previous = defaults.object(forKey: key) as? Date else { return false }
        return calendar.isDate(previous, inSameDayAs: now)
    }

    static func claim(defaults: UserDefaults = .standard, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !alreadySentToday(defaults: defaults, now: now, calendar: calendar) else { return false }
        defaults.set(now, forKey: key)
        return true
    }
}
