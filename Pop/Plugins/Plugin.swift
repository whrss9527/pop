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
    /// 里面有链接、邮箱、电话号码、IP 地址可以提取
    case extractable
    /// 字不多（逐个看字符），或者有看不见的字符
    case characters
    /// 至少两项的一列（或者一行用逗号隔开的）值
    case lineList
    /// 说到了时间（明天、周五、下午 3 点……）
    case dateMention
    /// JSON，或者读得出来的 YAML
    case yamlOrJSON
    /// XML（包括 SVG、plist）
    case xml
    /// 一条 SQL 语句
    case sql
    /// Base64 写的图片
    case base64Image
    /// 正好两个日期
    case twoDates
    /// 选中的是文件夹
    case folder
    /// 正好选中了两个文件夹
    case twoFolders
    /// 正好选中了两个文本文件
    case twoTextFiles
    /// Markdown 里至少有两个标题
    case markdownHeadings
    /// 身份证号、统一社会信用代码或者银行卡号
    case idNumber

    func matches(_ subject: String) -> Bool {
        switch self {
        case .numberList:
            return NumberStats.parse(subject) != nil
        case .cron:
            return CronExpression(subject) != nil
        case .colorPair:
            return ColorContrast.isColorPair(subject)
        case .extractable:
            return InfoExtractor.isWorthExtracting(subject)
        case .characters:
            return CharacterInspector.isApplicable(subject)
        case .lineList:
            return LineTools.isApplicable(subject)
        case .dateMention:
            return NaturalDate.parse(subject) != nil
        case .yamlOrJSON:
            return JSONFormatter.isJSON(subject) || YAMLConverter.looksLikeYAML(subject)
        case .xml:
            return XMLFormatter.isXML(subject)
        case .sql:
            return SQLFormatter.looksLikeSQL(subject)
        case .base64Image:
            return Base64Image.looksLikeImage(subject)
        case .twoDates:
            return DateSpan.find(in: subject) != nil
        case .folder:
            return FolderTree.isFolder(subject.components(separatedBy: "\n").first ?? "")
        case .twoFolders:
            let paths = subject.components(separatedBy: "\n").filter { !$0.isEmpty }
            return paths.count == 2 && paths.allSatisfy(FolderTree.isFolder)
        case .twoTextFiles:
            let paths = subject.components(separatedBy: "\n").filter { !$0.isEmpty }
            return paths.count == 2 && paths.allSatisfy { FileDiff.isTextFile(URL(fileURLWithPath: $0)) }
        case .markdownHeadings:
            return MarkdownTOC.headings(in: subject).count >= 2
        case .idNumber:
            return IDNumber.parse(subject) != nil
        }
    }
}

/// 结果卡片上的操作。
enum CardAction: Equatable {
    case copy(String)
    /// 写回原来的 App，替换选中的内容
    case replace(String)
    case open(URL)
    /// 用默认的 App 一个个打开（比如提取出来的几个链接）
    case openAll([URL])
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
    /// 把单词和译文加进生词本
    case addToVocabulary(word: String, translation: String, source: String?, target: String?)
    /// 转换图片文件，结果存在原图旁边
    case convertImages([URL], ImageConverter.Operation)
    /// 几张图片拼成一张，存在第一张旁边
    case stitchImages([URL], ImageStitcher.Direction)
    /// 转换视频，结果存在原视频旁边
    case convertVideos([URL], VideoConverter.Operation)
    /// PDF 的每一页存成图片，放在旁边的文件夹里
    case exportPDFPages(URL)
    /// 压缩 PDF，另存在旁边
    case compressPDF(URL)
    /// 打开 PDF 页面卡片（取出几页、每页存成一个 PDF）
    case pdfPages(URL)
    /// 打开 PDF 密码卡片：没有密码的加上密码，有密码的去掉
    case pdfPassword(URL)
    /// 把几张图片按顺序合成动图
    case animateImages([URL])
    /// 打开压缩到指定大小的卡片
    case imageSizeLimit([URL])
    /// 打开截取片段卡片
    case trimMedia(URL)
    /// 保持唤醒一段时间（分钟）；nil 表示一直保持
    case keepAwake(minutes: Int?)
    case stopKeepAwake
    /// 把这段 Markdown 转成富文本复制
    case copyRichText(String)
    /// 跟着短链接的跳转，看最后到哪个网址
    case expandLink(URL)
    /// 开始倒计时（秒）
    case startTimer(seconds: TimeInterval)
    case cancelTimer
    /// 停止「传到手机」
    case stopPhoneShare
    /// 把录音或视频里说的话转成文字（language 是语言代码，比如 zh-CN）
    case transcribe(URL, language: String)
    /// 把网页整页存成 PDF 或长图
    case captureWeb(URL, WebCapture.Format)
    /// 按比例裁剪图片，对准画面主体
    case cropImages([URL], SmartCrop.Ratio)
    /// 给图片里的人脸、个人信息（或者所有文字）打码，另存在原图旁边
    case redactImages([URL], Set<Redaction.Target>)
    /// 锁屏、熄屏、隐藏桌面图标这类系统操作
    case system(SystemAction)
    /// 把文字排成图片（换一种底色）
    case textImage(String, TextImage.Style)
    /// 把内容生成条形码
    case barcode(String)
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
    /// 可以切换的几段文字（比如同一份 JSON 生成的几种语言的代码），显示成分段选择器，「复制」复制当前这一段
    var tabs: [Tab] = []
    var buttons: [CardButton] = []

    struct Tab: Equatable, Identifiable {
        var title: String
        var text: String

        var id: String { title }
    }
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
    /// 列出唤起时前台 App 菜单里的快捷键
    case showMenuShortcuts
    /// 打开常用短语列表
    case showSnippets
    /// 选一个 App 打开文件或链接
    case chooseApp(OpenWithRequest)
    /// 打开正则测试卡片
    case regexTester(text: String)
    /// 打开「加到提醒事项」卡片
    case reminder(text: String)
    /// 打开批量重命名卡片
    case rename([URL])
    /// 打开生词本
    case showVocabulary
    /// 在这些文件夹里查找重复文件
    case findDuplicates([URL])
    /// 看这个文件夹里各部分占了多少空间
    case diskUsage(URL)
    /// 打开加水印的卡片
    case watermark([URL])
    /// 打开截取片段卡片
    case trimMedia(URL)
    /// 打开证件照卡片
    case idPhoto(URL)
    case failure(String)
}

struct PluginContext {
    var settings: AppSettings
    var openSettings: @MainActor () -> Void
    /// 唤起时前台 App 的名字
    var sourceAppName: String? = nil
    /// 唤起的位置（AppKit 屏幕坐标），贴图之类的功能在这附近显示
    var anchor: CGPoint? = nil
    /// 带格式地重新拷贝一次选中的内容（「转成 Markdown」用）
    var readRichSelection: (() async -> RichSelection?)? = nil
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
