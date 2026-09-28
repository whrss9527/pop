import AppKit
import ApplicationServices
import Combine
import ServiceManagement

enum Permissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统的辅助功能授权提示（只在未授权时出现）。
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 轮询辅助功能授权状态（系统没有可靠的授权变化通知）。
@MainActor
final class PermissionMonitor: ObservableObject {
    @Published private(set) var isTrusted = Permissions.isAccessibilityTrusted
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        let trusted = Permissions.isAccessibilityTrusted
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
