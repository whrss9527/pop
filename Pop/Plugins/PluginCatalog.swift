import Foundation

/// Pop 的一个插件包：单独编译的功能，要用时从 GitHub 发布页下载装上，不用了可以卸载（见 PluginManager）。
struct PluginPackage: Identifiable, Hashable {
    /// 插件包的 ID，和插件包 Info.plist 里的 PopPluginID 一样，也是发布页上压缩包的名字（plugin-<ID>.zip）
    let id: String
    /// 插件包的文件名（不带 .bundle），和 project.yml 里的 target 名字一样
    let bundleName: String
    let name: String
    let summary: String
    let symbol: String
    let category: BuiltinCategory
    /// 提供的功能（功能 ID）
    let functions: [String]
    /// 存在 UserDefaults 里的偏好，卸载时一起删掉
    var defaultsKeys: [String] = []
}

/// 所有插件包，没装的也在：设置的「插件」页按它列出来，没装上也知道插件包叫什么、提供哪些功能。
enum PluginCatalog {
    static let packages: [PluginPackage] = [
        PluginPackage(id: "screenPen", bundleName: "PopScreenPen", name: String(localized: "屏幕画笔"),
                      summary: String(localized: "演示、录教程时直接在屏幕上画：画笔、荧光笔、箭头、方框、椭圆，笔迹可以几秒后自动消失，也可以留着去操作下面的窗口，录屏时一起录进去；Esc 或再用一次结束"),
                      symbol: "scribble.variable", category: .recording, functions: [BuiltinPluginID.screenPen]),
        PluginPackage(id: "cameraBubble", bundleName: "PopCameraBubble", name: String(localized: "摄像头小窗"),
                      summary: String(localized: "在屏幕角落用一个圆形小窗显示摄像头画面，录教程、演示时把自己也放进画面；拖动换位置，滚动或双击换大小，右键换形状和摄像头。再用一次关闭"),
                      symbol: "person.crop.circle", category: .recording, functions: [BuiltinPluginID.cameraBubble],
                      // 和插件包里 CameraBubble 的键一样
                      defaultsKeys: ["pop.cameraBubble.size", "pop.cameraBubble.shape"]),
        PluginPackage(id: "pointerHighlight", bundleName: "PopPointerHighlight", name: String(localized: "突出显示指针"),
                      summary: String(localized: "演示、录教程时在指针周围加一圈黄色光圈，按下鼠标时泛起波纹，让人一眼看到指针在哪；再用一次关闭"),
                      symbol: "cursorarrow.rays", category: .recording, functions: [BuiltinPluginID.pointerHighlight]),
        PluginPackage(id: "teleprompter", bundleName: "PopTeleprompter", name: String(localized: "提词器"),
                      summary: String(localized: "把选中的稿子放进屏幕上方的提词器，按设好的速度慢慢往上滚，对着摄像头读；空格暂停，↑↓ 调速度，录屏时不会录进去"),
                      symbol: "text.aligncenter", category: .recording, functions: [BuiltinPluginID.teleprompter],
                      // 和插件包里 TeleprompterModel 的键一样
                      defaultsKeys: ["pop.teleprompter.speed", "pop.teleprompter.fontSize"]),
    ]

    /// 插件包提供的所有功能
    static let functionIDs: Set<String> = Set(packages.flatMap(\.functions))

    static func package(id: String) -> PluginPackage? {
        packages.first { $0.id == id }
    }

    /// 提供这个功能的插件包；Pop 自带的功能返回 nil
    static func package(providing functionID: String) -> PluginPackage? {
        packages.first { $0.functions.contains(functionID) }
    }
}
