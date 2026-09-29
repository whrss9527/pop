import Foundation
import IOKit.pwr_mgt

/// 保持唤醒：一段时间内不让屏幕变暗、电脑睡眠（退出 Pop 时自动失效）。
@MainActor
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()

    /// 卡片上可以选的时长（分钟）
    static let presets = [30, 60, 120]

    @Published private(set) var isActive = false
    /// 什么时候结束；一直保持时为 nil
    @Published private(set) var endsAt: Date?

    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?

    /// 开始保持唤醒；minutes 为 nil 表示一直保持，直到手动停止。成功返回 true
    @discardableResult
    func start(minutes: Int?) -> Bool {
        stop()
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Pop 保持唤醒" as CFString, &id)
        guard result == kIOReturnSuccess else { return false }
        assertionID = id
        isActive = true
        if let minutes {
            let duration = TimeInterval(minutes * 60)
            endsAt = Date().addingTimeInterval(duration)
            timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stop()
                }
            }
        }
        return true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if isActive {
            IOPMAssertionRelease(assertionID)
        }
        assertionID = 0
        isActive = false
        endsAt = nil
    }

    /// 现在的状态，比如「保持唤醒到 15:30（还剩 25 分钟）」；没有保持唤醒时为 nil
    func statusText(now: Date = Date()) -> String? {
        guard isActive else { return nil }
        guard let endsAt else { return "一直保持唤醒，直到手动停止或退出 Pop" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let remaining = max(Int((endsAt.timeIntervalSince(now) / 60).rounded(.up)), 1)
        return "保持唤醒到 \(formatter.string(from: endsAt))（还剩 \(Self.title(minutes: remaining))）"
    }

    /// 30 → 「30 分钟」，60 → 「1 小时」，90 → 「1 小时 30 分钟」
    static func title(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(minutes) 分钟"
        case (_, 0): return "\(hours) 小时"
        default: return "\(hours) 小时 \(rest) 分钟"
        }
    }
}
