import Foundation

/// 插件的静态描述，设置界面、圆盘和分发规则都只依赖它。
struct PluginInfo: Identifiable, Hashable {
    enum Source: Hashable {
        case builtin
        /// 用户自己添加的插件（插件文件夹里的 JSON）
        case user
    }

    let id: String
    let name: String
    /// SF Symbol 名称
    let symbol: String
    let summary: String
    /// 能处理的内容类型；为空表示不需要选中内容（比如「打开设置」）。
    let accepts: Set<ContentKind>
    /// 选中的文字（或文件路径）还要匹配这个正则
    var pattern: String? = nil
    var minLength: Int? = nil
    var maxLength: Int? = nil
    var source: Source = .builtin
    /// 执行前先收起浮窗：截图、取色这类需要看清屏幕的功能
    var hidesOverlay = false
    /// 不需要选中内容，但选中了会用上（比如贴图：选中了图片就贴图片，没选中就先截图）
    var optionalContent = false
    /// 正则写不出来的内容检查
    var check: ContentCheck? = nil

    func canHandle(_ content: ClassifiedContent) -> Bool {
        guard accepts.isEmpty || !accepts.isDisjoint(with: content.kinds) else { return false }
        return matchesConstraints(content)
    }

    private func matchesConstraints(_ content: ClassifiedContent) -> Bool {
        let pattern = self.pattern ?? ""
        guard minLength != nil || maxLength != nil || !pattern.isEmpty || check != nil else { return true }
        let subject = content.text ?? content.files.map { $0.path(percentEncoded: false) }.joined(separator: "\n")
        guard !subject.isEmpty else { return false }
        if let minLength, subject.count < minLength { return false }
        if let maxLength, subject.count > maxLength { return false }
        if !pattern.isEmpty {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(subject.startIndex..., in: subject)
            guard regex.firstMatch(in: subject, options: [], range: range) != nil else { return false }
        }
        if let check, !check.matches(subject) { return false }
        return true
    }
}

/// 正则写不出来的内容检查，决定圆盘里要不要显示这个功能
enum ContentCheck: Hashable {
    /// 至少两个数：一列（每行一个）或者一行用逗号、空格隔开
    case numberList
    /// 5 段式的 cron 表达式
    case cron
    /// 两个颜色（文字和背景）
    case colorPair

    func matches(_ subject: String) -> Bool {
        switch self {
        case .numberList:
            return NumberStats.parse(subject) != nil
        case .cron:
            return CronExpression(subject) != nil
        case .colorPair:
            return ColorContrast.isColorPair(subject)
        }
    }
}

/// 结果卡片上的操作。
enum CardAction: Equatable {
    case copy(String)
    /// 写回原来的 App，替换选中的内容
    case replace(String)
    case open(URL)
    case reveal(URL)
    /// 复制 PNG 图片
    case copyImage(Data)
    /// PNG 图片存到「下载」文件夹，文件名不带扩展名
    case saveImage(Data, name: String)
    /// 把 PNG 图片贴在屏幕上
    case pinImage(Data)
    /// 把文字贴在屏幕上
    case pinText(String)
    /// 用翻译卡片翻译这段文字
    case translate(String)
    /// 转换图片文件，结果存在原图旁边
    case convertImages([URL], ImageConverter.Operation)
    /// PDF 的每一页存成图片，放在旁边的文件夹里
    case exportPDFPages(URL)
    /// 保持唤醒一段时间（分钟）；nil 表示一直保持
    case keepAwake(minutes: Int?)
    case stopKeepAwake
    /// 把这段 Markdown 转成富文本复制
    case copyRichText(String)
    /// 跟着短链接的跳转，看最后到哪个网址
    case expandLink(URL)
}

struct CardButton: Equatable, Identifiable {
    var title: String
    var action: CardAction

    var id: String { title }
}

/// 结果卡片的内容。
struct ResultCard: Equatable {
    /// 一行「名称 值」，可以单独复制（或替换原文）
    struct Row: Equatable, Identifiable {
        var label: String
        var value: String

        var id: String { label }
    }

    var title: String
    var body: String = ""
    var detail: String? = nil
    var monospaced = false
    /// 「复制」按钮复制的内容，为空时不显示按钮
    var copyText: String? = nil
    /// 「替换原文」写回的内容，为空时不显示按钮
    var replaceText: String? = nil
    var rows: [Row] = []
    /// 每一行都可以替换原文（比如大小写转换、编码转换）
    var rowsReplaceable = false
    /// 每一行最多显示几行字（完整内容仍然可以复制、替换）
    var rowLineLimit = 4
    /// PNG 图片（比如二维码）
    var image: Data? = nil
    /// 颜色样本（#RRGGBB 或 #RRGGBBAA）
    var swatchHex: String? = nil
    /// 一排颜色（#RRGGBB），点一下复制色值
    var palette: [String] = []
    /// 两段文字的差异（文本对比）
    var diff: TextDiff.Result? = nil
    /// 按排版显示的 Markdown
    var markdown: String? = nil
    var buttons: [CardButton] = []
}

enum PluginOutcome: Equatable {
    /// 已经完成（比如打开了网页），可以带一句轻提示
    case done(toast: String?)
    /// 展示结果卡片
    case card(ResultCard)
    /// 交给翻译卡片处理
    case translate(text: String, language: String?)
    /// 把文字写回原来的 App，替换选中的内容
    case replace(String)
    /// 打开「全部功能」列表
    case showAllPlugins
    /// 打开剪贴板历史
    case showClipboardHistory
    /// 打开 AI 卡片
    case ai(AIRequestSpec)
    /// 打开窗口布局卡片
    case showWindowLayouts
    /// 打开常用短语列表
    case showSnippets
    /// 选一个 App 打开文件或链接
    case chooseApp(OpenWithRequest)
    case failure(String)
}

struct PluginContext {
    var settings: AppSettings
    var openSettings: @MainActor () -> Void
    /// 唤起时前台 App 的名字
    var sourceAppName: String? = nil
    /// 唤起的位置（AppKit 屏幕坐标），贴图之类的功能在这附近显示
    var anchor: CGPoint? = nil
}

/// 所有功能都实现这个协议。内置功能是写死的 Swift 代码，用户插件由 manifest 描述（见 ManifestPlugin）。
protocol PopPlugin {
    var info: PluginInfo { get }
    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome
}

/// 内置功能 + 用户插件。用户插件变化时（新建、编辑、iCloud 同步）会发布更新，设置界面跟着刷新。
@MainActor
final class PluginRegistry: ObservableObject {
    let builtins: [any PopPlugin]
    @Published private(set) var userPlugins: [ManifestPlugin] = []

    init(builtins: [any PopPlugin]? = nil) {
        self.builtins = builtins ?? BuiltinPlugins.make()
    }

    var plugins: [any PopPlugin] {
        builtins + userPlugins.map { $0 as any PopPlugin }
    }

    var catalog: [PluginInfo] { plugins.map(\.info) }

    var builtinCatalog: [PluginInfo] { builtins.map(\.info) }

    var userCatalog: [PluginInfo] { userPlugins.map(\.info) }

    func plugin(id: String) -> (any PopPlugin)? {
        plugins.first { $0.info.id == id }
    }

    func info(id: String) -> PluginInfo? {
        plugin(id: id)?.info
    }

    func setUserManifests(_ manifests: [PluginManifest]) {
        let builtinIDs = Set(builtins.map(\.info.id))
        let updated = manifests.filter { !builtinIDs.contains($0.id) }.map(ManifestPlugin.init(manifest:))
        if updated != userPlugins {
            userPlugins = updated
        }
    }
}

/// 决定一次唤起是直接执行某个插件，还是弹出圆盘。
enum Router {
    enum Decision: Equatable {
        case direct(pluginID: String)
        case ring
    }

    static func decide(_ content: ClassifiedContent, settings: AppSettings, catalog: [PluginInfo]) -> Decision {
        guard !content.isEmpty else { return .ring }
        for rule in settings.rules where rule.enabled {
            guard let pluginID = rule.pluginID,
                  content.kinds.contains(rule.condition.kind),
                  settings.isInstalled(pluginID),
                  let info = catalog.first(where: { $0.id == pluginID }),
                  info.canHandle(content) else { continue }
            return .direct(pluginID: pluginID)
        }
        return .ring
    }
}
