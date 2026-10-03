import Foundation

/// Pop 的两种发行方式。
///
/// - GitHub 发布页：自己检查和安装更新，插件包装上时从发布页下载，可以从插件库下载插件。
/// - Mac App Store：开 App Sandbox，只能由 App Store 更新，不下载、不运行从网上拿来的代码（审核指南 2.5.2），
///   没有赞赏码（3.1.1），沙盒里弹不出辅助功能授权提示、注册不了只带 ⌥ 的全局快捷键。
///
/// App Store 版编译时带 `APP_STORE`（`scripts/build-app.sh` 的 `POP_SANDBOX=1`）。代码里尽量用 `Distribution.isAppStore`
/// 在运行时分开，两种版本都编得到；只有沙盒里根本用不了的才用 `#if APP_STORE`。
enum Distribution {
    #if APP_STORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif
}
