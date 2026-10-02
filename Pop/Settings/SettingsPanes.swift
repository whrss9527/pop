import AppKit
import SwiftUI
import Translation
import UniformTypeIdentifiers

// MARK: - 通用

struct GeneralSettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var permissions: PermissionMonitor
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String? = nil
    @State private var interfaceLanguage = InterfaceLanguage.stored()

    var body: some View {
        Form {
            Section("快速上手") {
                QuickStartRow(number: 1, title: String(localized: "授予辅助功能权限"),
                              detail: String(localized: "Pop 要靠它识别长按右键、读取选中的内容，所有处理都在本机完成。"))
                QuickStartRow(number: 2, title: String(localized: "按住右键，不要松开"),
                              detail: triggerHint)
                QuickStartRow(number: 3, title: String(localized: "菜单栏里的 ◎ 就是 Pop"),
                              detail: String(localized: "点它可以打开设置、暂停或退出。菜单栏图标太多时可能被刘海挡住；macOS 26 也可能在「系统设置 → 菜单栏」里把它隐藏了。找不到图标时，再次打开 Pop 应用就会弹出这个窗口。"))
            }

            Section("权限") {
                HStack(spacing: 10) {
                    Image(systemName: permissionSymbol)
                        .foregroundStyle(permissionReady ? Color.green : Color.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(permissionTitle)
                        Text(permissionDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !permissions.isTrusted {
                        Button("去授权") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                            if Distribution.isAppStore {
                                Permissions.revealApp()
                            }
                        }
                    } else if !permissions.isTriggerRunning {
                        Button("重启 Pop") {
                            AppRelauncher.relaunch()
                        }
                    }
                }
                // App Store 版的签名不会变，也不能在沙盒里清除授权记录
                if !permissions.isTrusted && !Distribution.isAppStore {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("列表里已经有 Pop、开关也打开了，但还是不生效？多半是更新后签名变了：先清除旧的授权记录，再授权一次。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("清除旧的授权记录") {
                            Task {
                                _ = await Permissions.resetAccessibility()
                                Permissions.requestAccessibility()
                                Permissions.openAccessibilitySettings()
                            }
                        }
                    }
                }
            }

            Section {
                Picker("鼠标", selection: store.binding(\.trigger.mode)) {
                    ForEach(TriggerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if store.settings.trigger.mode == .longPressRight {
                    LabeledContent("长按时长") {
                        HStack {
                            Slider(value: store.binding(\.trigger.holdDuration), in: TriggerSettings.holdDurationRange, step: 0.05)
                            Text("\(Int((store.settings.trigger.holdDuration * 1000).rounded())) ms")
                                .monospacedDigit()
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                    Toggle("松开右键后圆盘保持打开", isOn: store.binding(\.trigger.keepsRingOpen))
                }
                if store.settings.trigger.mode == .modifierRightClick {
                    Picker("修饰键", selection: store.binding(\.trigger.modifier)) {
                        ForEach(TriggerModifier.allCases) { modifier in
                            Text(modifier.title).tag(modifier)
                        }
                    }
                }
                Picker("键盘快捷键", selection: store.binding(\.trigger.hotKey)) {
                    ForEach(HotKeyPreset.available(keeping: store.settings.trigger.hotKey)) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Toggle("拖着文件左右晃几下，打开暂存架", isOn: store.binding(\.trigger.shakeToOpenShelf))
            } header: {
                Text("唤起方式")
            } footer: {
                Text(triggerFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("选中文字后显示工具条", isOn: store.binding(\.toolbar.enabled))
                if store.settings.toolbar.enabled {
                    BundleIDListView(keyPath: \.toolbar.excludedBundleIDs)
                }
            } header: {
                Text("选中文字后")
            } footer: {
                Text("拖着选中一段文字、双击选词或者三击选段后，在选区上方显示圆盘里前几个能处理这段文字的功能，点一下就执行，点「更多」打开完整的圆盘。只用辅助功能读取选中的文字，不碰剪贴板，读不到选区的 App 里不会出现；上面列出的 App 里也不出现。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ExcludedAppsView()
            } header: {
                Text("排除的 App")
            } footer: {
                Text("在这些 App 里不响应鼠标唤起，比如依赖右键拖拽的游戏、远程桌面和虚拟机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("其他") {
                Picker("界面语言", selection: $interfaceLanguage) {
                    ForEach(InterfaceLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .onChange(of: interfaceLanguage) { _, newValue in
                    InterfaceLanguage.store(newValue)
                }
                if interfaceLanguage != InterfaceLanguage.atLaunch {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("重新启动 Pop 后生效")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("立即重新启动") {
                            AppRelauncher.relaunch()
                        }
                    }
                }
                Toggle("登录时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        guard newValue != LaunchAtLogin.isEnabled else { return }
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("恢复默认设置", role: .destructive) {
                    store.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }
}

extension GeneralSettingsView {
    private var triggerFooter: String {
        let trigger = store.settings.trigger
        switch trigger.mode {
        case .longPressRight:
            let release = trigger.keepsRingOpen
                ? String(localized: "在圆心松开时圆盘保持打开，可以再用鼠标点选，点圆心或按 Esc 关闭。")
                : String(localized: "在圆心松开就关闭圆盘；想松开后再用鼠标点选的话，打开「松开右键后圆盘保持打开」。")
            return String(localized: "长按右键：短按仍然是系统右键菜单，按住超过设定时长才唤起 Pop。圆盘出来后按住不放，往某个方向一划再松开，就执行那一格的功能；") + release
        case .modifierRightClick, .middleClick:
            return String(localized: "按住时往某个方向一划再松开，可以直接执行那一格的功能；点一下的话圆盘保持打开，用鼠标点选，点圆心或按 Esc 关闭。")
        case .disabled:
            return String(localized: "只用键盘快捷键唤起：圆盘出来后用鼠标点选，或者按数字键选择，Esc 关闭。")
        }
    }

    private var permissionReady: Bool {
        permissions.isTrusted && permissions.isTriggerRunning
    }

    private var permissionSymbol: String {
        permissionReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var permissionTitle: String {
        if !permissions.isTrusted { return String(localized: "需要辅助功能权限") }
        return permissions.isTriggerRunning ? String(localized: "已获得辅助功能权限，Pop 已就绪") : String(localized: "已授权，但鼠标拦截还没生效")
    }

    private var permissionDetail: String {
        if !permissions.isTrusted {
            if Distribution.isAppStore {
                return String(localized: "点「去授权」，在打开的「辅助功能」列表下面点「+」选中 Pop（访达里已经选好了，也可以直接把它拖进列表），再打开开关。授权后不用重启，几秒内自动生效。")
            }
            return String(localized: "点「去授权」，在「系统设置 → 隐私与安全性 → 辅助功能」里打开 Pop。授权后不用重启，几秒内自动生效。")
        }
        if !permissions.isTriggerRunning {
            return String(localized: "偶尔刚授权时系统还没放行，点「重启 Pop」即可。")
        }
        return String(localized: "所有处理都在本机完成。")
    }

    private var triggerHint: String {
        let trigger = store.settings.trigger
        switch trigger.mode {
        case .longPressRight:
            let ms = Int((trigger.holdDuration * 1000).rounded())
            let ring = trigger.keepsRingOpen
                ? String(localized: "往要用的功能方向一划再松开，或者松开后再点选")
                : String(localized: "按住不放往要用的功能方向一划再松开即可，在圆心松开就关闭")
            return String(localized: "按住鼠标右键约 \(ms) 毫秒：选中了外文会直接翻译；其他情况弹出圆盘，\(ring)。普通点一下右键仍然是系统菜单。")
        case .modifierRightClick:
            return String(localized: "按住 \(trigger.modifier.title) 再点鼠标右键唤起 Pop。")
        case .middleClick:
            return String(localized: "点击鼠标中键唤起 Pop。")
        case .disabled:
            return trigger.hotKey == .none ? String(localized: "鼠标唤起已关闭，可以在下面设置一个键盘快捷键。") : String(localized: "用键盘快捷键 \(trigger.hotKey.title) 唤起 Pop。")
        }
    }
}

private struct QuickStartRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ExcludedAppsView: View {
    var body: some View {
        BundleIDListView(keyPath: \.trigger.excludedBundleIDs)
    }
}

/// 一组 App（按 Bundle ID 保存），可以添加和移除。
struct BundleIDListView: View {
    @EnvironmentObject var store: SettingsStore
    let keyPath: WritableKeyPath<AppSettings, [String]>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.settings[keyPath: keyPath], id: \.self) { bundleID in
                HStack(spacing: 8) {
                    if let icon = AppInfo.icon(for: bundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                    }
                    Text(AppInfo.name(for: bundleID))
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.update { $0[keyPath: keyPath].removeAll { $0 == bundleID } }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("添加 App…", action: addApps)
        }
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        let bundleIDs = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        let keyPath = self.keyPath
        store.update { settings in
            for id in bundleIDs where !settings[keyPath: keyPath].contains(id) {
                settings[keyPath: keyPath].append(id)
            }
        }
    }
}

// MARK: - 圆盘布局

struct RingSettingsView: View {
    @EnvironmentObject var store: SettingsStore
    let catalog: [PluginInfo]
    /// 正在编辑哪个 App 的圆盘；nil 是默认圆盘（所有没单独设置的 App）
    @State private var editing: String? = nil

    private var installed: [PluginInfo] {
        catalog.filter { store.settings.isInstalled($0.id) }
    }

    /// 正在编辑的布局
    private var layout: RingLayout {
        editing.flatMap { id in store.settings.appRings.first { $0.bundleID == id }?.layout } ?? store.settings.ring
    }

    private func updateLayout(_ change: @escaping (inout RingLayout) -> Void) {
        let editing = self.editing
        store.update { settings in
            if let editing, let index = settings.appRings.firstIndex(where: { $0.bundleID == editing }) {
                change(&settings.appRings[index].layout)
            } else {
                change(&settings.ring)
            }
        }
    }

    private var slotCount: Binding<Int> {
        Binding(
            get: { layout.slotCount },
            set: { count in updateLayout { $0.setSlotCount(count) } }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("已安装的功能")
                    .font(.headline)
                Text("拖到右边的格子上放置；拖到已占用的格子会互换位置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                List(installed) { info in
                    PluginRow(info: info, slotIndex: layout.index(of: info.id))
                        .draggable(info.id)
                }
                .listStyle(.bordered)
            }
            .frame(width: 250)

            VStack(spacing: 14) {
                appPicker
                RingEditorCanvas(layout: layout, catalog: catalog, installed: installed) { pluginID, index in
                    updateLayout { $0.place(pluginID, at: index) }
                }
                Picker("格子数", selection: slotCount) {
                    ForEach(RingLayout.allowedSlotCounts, id: \.self) { count in
                        Text("\(count) 格").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                HStack {
                    Text("格子上点右键可以直接选择功能或清空。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if editing == nil {
                        Button("恢复默认布局") {
                            store.update { $0.ring = .default }
                        }
                        .controlSize(.small)
                    } else {
                        Button("和默认圆盘一样") {
                            let base = store.settings.ring
                            updateLayout { $0 = base }
                        }
                        .controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .onChange(of: store.settings.appRings) {
            // 正在编辑的 App 圆盘被删掉了（比如从另一台 Mac 同步过来）：回到默认圆盘
            if let editing, !store.settings.appRings.contains(where: { $0.bundleID == editing }) {
                self.editing = nil
            }
        }
    }

    /// 选择编辑默认圆盘还是某个 App 专用的圆盘
    private var appPicker: some View {
        HStack(spacing: 8) {
            Picker("圆盘", selection: $editing) {
                Text("默认（所有 App）").tag(String?.none)
                ForEach(store.settings.appRings) { appRing in
                    Text(AppInfo.name(for: appRing.bundleID)).tag(Optional(appRing.bundleID))
                }
            }
            .frame(width: 260)
            Button("为 App 单独设置…", action: addAppRing)
                .controlSize(.small)
            if let editing {
                Button("删除") {
                    store.update { $0.appRings.removeAll { $0.bundleID == editing } }
                    self.editing = nil
                }
                .controlSize(.small)
                .help("这个 App 改回用默认圆盘")
            }
        }
    }

    /// 选一个 App，从默认圆盘复制一份给它单独调整
    private func addAppRing() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "单独设置")
        guard panel.runModal() == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        store.update { settings in
            if !settings.appRings.contains(where: { $0.bundleID == bundleID }) {
                settings.appRings.append(AppRing(bundleID: bundleID, layout: settings.ring))
            }
        }
        editing = bundleID
    }
}

struct PluginRow: View {
    let info: PluginInfo
    let slotIndex: Int?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: info.symbol)
                .frame(width: 22)
            Text(info.name)
            Spacer()
            Text(slotIndex.map { String(localized: "第 \($0 + 1) 格") } ?? String(localized: "未放置"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct RingEditorCanvas: View {
    let layout: RingLayout
    let catalog: [PluginInfo]
    let installed: [PluginInfo]
    let onPlace: (String?, Int) -> Void

    @State var targetedSlot: Int? = nil

    var body: some View {
        let geometry = RingGeometry(slotCount: max(layout.slotCount, 1), innerRadius: 46, outerRadius: 158)
        let size = geometry.diameter
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.07))
            Circle()
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
            Circle()
                .fill(Color.secondary.opacity(0.12))
                .frame(width: geometry.innerRadius * 2, height: geometry.innerRadius * 2)
            Text("0 号格在正上方\n顺时针排列")
                .font(.system(size: 9))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            ForEach(Array(layout.slots.enumerated()), id: \.offset) { index, pluginID in
                let offset = geometry.slotCenterOffset(index)
                slot(index: index, pluginID: pluginID)
                    .position(x: size / 2 + offset.dx, y: size / 2 - offset.dy)
            }
        }
        .frame(width: size, height: size)
    }

    private func slot(index: Int, pluginID: String?) -> some View {
        let info = pluginID.flatMap { id in catalog.first(where: { $0.id == id }) }
        let isTargeted = targetedSlot == index
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isTargeted ? Color.accentColor.opacity(0.25) : Color(nsColor: .controlBackgroundColor))
                Circle()
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isTargeted ? 2 : 1)
                if let info {
                    Image(systemName: info.symbol)
                        .font(.system(size: 18))
                } else {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            Text(info?.name ?? String(localized: "空"))
                .font(.caption2)
                .foregroundStyle(info == nil ? Color.secondary : Color.primary)
                .lineLimit(1)
        }
        .frame(width: 76)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            onPlace(id, index)
            return true
        } isTargeted: { targeted in
            if targeted {
                targetedSlot = index
            } else if targetedSlot == index {
                targetedSlot = nil
            }
        }
        .contextMenu {
            ForEach(installed) { plugin in
                Button(plugin.name) { onPlace(plugin.id, index) }
            }
            Divider()
            Button("清空这一格") { onPlace(nil, index) }
        }
        .help(info?.summary ?? String(localized: "空格子"))
    }
}

// MARK: - 直达规则

struct RulesSettingsView: View {
    @EnvironmentObject var store: SettingsStore
    let catalog: [PluginInfo]

    var body: some View {
        Form {
            Section {
                ForEach(store.settings.rules) { rule in
                    RuleRow(rule: rule, candidates: candidates(for: rule.condition)) { updated in
                        store.update { settings in
                            if let index = settings.rules.firstIndex(where: { $0.condition == updated.condition }) {
                                settings.rules[index] = updated
                            }
                        }
                    }
                }
            } header: {
                Text("选中的内容满足条件时，不弹圆盘，直接执行对应功能")
            } footer: {
                Text("从上到下依次匹配。没有命中任何规则、或者什么都没选中时，弹出圆盘。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func candidates(for condition: RuleCondition) -> [PluginInfo] {
        catalog.filter { info in
            store.settings.isInstalled(info.id) && !info.accepts.isEmpty && !info.accepts.isDisjoint(with: condition.impliedKinds)
        }
    }
}

struct RuleRow: View {
    let rule: DirectRule
    let candidates: [PluginInfo]
    let onChange: (DirectRule) -> Void

    var body: some View {
        HStack {
            Toggle(rule.condition.title, isOn: Binding(
                get: { rule.enabled },
                set: { enabled in
                    var updated = rule
                    updated.enabled = enabled
                    onChange(updated)
                }
            ))
            Spacer()
            Picker("", selection: Binding(
                get: { rule.pluginID ?? "" },
                set: { id in
                    var updated = rule
                    updated.pluginID = id.isEmpty ? nil : id
                    onChange(updated)
                }
            )) {
                Text("（弹出圆盘）").tag("")
                ForEach(candidates) { info in
                    Text(info.name).tag(info.id)
                }
            }
            .labelsHidden()
            .frame(width: 180)
            .disabled(!rule.enabled)
        }
    }
}

extension RuleCondition {
    /// 满足这个条件的内容一定具备的特征（比如「外文」一定也是「文本」）
    var impliedKinds: Set<ContentKind> {
        switch self {
        case .files: return [.files]
        case .image: return [.image]
        case .anyText: return [.text]
        default: return [.text, kind]
        }
    }
}

// MARK: - 翻译

struct TranslationSettingsView: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("默认用", selection: store.binding(\.translation.engine)) {
                    ForEach(TranslationEngine.allCases) { engine in
                        Text(engine.longTitle).tag(engine)
                    }
                }
            } header: {
                Text("翻译引擎")
            } footer: {
                Text("系统翻译用 macOS 自带的离线翻译：不联网、不收费、原文不离开这台 Mac，但长段落译得比较生硬。AI 翻译用「设置 → AI」里的模型；DeepL 要填自己的 API Key。选的引擎现在用不了时（还没填 Key、AI 没设置好）先用系统翻译。翻译卡片上可以临时换引擎，也可以选「对比」把几家的译文放在一起看。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("目标语言") {
                Picker("外文译为", selection: store.binding(\.translation.foreignTarget)) {
                    ForEach(LanguageOption.translationTargets) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                Picker("中文译为", selection: store.binding(\.translation.chineseTarget)) {
                    ForEach(LanguageOption.translationTargets) { option in
                        Text(option.name).tag(option.id)
                    }
                }
            }
            Section {
                DeepLKeyView()
            } header: {
                Text("DeepL")
            } footer: {
                Text("到 DeepL 官网申请 API Key（有免费版），填在这里。只有用 DeepL 翻译时才把原文发给 DeepL；Key 只存在这台 Mac 的钥匙串里，不跟设置一起同步。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LanguagePackView()
            } header: {
                Text("离线语言包")
            } footer: {
                Text("系统翻译第一次翻译某个语言组合前，需要先下载对应的语言包，也可以在「系统设置 → 通用 → 语言与地区 → 翻译语言」里管理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// 填 DeepL 的 API Key，保存后翻一句试试
struct DeepLKeyView: View {
    @State private var key = ""
    @State private var loaded = false
    @State private var test: TestState = .idle

    enum TestState: Equatable {
        case idle
        case testing
        case succeeded(String)
        case failed(String)
    }

    var body: some View {
        Group {
            SecureField("API Key", text: $key, prompt: Text("粘贴 DeepL 的 API Key"))
                .onSubmit(save)
            HStack(spacing: 8) {
                Button("保存并测试", action: runTest)
                    .disabled(test == .testing || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                status
                Spacer()
                Link("申请 API Key", destination: DeepLClient.signUpURL)
            }
        }
        .onAppear {
            guard !loaded else { return }
            key = DeepLKeyStore.read() ?? ""
            loaded = true
        }
        .onDisappear(perform: save)
    }

    @ViewBuilder
    private var status: some View {
        switch test {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .succeeded(let reply):
            Label("可以用了：Hello → \(reply)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(1)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }

    private func save() {
        guard loaded else { return }
        DeepLKeyStore.save(key)
    }

    private func runTest() {
        save()
        test = .testing
        let key = self.key
        Task {
            do {
                let reply = try await DeepLClient.translate("Hello", to: "zh-Hans", key: key)
                test = .succeeded(String(reply.prefix(30)))
            } catch {
                test = .failed((error as? DeepLClient.Failure)?.message ?? error.localizedDescription)
            }
        }
    }
}

struct LanguagePackView: View {
    @EnvironmentObject private var request: TranslationDownloadRequest
    @State private var status: LanguageAvailability.Status? = nil
    @State private var configuration: TranslationSession.Configuration? = nil
    @State private var message: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("原文", selection: $request.source) {
                    ForEach(LanguageOption.translationTargets) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Picker("译文", selection: $request.target) {
                    ForEach(LanguageOption.translationTargets) { option in
                        Text(option.name).tag(option.id)
                    }
                }
            }
            HStack {
                Text(statusText)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("下载语言包", action: startDownload)
                    .disabled(status == .unsupported || status == .installed)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: request.pairKey) {
            await refresh()
        }
        .translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
                await MainActor.run { message = String(localized: "语言包已就绪") }
            } catch {
                await MainActor.run { message = String(localized: "下载没有完成：\(error.localizedDescription)") }
            }
            await refresh()
        }
        .onAppear(perform: startPendingDownload)
        .onChange(of: request.pendingAutoStart) { _, _ in
            startPendingDownload()
        }
    }

    private var statusText: String {
        switch status {
        case .none: return String(localized: "正在检查…")
        case .some(.installed): return String(localized: "已安装")
        case .some(.supported): return String(localized: "未下载")
        case .some(.unsupported): return String(localized: "不支持这个语言组合")
        case .some(_): return String(localized: "未知状态")
        }
    }

    private func refresh() async {
        let source = Locale.Language(identifier: request.source)
        let target = Locale.Language(identifier: request.target)
        status = await LanguageAvailability().status(from: source, to: target)
    }

    private func startPendingDownload() {
        guard request.pendingAutoStart else { return }
        request.pendingAutoStart = false
        startDownload()
    }

    private func startDownload() {
        message = nil
        let source = Locale.Language(identifier: request.source)
        let target = Locale.Language(identifier: request.target)
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }
}

// MARK: - 同步

struct SyncSettingsView: View {
    @EnvironmentObject private var sync: CloudSync
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var plugins: PluginStore
    @State private var backupMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("通过 iCloud 同步设置", isOn: Binding(get: { sync.isEnabled }, set: { sync.setEnabled($0) }))
                    .disabled(!sync.isAvailableInBuild)
                LabeledContent("状态") {
                    Text(sync.statusText)
                        .foregroundStyle(.secondary)
                }
                if let date = sync.lastSyncDate {
                    LabeledContent("上次同步") {
                        Text(date.formatted(date: .abbreviated, time: .standard))
                    }
                }
                if let device = sync.lastRemoteDevice {
                    LabeledContent("云端配置来自") {
                        Text(device)
                    }
                }
                Button("立即同步") {
                    sync.syncNow()
                }
                .disabled(!sync.isEnabled || !sync.isAvailableInBuild)
            } footer: {
                Text("同步圆盘布局、已安装的功能、自己添加的插件、直达规则、唤起方式、翻译和剪贴板设置（剪贴板历史本身只留在本机）。数据存在你自己的 iCloud 账号里（iCloud 键值存储），Pop 没有任何服务器。多台 Mac 都改过时，以最后一次修改为准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !sync.isAvailableInBuild {
                Section {
                    Text("当前构建没有 iCloud 能力：需要用付费开发者账号签名，并使用带 iCloud 的 entitlements（见 README）。")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                HStack {
                    Button("导出设置…", action: exportSettings)
                    Button("导入设置…", action: importSettings)
                    Spacer()
                }
                if let backupMessage {
                    Text(backupMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("导出和导入")
            } footer: {
                Text("把设置和自己写的插件存成一个文件，在另一台 Mac 上导入；没有 iCloud 同步的版本也能这样搬过去。AI 的 API Key 只在本机钥匙串里，不会导出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func exportSettings() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let backup = SettingsBackup(settings: store.settings, plugins: plugins.manifests, appVersion: version)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = SettingsBackup.suggestedFileName()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try backup.encoded().write(to: url, options: .atomic)
            backupMessage = String(localized: "已导出到「\(url.lastPathComponent)」")
        } catch {
            backupMessage = String(localized: "导出失败：\(error.localizedDescription)")
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let backup: SettingsBackup
        do {
            backup = try SettingsBackup.decode(try Data(contentsOf: url))
        } catch {
            backupMessage = (error as? SettingsBackup.Failure)?.message ?? String(localized: "读不了这个文件：\(error.localizedDescription)")
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "导入「\(url.lastPathComponent)」？")
        alert.informativeText = String(localized: "会替换现在的\(backup.summary)。同名的插件会被覆盖，其他插件保留。")
        alert.addButton(withTitle: String(localized: "导入"))
        alert.addButton(withTitle: String(localized: "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var failed: [String] = []
        for manifest in backup.plugins {
            do {
                _ = try plugins.save(manifest)
            } catch {
                failed.append(manifest.name)
            }
        }
        store.update { settings in
            settings = backup.settings
        }
        backupMessage = failed.isEmpty ? String(localized: "已导入") : String(localized: "已导入，但这些插件没能保存：\(failed.joinedAsList())")
    }
}
