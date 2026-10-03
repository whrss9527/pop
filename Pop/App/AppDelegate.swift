import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    /// 启动完成前收到的 pop:// 链接，准备好之后再处理
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 跑单元测试时 App 只是测试宿主，不做事件拦截、权限申请这些系统层面的初始化。
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        // CI 的截图、启动测试里看主线程有没有卡住（从启动这一刻开始看）
        HangWatchdog.startIfRequested()
        let controller = AppController()
        self.controller = controller
        controller.start()
        for url in pendingURLs {
            controller.open(url)
        }
        pendingURLs = []
    }

    /// 打开 pop:// 链接（快捷指令、终端里的 open、启动器）
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller else {
            pendingURLs += urls
            return
        }
        for url in urls {
            controller.open(url)
        }
    }

    /// 正在录屏时退出（包括更新后重新启动）：先停下来把视频存好再退出
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ScreenRecorder.shared.isRecording else { return .terminateNow }
        ScreenRecorder.shared.stop {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
