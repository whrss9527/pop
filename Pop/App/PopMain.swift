import AppKit

/// 手动启动 NSApplication：纯菜单栏 App，不需要 storyboard，也不走 SwiftUI App 生命周期
/// （后者无法从 AppKit 代码里可靠地打开设置窗口）。
@main
@MainActor
enum PopMain {
    private static var appDelegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}
