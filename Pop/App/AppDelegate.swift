import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 跑单元测试时 App 只是测试宿主，不做事件拦截、权限申请这些系统层面的初始化。
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let controller = AppController()
        self.controller = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    /// 在访达里再次打开 Pop 时显示设置窗口。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showSettings()
        return true
    }
}
